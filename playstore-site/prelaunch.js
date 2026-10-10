import { calculateCost, attribution, channelUrl, cleanShareUrl } from './prelaunch-domain.js';
const $ = (id) => document.getElementById(id);
const config = window.RECIPE_SCOUT_GROWTH || {};
const korean = Object.fromEntries([...document.querySelectorAll('[data-i18n]')].map((el) => [el.dataset.i18n, el.textContent]));
const english = {
  skip: 'Skip to content', brand: 'Recipe Scout', navWork: 'Your kitchen workflow', navDemo: 'Try menu costing', eyebrow: 'FOR CHEFS & RESTAURANT OWNERS',
  headline: 'Beyond recipes.\nA standard for your kitchen.', intro: 'Record your dishes. Understand the cost of each serving. Connect your recipes to the next service.',
  joinCta: 'Request launch & beta updates ↗', demoCta: 'Try the cost worksheet first ↓', availability: 'Android launch in preparation · Korean / English · No payment now',
  sample: 'Illustrative layout', dish: 'Mushroom cream risotto', dishSub: 'Lunch menu · Recipe version 03', servingFrom: 'Base: 4 servings', servingTo: 'Prep: 20 servings', rice: 'Rice', mushroom: 'Mushrooms', stock: 'Stock', boardTitle: 'A consistent standard for every service', boardNote: 'Record yield and prices, then prepare your purchase request',
  principle1: 'Your recipe standard', principle2: 'Servings · Yield · Cost', principle3: 'Suppliers · Requests', workflowTitle: 'Daily kitchen work,\none connected flow.', workflowIntro: 'From independent chefs to small restaurants.\nStart with one dish you make every day.',
  f1Title: 'Document your recipe', f1Body: 'Create an AI draft from a video and review it yourself. Refine the method and compare recipe versions.', f2Title: 'Scale and understand costs', f2Body: 'Bring together quantities, purchase prices, edible yield and additional costs to define your menu.', f3Title: 'Turn prep into a request', f3Body: 'Collect the ingredients you need and share a request with your supplier. You choose the recipient and send it in KakaoTalk.', featureNote: 'App features depend on your plan. Review AI drafts and conversions against your actual ingredients and cooking methods.',
  worksheetTitle: 'What does one\nserving really cost?', worksheetIntro: 'Try it without an email address. These values are calculated only in your browser and are never saved or sent.', formula: 'Ingredient cost ÷ yield + extra costs = total cost. The selling price adds your chosen markup to the cost per serving.', ingredientCost: 'Ingredient cost, before yield loss (KRW)', yield: 'Edible yield (%)', extraCost: 'Additional costs (KRW)', portions: 'Servings to prepare', markup: 'Markup on cost', unitCost: 'Cost per serving', sellingPrice: 'Calculated selling price', costNote: 'At 80% yield, divide ingredient cost by 0.8 to account for purchase loss. Actual profit depends on whether tax, labor, rent and other costs are included. This example does not save data in the app.',
  joinTitle: 'Tell us what matters\nin your kitchen.', joinIntro: 'We are collecting launch and beta requests with a focus on chefs and restaurant owners. Choose the feature you want to try first.', s1: 'Apply and confirm your email.', s2: 'Explore a real use case with the cost worksheet.', s3: 'Receive participation details when testing is ready.', joinNote: 'Applying does not guarantee app access, tester selection or free paid features. Dates and participation terms will be shared when confirmed.', youtube: 'Follow the preparation on YouTube ↗', kakao: 'Follow our Kakao Channel ↗',
  formTitle: 'Request launch & beta updates', notReady: 'Applications are not open yet. Try the cost worksheet and follow our YouTube channel in the meantime.', email: 'Email address', role: 'Your role', interest: 'The feature you want first', chef: 'Professional chef', owner: 'Restaurant owner', catering: 'Catering / food service', home: 'Home cook', costs: 'Menu costing', scaling: 'Serving and yield conversion', purchasing: 'Purchase requests', video: 'Video recipe drafts',
  privacyConsent: '[Required] I have read and agree to the prelaunch data collection notice below.', invitationConsent: '[Required] I agree to receive the launch and beta invitation emails I am requesting, including promotional information.', newsletter: '[Optional] I also want practical tips and promotional emails. You can apply without selecting this.', submit: 'Confirm my application by email ↗', privacyTitle: 'Prelaunch data collection notice',
  privacyBody: 'We collect your email, role, feature interest, language, acquisition channel/campaign, consent and application/confirmation timestamps. We use these to confirm your request, provide launch/beta invitations and measure recruitment. Unconfirmed requests are retained for 7 days and confirmed requests for up to 180 days. Withdrawal deletes your email; the remaining request, consent and processing records, including an anti-duplicate key, are kept for up to 30 days. Optional consent is used only for tips and promotions. You can withdraw through an email link without logging in. If you decline the required consents, you cannot request emails, but the worksheet and public channels remain available.',
  privacyProcessors: 'Before opening applications, we will finalize and publish details of Supabase storage and Resend email processing, including applicable overseas processing. Intake and delivery are currently disabled.', contact: 'Contact', sharePrompt: 'Share this cost worksheet with a colleague in your kitchen.', share: 'Copy page link ↗', privacyLink: 'App privacy policy', deleteLink: 'Delete app account',
};
const messages = {
  ko: { ready: '신청 후 확인 메일의 링크를 눌러 주세요. 선택한 동의 범위에 따라 안내합니다.', invalidCost: '재료비·추가 비용은 0~1억 원, 수율은 1~100%, 인분은 1~10,000의 정수로 입력해 주세요.', accepted: '신청 요청을 접수했습니다. 확인 메일이 도착하면 링크를 눌러 주세요. 이미 신청했다면 기존 메일과 스팸함을 확인해 주세요. 발송량에 따라 안내가 지연될 수 있습니다.', failure: '지금 요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.', captcha: '자동 입력 방지 확인을 완료해 주세요.', copied: '링크를 복사했습니다.', copyFailed: '복사하지 못했습니다. 브라우저 주소를 직접 복사해 주세요.', confirmTitle: '이메일 신청 확인', confirmBody: '버튼을 누르면 출시·베타 안내 신청이 확인됩니다.', confirmButton: '신청 확인하기', withdrawTitle: '신청 철회·이메일 수신 거부', withdrawBody: '버튼을 누르면 등록된 이메일을 삭제하고 대기 중인 안내를 취소합니다. 이미 발송 중인 이메일은 도착할 수 있습니다.', withdrawButton: '신청 철회하기', confirmed: '신청을 확인했습니다. 원가 계산 체험을 이용해 보세요.', withdrawn: '철회를 처리했습니다. 이메일은 삭제되고 이후 안내는 중단됩니다.', invalidLink: '링크가 만료되었거나 유효하지 않습니다. 원본 이메일을 확인하거나 문의해 주세요.', notConnected: '신청 기능이 아직 연결되지 않았습니다.' },
  en: { ready: 'After applying, use the link in your confirmation email. Updates follow the consent you select.', invalidCost: 'Use costs from 0 to 100 million KRW, yield from 1–100%, and whole servings from 1–10,000.', accepted: 'Your request has been received. Confirm using the email when it arrives. If you already applied, check your previous email and spam folder. Delivery can be delayed by sending limits.', failure: 'We could not process this request. Please try again later.', captcha: 'Please complete the anti-bot check.', copied: 'Link copied.', copyFailed: 'Copy failed. Please copy the page address in your browser.', confirmTitle: 'Confirm your email request', confirmBody: 'Use the button to confirm your launch and beta update request.', confirmButton: 'Confirm my request', withdrawTitle: 'Withdraw / unsubscribe', withdrawBody: 'This deletes the registered email and cancels queued updates. An email already being sent may still arrive.', withdrawButton: 'Withdraw my request', confirmed: 'Your request is confirmed. Try the menu-cost worksheet.', withdrawn: 'Your request has been withdrawn. Your email is deleted and future updates are stopped.', invalidLink: 'This link has expired or is invalid. Check the original email or contact us.', notConnected: 'Applications are not connected yet.' },
};
let language = new URLSearchParams(location.search).get('lang') === 'en' ? 'en' : 'ko';
let isReady = false, challengeToken = '', widgetId, submitting = false;
let tokenAction = null;
const m = (key) => messages[language][key];
function cost() {
  const result = calculateCost({ ingredients: $('ingredient-cost').valueAsNumber, yieldPercent: $('yield').valueAsNumber, extra: $('extra-cost').valueAsNumber, portions: $('portions').valueAsNumber, markup: $('markup').valueAsNumber });
  $('markup-value').textContent = $('markup').value + '%';
  $('calculator-error').textContent = result ? '' : m('invalidCost');
  const format = (value) => new Intl.NumberFormat(language === 'ko' ? 'ko-KR' : 'en-US', { style: 'currency', currency: 'KRW', maximumFractionDigits: 0 }).format(value);
  $('unit-cost').textContent = result ? format(result.unit) : '—';
  $('selling-price').textContent = result ? format(result.price) : '—';
}
function renderLanguage() {
  document.documentElement.lang = language;
  document.title = language === 'ko' ? '레시피 스카우트 — 전문 주방의 레시피와 원가' : 'Recipe Scout — Recipes and costs for professional kitchens';
  document.querySelectorAll('[data-i18n]').forEach((el) => { el.textContent = (language === 'en' ? english : korean)[el.dataset.i18n]; });
  $('language').textContent = language === 'ko' ? 'English' : '한국어';
  if (isReady) $('readiness').textContent = m('ready');
  if (tokenAction) renderToken();
  cost();
}
function endpoint() {
  try { const url = new URL(config.endpoint); return url.protocol === 'https:' && !url.username && !url.password && !url.search && !url.hash ? url.href : null; } catch { return null; }
}
async function api(body) {
  if (!endpoint()) throw new Error('not_connected');
  const response = await fetch(endpoint(), { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), credentials: 'omit', referrerPolicy: 'no-referrer', signal: AbortSignal.timeout(18000) });
  const result = await response.json();
  if (!response.ok) throw new Error(result.code || 'failure');
  return result;
}
function renderCaptcha() {
  if (!window.turnstile || !isReady) return;
  if (widgetId !== undefined) window.turnstile.remove(widgetId);
  challengeToken = '';
  widgetId = window.turnstile.render('#challenge', { sitekey: config.turnstileSiteKey, action: 'prelaunch', language, size: 'flexible',
    callback: (token) => { challengeToken = token; }, 'expired-callback': () => { challengeToken = ''; }, 'error-callback': () => { challengeToken = ''; $('form-result').textContent = m('captcha'); } });
}
async function connect() {
  if (config.enabled !== true || config.privacyReady !== true || !endpoint() || !config.turnstileSiteKey) return;
  try {
    const response = await fetch(endpoint(), { credentials: 'omit', signal: AbortSignal.timeout(10000) });
    if (!response.ok || (await response.json()).ready !== true) return;
    const script = document.createElement('script'); script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'; script.async = true;
    script.onload = () => { isReady = true; $('join-fields').disabled = false; $('readiness').textContent = m('ready'); renderCaptcha(); };
    script.onerror = () => { $('readiness').textContent = m('failure'); };
    document.head.append(script);
  } catch { $('readiness').textContent = m('failure'); }
}
function renderToken() {
  const confirm = tokenAction.action === 'confirm';
  $('token-panel').hidden = false;
  $('token-title').textContent = m(confirm ? 'confirmTitle' : 'withdrawTitle');
  $('token-description').textContent = m(confirm ? 'confirmBody' : 'withdrawBody');
  $('token-action').textContent = m(confirm ? 'confirmButton' : 'withdrawButton');
}
const fragment = new URLSearchParams(location.hash.slice(1));
for (const action of ['confirm', 'withdraw']) {
  if (fragment.has(action)) {
    tokenAction = { action, token: fragment.get(action) };
    history.replaceState(null, '', location.pathname + location.search); // Keep signed links out of sharing/history and third-party requests.
    break;
  }
}
$('language').addEventListener('click', () => { language = language === 'ko' ? 'en' : 'ko'; const u = new URL(location.href); u.searchParams.set('lang', language); history.replaceState(null, '', u); renderLanguage(); renderCaptcha(); });
['ingredient-cost', 'yield', 'extra-cost', 'portions', 'markup'].forEach((id) => $(id).addEventListener('input', cost));
$('join-form').addEventListener('submit', async (event) => {
  event.preventDefault(); if (!isReady || submitting) return;
  if (!challengeToken) { $('form-result').textContent = m('captcha'); return; }
  const form = new FormData(event.currentTarget);
  submitting = true; $('join-fields').disabled = true; $('form-result').textContent = '';
  let success = false;
  try {
    await api({ action: 'join', email: form.get('email'), role: form.get('role'), interest: form.get('interest'), locale: language, newsletter: form.has('newsletter'), privacyConsent: form.has('privacyConsent'), invitationConsent: form.has('invitationConsent'), consentVersion: 'pro-2026-09-v1', website: form.get('website'), challenge: challengeToken, ...attribution(location.search) });
    $('form-result').textContent = m('accepted'); success = true; event.target.reset();
  } catch { $('form-result').textContent = m('failure'); }
  finally { submitting = false; challengeToken = ''; $('join-fields').disabled = success; if (window.turnstile && widgetId !== undefined) window.turnstile.reset(widgetId); }
});
$('token-action').addEventListener('click', async () => {
  if (!tokenAction) return;
  if (!endpoint()) { $('token-result').textContent = m('notConnected'); return; }
  $('token-action').disabled = true;
  try { const result = await api(tokenAction); $('token-result').textContent = m(result.status); }
  catch (error) { $('token-result').textContent = m(error.message === 'invalid_link' ? 'invalidLink' : 'failure'); $('token-action').disabled = false; }
});
$('share').addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(cleanShareUrl(location.href, language)); $('share-status').textContent = m('copied'); }
  catch { $('share-status').textContent = m('copyFailed'); }
});
for (const kind of ['youtube', 'kakao']) { const url = channelUrl(config[kind + 'Url'], kind); $(kind + '-link').hidden = !url; if (url) $(kind + '-link').href = url; }
renderLanguage(); if (tokenAction) { renderToken(); $('token-panel').scrollIntoView(); } else { void connect(); }
