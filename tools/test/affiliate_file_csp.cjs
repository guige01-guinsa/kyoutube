// Exercise the same blob XHR as cross_file, under real and proposed CSP.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
(async () => {
  const origin = 'https://recipe-scout-workspace.web.app';
  const response = await fetch(origin);
  const live = response.headers.get('content-security-policy');
  assert.ok(live);
  const configured = JSON.parse(fs.readFileSync('firebase.web.json', 'utf8'))
    .hosting.headers[0].headers.find(h => h.key === 'Content-Security-Policy').value;
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    for (const [label, csp] of [['live', live], ['fixed', configured]]) {
      const page = await browser.newPage();
      // No app, account, remote mutation or credentials: a synthetic test page.
      await page.route(origin + '/import-csp-test', route => route.fulfill({
        status: 200, headers: { 'content-type': 'text/html', 'content-security-policy': csp }, body: '<!doctype html><title>Import CSP test</title>'
      }));
      await page.goto(origin + '/import-csp-test');
      const result = await page.evaluate(() => new Promise(resolve => {
        const url = URL.createObjectURL(new Blob(['상품명,제휴 링크'], {type: 'text/csv'}));
        const xhr = new XMLHttpRequest();
        xhr.open('GET', url); xhr.responseType = 'blob'; xhr.timeout = 5000;
        const done = ok => { URL.revokeObjectURL(url); resolve(ok); };
        xhr.onload = () => done(xhr.status === 200);
        xhr.onerror = xhr.ontimeout = () => done(false);
        xhr.send();
      }));
      console.log(label + ': local file bytes ' + (result ? 'readable' : 'BLOCKED'));
      if (label === 'fixed') assert.equal(result, true);
      await page.close();
    }
  } finally { await browser.close(); }
})().catch(e => { console.error(e.message); process.exitCode = 1; });
