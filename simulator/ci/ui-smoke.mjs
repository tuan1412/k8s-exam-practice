// Smoke test of the exam UI against a provisioned desktop (used by .github/workflows/simulator.yml).
// Usage: [PW_CHANNEL=chrome] node ui-smoke.mjs <login-url> <out-dir>
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
import { execSync } from 'node:child_process';

const [url, out = 'shots'] = process.argv.slice(2);
mkdirSync(out, { recursive: true });
// PW_CHANNEL=chrome: the Chrome already on the machine, nothing to download
const browser = await chromium.launch(process.env.PW_CHANNEL ? { channel: process.env.PW_CHANNEL } : {});
const page = await (await browser.newContext({ viewport: { width: 1600, height: 900 } })).newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
const shot = (name) => page.screenshot({ path: `${out}/${name}.png` });
const fail = async (msg) => { await shot('failure'); console.error(`FAIL: ${msg}`); process.exit(1); };

await page.goto(url);
await page.waitForSelector('#dlg-start[open]');

// exam picker: every question set is offered, switching loads its questions
const sets = await page.$$eval('#start-exams input[name=exam]', (els) => els.map((e) => e.value));
if (!sets.includes('cka/mock-01')) await fail(`exam list: ${sets}`);
await page.check('#start-exams input[value="cka/mock-01"]');
await page.waitForFunction(() => document.querySelector('#start-title').textContent === 'CKA Mock 1');
if ((await page.textContent('#qtotal')) !== '19') await fail('mock 1 should have 19 questions');
// exam hosts: destructive questions have hosts of their own, so "set up all" includes them
if (/skipped/.test(await page.textContent('#start-setup-text'))) await fail('no question should be skipped with exam hosts');
if (!/ssh cka\d{4}/.test(await page.textContent('#qhost'))) await fail(`no exam host above the task: ${await page.textContent('#qhost')}`);
await shot('0-exam-picker');
await page.uncheck('#start-setup');
await page.click('#start-go');
await page.waitForSelector('#desk-status', { state: 'hidden', timeout: 30000 }).catch(() => fail('desktop did not connect'));
await page.waitForTimeout(3000);
await shot('1-desktop');

// click a highlighted value (no "copied" pop-up) and paste it into the terminal over ssh
await page.click('#qbody code.copy >> nth=0');            // first highlighted value of Q1
if (await page.locator('#toast.show').count()) await fail('a copy pop-up was shown');
const canvas = await page.$('#screen canvas');
const box = await canvas.boundingBox();
await page.mouse.click(box.x + box.width * 0.5, box.y + box.height * 0.5);
const host = (await page.textContent('#qhost')).match(/ssh (cka\d+)/)?.[1] || await fail('no host for Q1');
await page.keyboard.type(`ssh ${host} kubectl get nodes -o wide; echo pasted: `, { delay: 20 });
await page.keyboard.press('Control+Shift+V');
await page.waitForTimeout(500);
await page.keyboard.press('Enter');
await page.waitForTimeout(6000);
await shot('2-terminal');

// grade one question through the UI (runs on its exam host over ssh)
await page.click('[data-lab="validate"]');
// the first lab action may wait for the exam's hosts to start
await page.waitForFunction(() => document.querySelector('#out-status').textContent !== 'running…', null, { timeout: 300000 });
const out1 = await page.textContent('#out-text');
await shot('3-check');
if (!/RESULT \d+\/\d+/.test(out1)) await fail(`Check did not run the grader:\n${out1}`);
await page.click('#out-close');

await page.click('#kbd-btn');
await shot('4-shortcuts');
await page.click('#kbd-close');

// doc links open in a new tab of the desktop's Firefox
const [opened] = await Promise.all([
  page.waitForResponse((r) => r.url().endsWith('/api/open-doc')),
  page.click('#qbody .docs a >> nth=0'),
]);
if (opened.status() !== 204) await fail(`open-doc: HTTP ${opened.status()}`);
let firefox = false;
for (let i = 0; i < 20 && !firefox; i++) {
  try { execSync('pgrep -f /usr/lib/firefox/firefox', { stdio: 'ignore' }); firefox = true; } catch { await page.waitForTimeout(1000); }
}
if (!firefox) await fail('Firefox did not start on the desktop');
await page.waitForTimeout(5000);
await shot('5-doc-in-firefox');

console.log('check output:\n' + out1);
console.log('page errors:', errors);
await browser.close();
if (errors.length) process.exit(1);
