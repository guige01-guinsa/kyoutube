import test from 'node:test';
import assert from 'node:assert/strict';
import { campaignLink, videoMetadata, uploadVideo, runWorker } from './worker.mjs';
import { parseContent, buildPrompt } from '../../supabase/functions/marketing_generate/content.ts';

const campaign = { id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', title: '재료 검색', description: '앱 기능 소개' };

test('Play referral preserves campaign without confusing Shorts links with clicks', () => {
  const url = new URL(campaignLink(campaign.id));
  assert.equal(url.searchParams.get('id'), 'com.kyoutube.app');
  const referral = new URLSearchParams(url.searchParams.get('referrer'));
  assert.equal(referral.get('utm_campaign'), campaign.id);
  assert.equal(referral.get('utm_source'), 'youtube');
  assert.throws(() => campaignLink('a&other=1'));
  assert.match(videoMetadata(campaign, 'channel', 'private').snippet.description, /채널 프로필/);
  assert.throws(() => videoMetadata(campaign, 'channel', 'invalid'));
});

test('upload uses resumable session and records one successful video ID', async () => {
  const calls = [];
  let initiated = false;
  const id = await uploadVideo({ campaign, video: Buffer.from('video'), token: 'test',
    channelId: 'channel', privacy: 'private', onInitiated: () => { initiated = true; },
    fetcher: async (url, options) => {
      calls.push({ url, options });
      return calls.length === 1
        ? new Response(null, { headers: { location: 'https://www.googleapis.com/upload/session' } })
        : Response.json({ id: 'abcdefghijk' });
    } });
  assert.equal(id, 'abcdefghijk');
  assert.equal(initiated, true);
  assert.equal(calls.length, 2);
  assert.equal(calls[1].options.method, 'PUT');
  assert.equal(JSON.parse(calls[0].options.body).status.privacyStatus, 'private');
});

test('rejects an untrusted upload host before sending bytes', async () => {
  let calls = 0;
  await assert.rejects(uploadVideo({ campaign, video: Buffer.from('video'), token: 'test',
    channelId: 'channel', privacy: 'private', fetcher: async () => {
      calls++;
      return new Response(null, { headers: { location: 'https://attacker.example/upload' } });
    } }), /invalid_upload_location/);
  assert.equal(calls, 1);
});

test('uncertain upload result is surfaced without retrying', async () => {
  let calls = 0;
  await assert.rejects(uploadVideo({ campaign, video: Buffer.from('video'), token: 'test',
    channelId: 'channel', privacy: 'private', fetcher: async () => {
      calls++;
      if (calls === 1) return new Response(null, { headers: { location: 'https://www.googleapis.com/upload/session' } });
      throw new Error('network_disconnected');
    } }), /network_disconnected/);
  assert.equal(calls, 2);
});

test('disabled worker runs without credentials or network', async () => {
  await runWorker({ MARKETING_ENABLED: 'false' });
});

test('content parser refuses missing scenes and overly long text', () => {
  assert.throws(() => parseContent({ title: 'a', description: 'b', scenes: [] }));
  assert.throws(() => parseContent({ title: 'a', description: 'b', scenes: ['a'.repeat(73), 'b', 'c'] }));
  assert.deepEqual(parseContent({ title: ' 제목 ', description: ' 설명 ', scenes: ['1', '2', '3'] }),
    { title: '제목', description: '설명', scenes: ['1', '2', '3'] });
  assert.match(buildPrompt('youtube'), /3분 이내/);
  assert.match(buildPrompt('shopping'), /외부 레시피/);
});
