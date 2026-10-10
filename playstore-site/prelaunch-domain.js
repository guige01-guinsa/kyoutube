export function calculateCost({ ingredients, yieldPercent, extra, portions, markup }) {
  if (![ingredients, yieldPercent, extra, portions, markup].every(Number.isFinite) || ingredients < 0 || ingredients > 1e8 || extra < 0 || extra > 1e8 || yieldPercent < 1 || yieldPercent > 100 || !Number.isInteger(portions) || portions < 1 || portions > 10000 || markup < 0 || markup > 100) return null;
  const total = ingredients / (yieldPercent / 100) + extra;
  const unit = total / portions;
  return { total, unit, price: Math.ceil(unit * (1 + markup / 100)) };
}
export function attribution(search) {
  const p = new URLSearchParams(search);
  const source = (p.get('utm_source') || 'direct').toLowerCase();
  const campaign = p.get('utm_campaign') || '';
  return { source: ['direct', 'youtube', 'kakao', 'partner'].includes(source) ? source : 'other', campaign: /^[a-z0-9_-]{0,48}$/.test(campaign) ? campaign : '' };
}
export function channelUrl(value, kind) {
  try { const u = new URL(value); return u.protocol === 'https:' && !u.username && !u.password && (kind === 'youtube' ? ['youtube.com', 'www.youtube.com'].includes(u.hostname) : u.hostname === 'pf.kakao.com') ? u.href : null; }
  catch { return null; }
}
export function cleanShareUrl(value, language) {
  const u = new URL(value); u.search = ''; u.hash = '';
  u.searchParams.set('utm_source', 'partner'); u.searchParams.set('utm_campaign', 'chef-share'); u.searchParams.set('lang', language);
  return u.href;
}
