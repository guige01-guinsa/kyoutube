// Only reviewed, bundled UI captures. No user/model URL, path or network fetch.
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const root = new URL('../../assets/story_demos/', import.meta.url);
export async function demoAssets(snapshot) {
  const brief = snapshot.episode?.brief ?? '';
  if (!brief.includes('[APP_DEMO:')) return new Map();
  const manifest = JSON.parse(await readFile(new URL('bibimbap-v1.json', root), 'utf8'));
  const markers = brief.split(/\r?\n/).filter(line => line.includes('[APP_DEMO:'));
  if (markers.length !== 1 || markers[0] !== manifest.marker) throw new Error('invalid_demo_template');
  const assets = new Map();
  for (const panel of manifest.panels) {
    if (![2,3].includes(panel.index) || !/^bibimbap-(source|draft)\.jpg$/.test(panel.file)) throw new Error('invalid_demo_asset');
    const bytes = await readFile(new URL(panel.file, root));
    if (bytes.length > 1_000_000 || createHash('sha256').update(bytes).digest('hex') !== panel.sha256) throw new Error('demo_asset_changed');
    assets.set(panel.index, bytes);
  }
  if (assets.size !== 2) throw new Error('invalid_demo_asset');
  return assets;
}
