// Exam simulator UI: task panel + noVNC desktop + timer + lab actions + shortcut drill.
import RFB from '/novnc/core/rfb.js';

const $ = (s) => document.querySelector(s);
const esc = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const stripAnsi = (s) => s.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '');

let exams = [], exam, rfb, connected = false, state;

// ---------- persisted state ----------
// examsim:<mock> = timer/flags of that exam · examsim:current = selected exam
// examsim:labs = exam whose labs are on the cluster (set up last)
const storeKey = () => `examsim:${exam.mock}`;
const getPref = (k) => { try { return localStorage.getItem(`examsim:${k}`); } catch { return null; } };
const setPref = (k, v) => { try { v == null ? localStorage.removeItem(`examsim:${k}`) : localStorage.setItem(`examsim:${k}`, v); } catch { /* private mode */ } };
const titleOf = (mock) => exams.find((e) => e.mock === mock)?.title || mock;
function load() {
  try { state = JSON.parse(localStorage.getItem(storeKey())) || {}; } catch { state = {}; }
  state.flags ||= {};
  state.cur ||= exam.questions[0].n;
}
function save() { try { localStorage.setItem(storeKey(), JSON.stringify(state)); } catch { /* private mode */ } }
const running = () => state.startedAt && !state.endedAt;

// ---------- toast / dialogs ----------
let toastTimer;
function toast(msg) {
  const t = $('#toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('show'), 2200);
}
function confirmBox(title, text, okLabel = 'OK') {
  return new Promise((resolve) => {
    const d = $('#dlg-confirm');
    $('#cf-title').textContent = title; $('#cf-text').textContent = text; $('#cf-yes').textContent = okLabel;
    const done = (v) => { d.close(); resolve(v); };
    $('#cf-yes').onclick = () => done(true); $('#cf-no').onclick = () => done(false);
    d.oncancel = () => resolve(false);
    d.showModal();
  });
}

// ---------- markdown-ish rendering of the task text ----------
function inline(s) {
  return esc(s)
    .replace(/`([^`]+)`/g, (_, c) => `<code class="copy" title="Click to copy">${c}</code>`)
    // doc links open in a new tab (of the desktop's Firefox when available), like in the exam
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, (_, t, u) => `<a href="${u}" target="_blank" rel="noopener noreferrer">${t}</a>`)
    .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
    .replace(/(^|[\s(])\*([^*]+)\*/g, '$1<i>$2</i>');
}
function render(md) {
  const out = []; let list = null, para = [], fence = null;
  const flushPara = () => { if (para.length) { out.push(`<p>${inline(para.join(' '))}</p>`); para = []; } };
  const flushList = () => { if (list) { out.push(`<ul>${list.map((l) => `<li>${inline(l)}</li>`).join('')}</ul>`); list = null; } };
  for (const line of md.split('\n')) {
    if (fence !== null) {
      if (line.trim().startsWith('```')) { out.push(`<pre class="copy" title="Click to copy">${esc(fence.join('\n'))}</pre>`); fence = null; }
      else fence.push(line);
      continue;
    }
    if (line.trim().startsWith('```')) { flushPara(); flushList(); fence = []; continue; }
    if (/^\s*- /.test(line)) { flushPara(); (list ||= []).push(line.replace(/^\s*- /, '')); continue; }
    if (!line.trim()) { flushPara(); flushList(); continue; }
    flushList();
    if (line.startsWith('ℹ️')) { flushPara(); out.push(`<p class="info">${inline(line)}</p>`); continue; }
    if (/^\*Suggested docs:/.test(line)) { flushPara(); out.push(`<p class="docs">${inline(line)}</p>`); continue; }
    para.push(line);
  }
  if (fence) out.push(`<pre class="copy" title="Click to copy">${esc(fence.join('\n'))}</pre>`);
  flushPara(); flushList();
  return out.join('');
}

// ---------- question panel ----------
const qByN = (n) => exam.questions.find((q) => q.n === n);
const qIndex = () => exam.questions.findIndex((q) => q.n === state.cur);

