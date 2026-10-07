import { readFile, mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL, fileURLToPath } from 'node:url';

export function campaignLink(id) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id)) throw new Error('invalid_campaign_id');
  const url = new URL('https://play.google.com/store/apps/details');
  url.searchParams.set('id', 'com.kyoutube.app');
  url.searchParams.set('referrer', new URLSearchParams({ utm_source: 'youtube',
    utm_medium: 'shorts', utm_campaign: id }).toString());
  return url.toString();
}

export function videoMetadata(campaign, channelId, privacy) {
  if (!['private', 'public', 'unlisted'].includes(privacy)) throw new Error('invalid_privacy');
  return { snippet: { title: campaign.title,
    description: `${campaign.description}\n\n채널 프로필의 앱 링크를 확인하세요.\n${campaignLink(campaign.id)}\n\n#RecipeScout #레시피스카우트 #Shorts`,
    categoryId: '26', channelId, tags: ['Recipe Scout', '레시피 스카우트'] },
    status: { privacyStatus: privacy, selfDeclaredMadeForKids: false } };
}

async function checked(response, code) {
  if (!response.ok) throw new Error(code); // Never log upstream responses or secrets.
  return response.json();
}

export async function uploadVideo({ campaign, video, token, channelId, privacy, fetcher = fetch, onInitiated = () => {} }) {
  const init = await fetcher('https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status', {
    method: 'POST', signal: AbortSignal.timeout(30000), headers: { Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json', 'X-Upload-Content-Type': 'video/mp4',
      'X-Upload-Content-Length': String(video.length) },
    body: JSON.stringify(videoMetadata(campaign, channelId, privacy)),
  });
  if (!init.ok) throw new Error('youtube_init_failed');
  const location = init.headers.get('location');
  if (!location || new URL(location).hostname !== 'www.googleapis.com' || !location.startsWith('https://')) {
    throw new Error('invalid_upload_location');
  }
  onInitiated();
  const result = await checked(await fetcher(location, { method: 'PUT',
    signal: AbortSignal.timeout(180000), headers: { 'Content-Type': 'video/mp4' }, body: video }), 'youtube_upload_uncertain');
  if (!/^[A-Za-z0-9_-]{11}$/.test(result.id ?? '')) throw new Error('youtube_upload_uncertain');
  return result.id;
}

export async function runWorker(env = process.env) {
  if (env.MARKETING_ENABLED !== 'true') {
    console.log('Marketing is disabled; no upload attempted.'); return;
  }
  const names = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'YOUTUBE_CLIENT_ID',
    'YOUTUBE_CLIENT_SECRET', 'YOUTUBE_REFRESH_TOKEN', 'YOUTUBE_CHANNEL_ID'];
  if (names.some(name => !env[name])) throw new Error('missing_marketing_configuration');
  const privacy = env.MARKETING_PRIVACY ?? 'private';
  if (!['private', 'public', 'unlisted'].includes(privacy)) throw new Error('invalid_privacy');
  const root = new URL(env.SUPABASE_URL);
  if (root.protocol !== 'https:') throw new Error('invalid_supabase_url');
  const dbHeaders = { apikey: env.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' };
  const db = async (path, method = 'GET', body) => {
    const response = await fetch(new URL(`/rest/v1/${path}`, root), { method,
      signal: AbortSignal.timeout(30000), headers: dbHeaders, body: body ? JSON.stringify(body) : undefined });
    if (!response.ok) throw new Error('database_request_failed');
    return response.status === 204 ? null : response.json();
  };
  const oauth = await checked(await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', signal: AbortSignal.timeout(30000), body: new URLSearchParams({
      client_id: env.YOUTUBE_CLIENT_ID, client_secret: env.YOUTUBE_CLIENT_SECRET,
      refresh_token: env.YOUTUBE_REFRESH_TOKEN, grant_type: 'refresh_token' }),
  }), 'youtube_auth_failed');
  if (!oauth.access_token) throw new Error('youtube_auth_failed');
  const yt = async path => checked(await fetch(`https://www.googleapis.com/youtube/v3/${path}`, {
    signal: AbortSignal.timeout(30000), headers: { Authorization: `Bearer ${oauth.access_token}` },
  }), 'youtube_read_failed');
  const channel = await yt('channels?part=id&mine=true');
  if (!channel.items?.some(item => item.id === env.YOUTUBE_CHANNEL_ID)) throw new Error('youtube_channel_mismatch');
  const campaigns = await db('rpc/claim_marketing_campaign', 'POST', {});
  const campaign = campaigns[0];
  if (campaign) {
    const directory = await mkdtemp(join(tmpdir(), 'recipe-marketing-'));
    let initiated = false;
    try {
      const input = join(directory, 'campaign.json');
      const output = join(directory, 'video.mp4');
      await writeFile(input, JSON.stringify(campaign));
      const render = spawnSync('python3', [fileURLToPath(new URL('./render.py', import.meta.url)), input, output],
        { encoding: 'utf8', timeout: 180000 });
      if (render.status !== 0) throw new Error('video_render_failed');
      const videoId = await uploadVideo({ campaign, video: await readFile(output), token: oauth.access_token,
        channelId: env.YOUTUBE_CHANNEL_ID, privacy, onInitiated: () => { initiated = true; } });
      await db(`marketing_campaigns?id=eq.${campaign.id}&status=eq.publishing`, 'PATCH', {
        status: 'published', youtube_video_id: videoId, error_code: null });
      console.log(`Uploaded campaign ${campaign.id}; requested visibility: ${privacy}.`);
    } catch (error) {
      await db(`marketing_campaigns?id=eq.${campaign.id}&status=eq.publishing`, 'PATCH', {
        status: initiated ? 'needs_review' : 'failed',
        error_code: initiated ? 'upload_result_needs_review' : 'publish_failed' });
      throw new Error('campaign_publish_failed');
    } finally { await rm(directory, { recursive: true, force: true }); }
  }
  // Aggregate video metrics only. No claim that views equal app clicks or installs.
  const published = await db('marketing_campaigns?status=eq.published&select=id,youtube_video_id&order=metrics_at.asc.nullsfirst&limit=50');
  if (published.length) {
    const metrics = await yt(`videos?part=statistics&id=${published.map(c => c.youtube_video_id).join(',')}`);
    for (const item of metrics.items ?? []) {
      const match = published.find(c => c.youtube_video_id === item.id);
      if (match) await db(`marketing_campaigns?id=eq.${match.id}`, 'PATCH', {
        views: Number(item.statistics.viewCount ?? 0), likes: Number(item.statistics.likeCount ?? 0),
        metrics_at: new Date().toISOString() });
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  runWorker().catch(() => { console.error('Marketing worker failed; check configuration and campaign status.'); process.exitCode = 1; });
}