function show(n) {
  const q = qByN(n); if (!q) return;
  state.cur = n; save();
  $('#qnum').textContent = n;
  $('#qtitle').textContent = `Question ${n} · ${q.title}`;
  $('#qmeta').textContent = [q.weight ? `Weight ${q.weight}%` : '', q.domain].filter(Boolean).join(' · ');
  // like the exam: each task names the host to solve it on
  $('#qhost').hidden = !q.host;
  $('#qhost').innerHTML = q.host ? `Solve this question on: <code class="copy" title="Click to copy">ssh ${esc(q.host)}</code>` : '';
  useHost(q);
  // lab notes right under the task text (they change how to solve it), not at the pane's bottom
  const notes = (q.labNotes || []).map((l) => `<div><b>Lab note:</b> ${inline(l)}</div>`).join('');
  $('#qbody').innerHTML = render(q.body) + (notes ? `<div class="labnotes">${notes}</div>` : '');
  $('#qbody').scrollTop = 0;
  const w = $('#qwarn'); w.hidden = !q.warning; w.textContent = q.warning ? `⚠ ${q.warning}` : '';
  $('#flag-btn').classList.toggle('on', !!state.flags[n]);
  $('#flag-btn').textContent = state.flags[n] ? '⚑ Flagged' : '⚑ Flag';
  $('#prev').disabled = qIndex() === 0;
  $('#next').disabled = qIndex() === exam.questions.length - 1;
  renderPicker();
}
// Only some exam hosts run at a time (memory): start this question's host now, so that
// "ssh <host>" works from the terminal.
// Not while the start dialog is open (browsing exams would start and stop hosts), and
// only for a question you stay on for a moment.
let usedHost = null, useTimer = null;
function useHost(q) {
  clearTimeout(useTimer);
  if (!q?.host || q.host === usedHost || $('#dlg-start').open) return;
  useTimer = setTimeout(() => {
    usedHost = q.host;
    // next to "ssh <host>": an ssh before the host is up fails with "No route to host"
    const st = (cls, text) => {
      if (state.cur !== q.n) return;
      let el = $('#hoststat');
      if (!el) { el = document.createElement('span'); el.id = 'hoststat'; $('#qhost').append(' ', el); }
      el.className = cls; el.textContent = text;
    };
    st('busy', 'preparing the host…');
    fetch('/api/lab', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'use', q: q.n, mock: exam.mock }),
    }).then((r) => (r.ok ? r.text() : Promise.reject(new Error(r.status))))
      .then((t) => {
        st('ok', '✓ ready');
        if (/Started host/.test(t)) toast(`Host ${q.host} is up`);
      })
      .catch(() => { st('err', 'could not start the host'); if (usedHost === q.host) usedHost = null; });   // retry on the next visit
  }, 800);   // not for every question you only click through
}
function renderPicker() {
  const p = $('#qpicker');
  p.innerHTML = exam.questions.map((q) =>
    `<button data-q="${q.n}" class="${q.n === state.cur ? 'cur' : ''} ${state.flags[q.n] ? 'flagged' : ''}" title="${esc(q.title)} (${q.weight}%)">${q.n}</button>`).join('')
    + `<div class="legend">⚑ = flagged · ${Object.values(state.flags).filter(Boolean).length} flagged</div>`;
}

// ---------- clipboard ----------
function copyLocal(text) {
  if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text).catch(() => {});
  const ta = document.createElement('textarea');
  ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
  document.body.appendChild(ta); ta.select();
  try { document.execCommand('copy'); } catch { /* ignore */ }
  ta.remove();
}
function sendClip(text) {
  if (rfb && connected) rfb.clipboardPasteFrom(text);
  copyLocal(text);
}
// Text of the selection that lies inside highlighted (.copy) elements of the task pane.
// Like the exam, only those parts can be copied; the rest of the task text cannot.
function copyableSelection(range) {
  const parts = [];
  for (const el of $('#qpane').querySelectorAll('.copy')) {
    if (!range.intersectsNode(el)) continue;
    const r = document.createRange(); r.selectNodeContents(el);
    if (range.compareBoundaryPoints(Range.START_TO_START, r) > 0) r.setStart(range.startContainer, range.startOffset);
    if (range.compareBoundaryPoints(Range.END_TO_END, r) < 0) r.setEnd(range.endContainer, range.endOffset);
    const t = r.toString(); if (t) parts.push(t);
  }
  return parts.join('\n');
}

// ---------- noVNC ----------
function connect() {
  const url = `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/websockify`;
  const status = $('#desk-status');
  status.hidden = false; status.textContent = 'Connecting to the desktop…';
  rfb = new RFB($('#screen'), url, { wsProtocols: ['binary'] });
  rfb.resizeSession = true;   // Xvnc follows the browser size
  rfb.scaleViewport = true;   // fallback if the server can't resize
  rfb.focusOnClick = true;
  rfb.qualityLevel = 6;
  rfb.compressionLevel = 2;
  rfb.addEventListener('connect', () => { connected = true; status.hidden = true; rfb.focus(); });
  rfb.addEventListener('disconnect', () => {
    connected = false; status.hidden = false;
    status.textContent = 'Desktop disconnected — reconnecting…';
    setTimeout(connect, 2000);
  });
  rfb.addEventListener('clipboard', (e) => copyLocal(e.detail.text));
}

// noVNC only resizes the remote session (and rescales) on a window 'resize' event. The
// desktop pane also changes size without one (saved splitter width applied, question
// pane reflow, font A+/A-), which left the desktop larger than the pane and cut off.
// Forward every size change of the pane, debounced so a drag doesn't flood Xvnc.
let deskResizeTimer;
new ResizeObserver(() => {
  clearTimeout(deskResizeTimer);
  deskResizeTimer = setTimeout(() => window.dispatchEvent(new Event('resize')), 150);
}).observe(document.getElementById('desk'));

// When focus leaves the desktop mid-shortcut (right-click menu, Alt+Tab, clicking the task
// pane) the key-up never reaches the VM, so Ctrl/Shift/Alt stay "held" there and keys like
// Backspace stop working. Release them every time focus leaves the desktop.
const MODIFIERS = [[0xffe3, 'ControlLeft'], [0xffe4, 'ControlRight'], [0xffe1, 'ShiftLeft'],
  [0xffe2, 'ShiftRight'], [0xffe9, 'AltLeft'], [0xffea, 'AltRight'], [0xffeb, 'MetaLeft']];
function releaseModifiers() {
  if (!rfb || !connected) return;
  for (const [sym, code] of MODIFIERS) rfb.sendKey(sym, code, false);
}

// Doc links open in a new tab of the desktop's Firefox, like the exam's task panel.
// Without a desktop (local UI development) they open in a new tab of this browser.
function openDoc(e, url) {
  if (!exam.docsInDesktop) return;               // default: <a target="_blank">
  e.preventDefault();
  fetch('/api/open-doc', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url }) })
    .then((r) => { if (!r.ok) throw new Error(); })
    .catch(() => window.open(url, '_blank', 'noopener'));
}

// ---------- timer ----------
function fmt(ms) {
  const neg = ms < 0; ms = Math.abs(ms);
  const s = Math.floor(ms / 1000), h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60;
  return `${neg ? '-' : ''}${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}
let timeUpShown = false;
function tick() {
  const t = $('#timer');
  if (!state.startedAt) { t.textContent = fmt(exam.durationMin * 60000); return; }
  const end = state.endedAt || Date.now();
  const left = exam.durationMin * 60000 - (end - state.startedAt);
  t.textContent = state.endedAt ? `ended ${fmt(end - state.startedAt)}` : fmt(left);
  t.classList.toggle('low', left < 15 * 60000 && left >= 0);
  t.classList.toggle('over', left < 0 && !state.endedAt);
  if (left < 0 && running() && !timeUpShown) {
    timeUpShown = true;
    confirmBox('Time is up', 'The 120 minutes are over. Grade the exam now? (You can keep working; the timer shows the overtime.)', 'Grade now')
      .then((ok) => ok && endExam(true));
  }
}

// ---------- lab actions ----------
let abortCtl = null;
// stream runs lab actions one after the other ([{action, q, mock}]) and shows their output.
async function stream(title, steps, onDone) {
  const d = $('#dlg-out'), pre = $('#out-text'), st = $('#out-status');
  $('#out-title').textContent = title; pre.textContent = ''; st.textContent = 'running…'; st.className = '';
  $('#out-stop').hidden = false;
  if (!d.open) d.showModal();
  abortCtl = new AbortController();
  let text = '', ok = true;
  try {
    for (const { action, q = 0, mock = exam.mock } of steps) {
      const res = await fetch('/api/lab', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action, q, mock }), signal: abortCtl.signal,
      });
      if (!res.ok) throw new Error(await res.text());
      const reader = res.body.getReader(), dec = new TextDecoder();
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        text += stripAnsi(dec.decode(value, { stream: true }));
        const atBottom = pre.scrollHeight - pre.scrollTop - pre.clientHeight < 40;
        pre.textContent = text;
        if (atBottom) pre.scrollTop = pre.scrollHeight;
      }
      text += '\n';
    }
    st.textContent = 'done';
  } catch (e) {
    ok = false;
    st.textContent = e.name === 'AbortError' ? 'stopped' : `error: ${e.message}`;
    st.className = 'fail';
  }
  $('#out-stop').hidden = true; abortCtl = null;
  onDone?.(text, ok);
}
function showScore(text) {
  const total = text.match(/TOTAL\s+([\d.]+)\/(\d+)/);
  const st = $('#out-status');
  if (!total) return;
  const pass = /PASS/.test(text.split('TOTAL').pop());
  st.textContent = `Score ${total[1]} / ${total[2]} — ${pass ? 'PASS' : 'FAIL'} (pass mark ${exam.passMark})`;
  st.className = pass ? 'pass' : 'fail';
}
async function labAction(action) {
  const q = qByN(state.cur);
  if (action === 'setup' && q.warning && !(await confirmBox(`Set up Q${q.n}?`, q.warning, 'Run setup'))) return;
  const label = { setup: 'Set up', validate: 'Check', cleanup: 'Reset' }[action];
  if (action === 'setup') setPref('labs', exam.mock);
  stream(`${label} · Question ${q.n}`, [{ action, q: q.n }]);
}
async function showSolution() {
  const q = qByN(state.cur);
  if (running() && !(await confirmBox('Show the solution?', 'The exam is still running. Looking at the solution now spoils this question.', 'Show'))) return;
  const res = await fetch(`/api/solution?mock=${encodeURIComponent(exam.mock)}&q=${q.n}`);
  $('#out-title').textContent = `Solution · Question ${q.n}`;
  $('#out-text').textContent = await res.text();
  $('#out-status').textContent = ''; $('#out-stop').hidden = true;
  $('#dlg-out').showModal();
}
async function endExam(skipConfirm) {
  if (!skipConfirm && running()
    && !(await confirmBox('End the exam?', 'The timer stops and all questions are graded.', 'End & grade'))) return;
  if (running()) { state.endedAt = Date.now(); save(); }
  stream(`Final score · ${exam.title}`, [{ action: 'score' }], showScore);
}

// ---------- start dialog ----------
function examStatus(mock) {
  let st = {};
  try { st = JSON.parse(localStorage.getItem(`examsim:${mock}`)) || {}; } catch { /* ignore */ }
  return st.endedAt ? 'ended' : st.startedAt ? 'in progress' : 'not started';
}
function renderStart() {
  const flagged = Object.values(state.flags).filter(Boolean).length;
  $('#start-exams').innerHTML = exams.map((e) => `<label class="exam-card ${e.mock === exam.mock ? 'on' : ''}">
    <input type="radio" name="exam" value="${esc(e.mock)}" ${e.mock === exam.mock ? 'checked' : ''}>
    <span><b>${esc(e.title)}</b><small>${e.questions} questions · ${examStatus(e.mock)}</small></span></label>`).join('');
  $('#start-title').textContent = exam.title;
  $('#start-info').textContent = `${exam.questions.length} questions · ${exam.durationMin} minutes · pass mark ${exam.passMark}%`
    + (state.endedAt ? ' · ended' : state.startedAt ? ` · in progress (${flagged} flagged)` : '');
  $('#start-go').textContent = state.endedAt ? 'Review answers' : state.startedAt ? 'Continue' : 'Start exam';
  $('#start-restart').hidden = !state.startedAt;
  const skipped = exam.questions.filter((q) => q.warning).map((q) => `Q${q.n}`);
  $('#start-setup-text').textContent = 'Set up all labs first (several minutes, needs internet'
    + (skipped.length ? `; ${skipped.join(', ')} ${skipped.length > 1 ? 'are' : 'is'} skipped — set ${skipped.length > 1 ? 'each' : 'it'} up on its own` : '') + ')';
  $('#start-setup').checked = !state.startedAt;
  $('#start-setup').closest('label').hidden = !!state.startedAt;
  // labs of another exam on the cluster clash with this one (names, NodePorts, default StorageClass...)
  const other = getPref('labs');
  // (with exam hosts every exam has hosts of its own: no clash)
  const clash = !exam.hosts?.length && other && other !== exam.mock && exams.some((e) => e.mock === other);
  $('#start-clean-text').textContent = clash ? `Remove the labs of ${titleOf(other)} from the cluster first (Reset all)` : '';
  $('#start-clean').checked = !!clash;
  $('#start-clean').closest('label').hidden = !clash;
}
function startDialog() {
  renderStart();
  if (!$('#dlg-start').open) $('#dlg-start').showModal();
}
async function selectExam(mock) {
  const res = await fetch(`/api/exam?mock=${encodeURIComponent(mock)}`);
  if (!res.ok) throw new Error(await res.text());
  exam = await res.json();
  setPref('current', exam.mock);
  document.title = `${exam.title} · Exam Simulator`;
  $('#exam-title').textContent = `${exam.title} ▾`;
  $('#qtotal').textContent = exam.questions.length;
  load(); timeUpShown = false;
  show(qByN(state.cur) ? state.cur : exam.questions[0].n);
  tick();
}
function beginTimer() {
  if (!state.startedAt) { state.startedAt = Date.now(); save(); }
  tick();
}

// ---------- splitter / font ----------
function initLayout() {
  const root = document.documentElement.style;
  if (state.qwidth) root.setProperty('--qwidth', state.qwidth);
  if (state.qfont) root.setProperty('--qfont', `${state.qfont}px`);
  const sp = $('#splitter');
  sp.addEventListener('pointerdown', (e) => {
    sp.setPointerCapture(e.pointerId); sp.classList.add('drag');
    const move = (ev) => {
      const pct = Math.min(70, Math.max(18, (ev.clientX / window.innerWidth) * 100));
      state.qwidth = `${pct.toFixed(1)}%`; root.setProperty('--qwidth', state.qwidth);
    };
    const up = () => {
      sp.classList.remove('drag'); sp.removeEventListener('pointermove', move); save();
      window.dispatchEvent(new Event('resize')); // let noVNC resize the remote session
    };
    sp.addEventListener('pointermove', move);
    sp.addEventListener('pointerup', up, { once: true });
  });
  const font = (d) => {
    state.qfont = Math.min(22, Math.max(12, (state.qfont || 15) + d)); save();
    root.setProperty('--qfont', `${state.qfont}px`);
  };
  $('#font-dec').onclick = () => font(-1);
  $('#font-inc').onclick = () => font(1);
}

// ---------- shortcuts: cheat sheet + drill ----------
const SHEET = [
  ['Terminal (xfce4-terminal)', [
    ['Ctrl+Shift+C', 'copy selection'], ['Ctrl+Shift+V', 'paste'], ['Shift+Insert', 'paste (alternative)'],
    ['Ctrl+Shift+T', 'new tab'], ['Ctrl+Shift+W', 'close tab'], ['Ctrl+Shift+N', 'new window'],
    ['Ctrl+PageDown / PageUp', 'next / previous tab'], ['Alt+1 … Alt+9', 'go to tab N'],
    ['Ctrl++ / Ctrl+- / Ctrl+0', 'zoom in / out / reset'], ['F11', 'fullscreen terminal'],
  ]],
  ['Shell (bash readline)', [
    ['Ctrl+C', 'interrupt — NOT copy'], ['Ctrl+D', 'EOF / leave ssh'], ['Ctrl+L', 'clear screen'],
    ['Ctrl+R', 'search history'], ['Ctrl+A / Ctrl+E', 'start / end of line'], ['Ctrl+U', 'delete to line start'],
    ['Ctrl+W', 'delete previous word (closes a browser tab outside fullscreen!)'], ['Alt+B / Alt+F', 'word back / forward'],
    ['Tab Tab', 'completion (kubectl/k completion is set up)'],
  ]],
  ['vim', [
    ['i / Esc', 'insert / normal mode'], [':wq  :q!', 'save+quit / quit'], ['dd  yy  p', 'cut / copy / paste line'],
    ['u  Ctrl+R', 'undo / redo'], ['V then > or <', 'indent selected lines'], ['/text  n', 'search, next match'],
    [':set paste', 'before pasting YAML (keeps indent)'], ['gg  G', 'top / bottom'],
  ]],
  ['Firefox (docs)', [
    ['Ctrl+L', 'address bar'], ['Ctrl+F', 'find on page'], ['Ctrl+T / Ctrl+W', 'new / close tab'],
    ['Ctrl+Tab', 'next tab'], ['Alt+← / Alt+→', 'back / forward'],
  ]],
  ['Desktop & simulator', [
    ['Alt+Tab', 'switch window'], ['click highlighted text', 'copies it into the desktop clipboard'], ['doc links', 'open in a new Firefox tab on the desktop'],
    ['⛶ Fullscreen', 'lets Ctrl+W/T/N reach the desktop (Chrome/Edge keyboard lock)'],
  ]],
  ['First minute in the terminal', [
    ['ssh <host>', 'the host named above the task; work there as root, exit before the next task'], ['alias k=kubectl', 'already set'],
    ['export do="--dry-run=client -o yaml"', 'k run x --image=nginx $do > x.yaml'],
    ['export now="--force --grace-period 0"', 'k delete pod x $now'],
  ]],
];
const DRILL = [
  ['Copy the selected text in the terminal', ['Ctrl+Shift+C']],
  ['Paste into the terminal', ['Ctrl+Shift+V', 'Shift+Insert']],
  ['Open a new terminal tab', ['Ctrl+Shift+T']],
  ['Close the current terminal tab', ['Ctrl+Shift+W']],
  ['Open a new terminal window', ['Ctrl+Shift+N']],
  ['Go to the next terminal tab', ['Ctrl+PageDown']],
  ['Go to the previous terminal tab', ['Ctrl+PageUp']],
  ['Jump to terminal tab 2', ['Alt+2']],
  ['Terminal: make the font bigger', ['Ctrl++', 'Ctrl+Shift++']],
  ['Terminal: make the font smaller', ['Ctrl+-']],
  ['Terminal: reset the font size', ['Ctrl+0']],
  ['Stop the running command', ['Ctrl+C']],
  ['Leave the ssh session (EOF)', ['Ctrl+D']],
  ['Clear the terminal screen', ['Ctrl+L']],
  ['Search the shell history', ['Ctrl+R']],
  ['Move the cursor to the start of the line', ['Ctrl+A', 'Home']],
  ['Move the cursor to the end of the line', ['Ctrl+E', 'End']],
  ['Delete everything before the cursor', ['Ctrl+U']],
  ['Delete the previous word in the shell', ['Ctrl+W'], true],
  ['Move back one word in the shell', ['Alt+B']],
  ['Move forward one word in the shell', ['Alt+F']],
  ['Firefox: find text on the page', ['Ctrl+F']],
  ['Firefox: jump to the address bar', ['Ctrl+L']],
  ['Firefox: open a new tab', ['Ctrl+T'], true],
  ['Firefox: close the current tab', ['Ctrl+W'], true],
  ['Firefox: go to the next tab', ['Ctrl+Tab', 'Ctrl+PageDown'], true],
  ['Switch to another window', ['Alt+Tab'], true],
];
function renderSheet() {
  $('#tab-sheet').innerHTML = `<div class="sheet">${SHEET.map(([h, rows]) => `<div><h4>${esc(h)}</h4><table>${
    rows.map(([k, v]) => `<tr><td>${keys(k)}</td><td class="${v.includes('!') ? 'warn' : ''}">${esc(v)}</td></tr>`).join('')
  }</table></div>`).join('')}</div>`;
}
function keys(k) {
  if (!/^(Ctrl|Alt|Shift|F\d|Tab|Esc)/.test(k)) return `<code>${esc(k)}</code>`;
  const combo = (w) => w.replace(/\+\+/g, '+PLUS').split('+')
    .map((x) => `<kbd>${esc(x === 'PLUS' ? '+' : x)}</kbd>`).join('+');
  return k.split(' / ').map((part) => part.split(' ').map((w) => (w === '…' ? w : combo(w))).join(' ')).join(' / ');
}
function comboOf(e) {
  if (['Control', 'Shift', 'Alt', 'Meta', 'AltGraph'].includes(e.key)) return null;
  const c = e.code; let k;
  if (/^Key[A-Z]$/.test(c)) k = c.slice(3);
  else if (/^Digit\d$/.test(c)) k = c.slice(5);
  else if (c === 'Equal' || c === 'NumpadAdd') k = '+';
  else if (c === 'Minus' || c === 'NumpadSubtract') k = '-';
  else if (c === 'Numpad0') k = '0';
  else k = e.key.length === 1 ? e.key.toUpperCase() : e.key;
  return [e.ctrlKey && 'Ctrl', e.altKey && 'Alt', e.shiftKey && 'Shift', k].filter(Boolean).join('+');
}
const fmtKeys = (list) => list.map((k) => keys(k)).join(' or ');
const drill = { items: [], i: 0, t0: 0, results: [], tries: 0, locked: false };
function drillStart() {
  drill.items = [...DRILL].sort(() => Math.random() - 0.5).slice(0, 15);
  drill.i = 0; drill.results = [];
  $('#drill-intro').hidden = true; $('#drill-done').hidden = true; $('#drill-run').hidden = false;
  drillNext();
}
function drillNext() {
  if (drill.i >= drill.items.length) return drillDone();
  const [action, , reserved] = drill.items[drill.i];
  drill.t0 = performance.now(); drill.tries = 0; drill.locked = false;
  $('#drill-progress').textContent = `${drill.i + 1} / ${drill.items.length}`;
  $('#drill-action').textContent = action;
  const fb = $('#drill-feedback'); fb.className = 'drill-feedback';
  fb.innerHTML = reserved && !document.fullscreenElement
    ? 'Press the shortcut… <span class="muted">(the browser may swallow this one outside ⛶ Fullscreen — Skip if so)</span>'
    : 'Press the shortcut…';
}
function drillRecord(ok, how) {
  const [action, accepted] = drill.items[drill.i];
  drill.results.push({ action, accepted, ok, how, ms: performance.now() - drill.t0, tries: drill.tries });
  drill.i++; drill.locked = true;
  setTimeout(drillNext, ok ? 450 : 1400);
}
function drillKey(e) {
  if ($('#tab-drill').hidden || $('#drill-run').hidden || drill.locked) return;
  const combo = comboOf(e); if (!combo) return;
  e.preventDefault(); e.stopPropagation();
  const accepted = drill.items[drill.i][1];
  const fb = $('#drill-feedback');
  if (accepted.includes(combo)) {
    fb.className = 'drill-feedback ok'; fb.innerHTML = `✓ ${keys(combo)}`;
    drillRecord(drill.tries === 0, combo);
  } else {
    drill.tries++;
    fb.className = 'drill-feedback bad'; fb.innerHTML = `✗ ${keys(combo)} — try again`;
  }
}
function drillReveal(skip) {
  if (drill.locked) return;
  const accepted = drill.items[drill.i][1];
  const fb = $('#drill-feedback'); fb.className = 'drill-feedback bad';
  fb.innerHTML = `${skip ? 'Skipped' : 'Answer'}: ${fmtKeys(accepted)}`;
  drillRecord(false, skip ? 'skipped' : 'shown');
}
function drillDone() {
  $('#drill-run').hidden = true;
  const ok = drill.results.filter((r) => r.ok);
  const avg = ok.length ? (ok.reduce((a, r) => a + r.ms, 0) / ok.length / 1000).toFixed(1) : '–';
  const missed = drill.results.filter((r) => !r.ok);
  const d = $('#drill-done'); d.hidden = false;
  d.innerHTML = `<h3>${ok.length} / ${drill.results.length} right on the first try · avg ${avg}s</h3>`
    + (missed.length ? `<p>Practise these:</p><table>${missed.map((r) =>
      `<tr><td>${esc(r.action)}</td><td>${fmtKeys(r.accepted)}</td></tr>`).join('')}</table>` : '<p>Perfect run.</p>')
    + '<div class="row"><button id="drill-again" class="primary">Again</button></div>';
  $('#drill-again').onclick = drillStart;
}
function openKbd(tab = 'sheet') {
  rfb?.blur();
  for (const b of document.querySelectorAll('.tabs [data-tab]')) b.classList.toggle('on', b.dataset.tab === tab);
  $('#tab-sheet').hidden = tab !== 'sheet'; $('#tab-drill').hidden = tab !== 'drill';
  if (tab === 'drill') { $('#drill-intro').hidden = false; $('#drill-run').hidden = true; $('#drill-done').hidden = true; }
  if (!$('#dlg-kbd').open) $('#dlg-kbd').showModal();
}

// ---------- fullscreen + keyboard lock ----------
async function toggleFullscreen() {
  if (document.fullscreenElement) { await document.exitFullscreen(); return; }
  await document.documentElement.requestFullscreen();
  if (navigator.keyboard?.lock) {
    try { await navigator.keyboard.lock(); toast('Keyboard locked: Ctrl+W/T/N go to the desktop. Hold Esc to leave fullscreen.'); }
    catch { toast('Fullscreen on (keyboard lock not available in this browser)'); }
  } else toast('Fullscreen on (keyboard lock needs Chrome or Edge)');
}

// ---------- wiring ----------
function wire() {
  $('#prev').onclick = () => { const i = qIndex(); if (i > 0) show(exam.questions[i - 1].n); };
  $('#next').onclick = () => { const i = qIndex(); if (i < exam.questions.length - 1) show(exam.questions[i + 1].n); };
  $('#flag-btn').onclick = () => { state.flags[state.cur] = !state.flags[state.cur]; save(); show(state.cur); };
  $('#qpicker-btn').onclick = (e) => { e.stopPropagation(); $('#qpicker').hidden = !$('#qpicker').hidden; };
  $('#qpicker').onclick = (e) => { const b = e.target.closest('[data-q]'); if (b) { show(+b.dataset.q); $('#qpicker').hidden = true; } };
  document.addEventListener('click', (e) => { if (!e.target.closest('#qpicker')) $('#qpicker').hidden = true; });

  // Like the exam: a click on a highlighted value copies it (no "copied" pop-up), into the
  // desktop clipboard too, so Ctrl+Shift+V pastes it in the terminal. Also the "ssh <host>" line.
  $('#qpane').addEventListener('click', (e) => {
    const a = e.target.closest('a[href]');
    if (a) { openDoc(e, a.href); return; }
    const el = e.target.closest('.copy'); if (!el) return;
    if (String(window.getSelection())) return;      // the user is selecting part of it: Ctrl+C
    // code blocks: copy the commands without trailing "  # should fail" style notes
    const text = el.tagName === 'PRE'
      ? el.textContent.split('\n').map((l) => l.replace(/\s+#\s.*$/, '')).join('\n')
      : el.textContent;
    sendClip(text);
    el.classList.add('flash'); setTimeout(() => el.classList.remove('flash'), 300);
  });
  // Ctrl+C / right-click > Copy: only the highlighted parts of the task pane are copied
  document.addEventListener('copy', (e) => {
    if (document.activeElement?.closest?.('#screen')) return;   // copy inside the desktop
    const sel = window.getSelection();
    if (!sel || !sel.rangeCount || sel.isCollapsed) return;
    const range = sel.getRangeAt(0);
    let text = String(sel);
    if ($('#qpane').contains(range.commonAncestorContainer) || range.intersectsNode($('#qpane'))) {
      text = copyableSelection(range);
      e.preventDefault();                       // only the highlighted parts reach the clipboard
      if (text) e.clipboardData.setData('text/plain', text);
    }
    if (text && rfb && connected) rfb.clipboardPasteFrom(text);
  });
  window.addEventListener('blur', releaseModifiers);
  $('#screen').addEventListener('focusout', releaseModifiers);
  for (const b of document.querySelectorAll('[data-lab]')) b.onclick = () => labAction(b.dataset.lab);
  $('#sol-btn').onclick = showSolution;
  $('#end-btn').onclick = () => endExam(false);
  $('#out-stop').onclick = () => abortCtl?.abort();
  $('#out-close').onclick = () => { abortCtl?.abort(); $('#dlg-out').close(); rfb?.focus(); };
  $('#dlg-out').addEventListener('cancel', () => abortCtl?.abort());

  $('#kbd-btn').onclick = () => openKbd('sheet');
  $('#kbd-close').onclick = () => { $('#dlg-kbd').close(); rfb?.focus(); };
  for (const b of document.querySelectorAll('.tabs [data-tab]')) b.onclick = () => openKbd(b.dataset.tab);
  $('#drill-start').onclick = drillStart;
  $('#drill-skip').onclick = () => drillReveal(true);
  $('#drill-show').onclick = () => drillReveal(false);
  $('#dlg-kbd').addEventListener('keydown', drillKey, true);
  $('#dlg-kbd').addEventListener('cancel', (e) => { if (!$('#drill-run').hidden) e.preventDefault(); }); // Esc is a drill key too

  $('#fs-btn').onclick = () => toggleFullscreen().catch(() => toast('Fullscreen was blocked by the browser'));
  document.addEventListener('fullscreenchange', () => {
    $('#fs-btn').textContent = document.fullscreenElement ? '⛶ Exit fullscreen' : '⛶ Fullscreen';
    setTimeout(() => window.dispatchEvent(new Event('resize')), 100);
  });

  $('#start-exams').addEventListener('change', (e) => {
    if (e.target.name === 'exam') selectExam(e.target.value).then(renderStart).catch((err) => toast(`Cannot load: ${err.message}`));
  });
  $('#exam-title').onclick = startDialog;
  $('#start-go').onclick = () => {
    $('#dlg-start').close();
    useHost(qByN(state.cur));
    const steps = [], other = getPref('labs');
    const clean = !$('#start-clean').closest('label').hidden && $('#start-clean').checked;
    const setup = $('#start-setup').checked && !state.startedAt;
    if (clean) steps.push({ action: 'cleanup-all', mock: other });
    if (setup) steps.push({ action: 'setup-all' });
    if (!steps.length) { beginTimer(); rfb?.focus(); return; }
    const title = setup ? `Setting up all labs · ${exam.title}` : `Removing the labs of ${titleOf(other)}`;
    stream(title, steps, (_, ok) => {
      if (clean && ok) setPref('labs', null);
      if (setup) setPref('labs', exam.mock);
      beginTimer();
      if (ok) $('#out-status').textContent = `${setup ? 'Labs ready' : 'Done'} — the timer has started. Close this window to begin.`;
    });
  };
  $('#start-restart').onclick = async () => {
    if (!(await confirmBox('Restart the exam?', 'Timer and flags are reset and every exam host goes back to its fresh state: all your work on the clusters is removed. Start exam then sets the labs up again.', 'Restart'))) return;
    state = { flags: {}, cur: exam.questions[0].n }; save(); timeUpShown = false;
    usedHost = null; setPref('labs', null);
    $('#dlg-start').close(); show(state.cur); tick();
    stream(`Resetting the hosts · ${exam.title}`, [{ action: 'reset-all' }], (_, ok) => {
      if (ok) $('#out-status').textContent = 'Hosts reset. Close this window, then Start exam.';
      $('#dlg-out').addEventListener('close', startDialog, { once: true });
    });
  };
  $('#dlg-start').addEventListener('cancel', (e) => e.preventDefault());

  window.addEventListener('beforeunload', (e) => { if (running()) { e.preventDefault(); e.returnValue = ''; } });
}

async function main() {
  exams = await (await fetch('/api/exams')).json();
  const saved = getPref('current');
  const first = exams.find((e) => e.mock === saved) || exams.find((e) => e.default) || exams[0];
  await selectExam(first.mock);
  initLayout(); renderSheet(); wire();
  setInterval(tick, 1000);
  connect();
  startDialog();   // also after End exam: it holds "Restart from scratch"
}
main().catch((e) => { document.body.textContent = `Failed to start: ${e.message}`; });
