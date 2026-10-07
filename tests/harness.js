// Shared helpers for the test pages. Each page includes this file and calls test(async () => { ... }).
//
// loadApp() fetches web/index.html, optionally puts a script at the top of its <head> (to fake the iOS
// bridges before the app's own script runs) and shows it in an iframe on this page. The iframe shares this
// page's origin, so the tests set and read the app's localStorage directly and call its functions through
// app.E('…'). run.sh opens every page in headless Chrome and reads the results from <pre id="out">.

const STORAGE_KEY = 'golf-strokes.v1';
const DAY = 86400000;
const results = [];
const out = document.getElementById('out') || document.body.appendChild(document.createElement('pre'));
out.id = 'out';
let frame = null;

// Messages the app posts to the fake bridges (see WATCH_BRIDGE, MAP_BRIDGE).
window.posted = [];
const WATCH_BRIDGE = '<script>window.webkit = { messageHandlers: { watch: { postMessage: m => parent.posted.push(m) } } };</script>';
const MAP_BRIDGE = '<script>window.webkit = { messageHandlers: { courseMap: { postMessage: m => parent.posted.push(m) } } };</script>';

function ok(name, pass, detail) {
  results.push({ name, pass: !!pass });
  out.textContent += (pass ? 'PASS ' : 'FAIL ') + name + (pass || detail === undefined ? '' : ' :: ' + detail) + '\n';
}

const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

// Shows the given HTML in a fresh iframe and waits for it to load.
async function loadHtml(html) {
  if (frame) frame.remove();
  frame = document.createElement('iframe');
  frame.width = 390;
  frame.height = 844;
  document.body.appendChild(frame);
  await new Promise(resolve => { frame.onload = resolve; frame.srcdoc = html; });
}

// Loads the app. `data` replaces what is saved first (omit it to keep the current save, as after a reload);
// `inject` is HTML put at the top of <head>.
async function loadApp({ data, inject = '' } = {}) {
  if (data !== undefined) {
    localStorage.clear();
    if (data) localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  }
  const html = await (await fetch('../web/index.html', { cache: 'no-store' })).text();
  await loadHtml(html.replace('<head>', '<head>' + inject));
  await wait(300);
  const w = frame.contentWindow, d = frame.contentDocument;
  return {
    w, d,
    E: code => w.eval(code),
    q: sel => d.querySelector(sel),
    qa: sel => [...d.querySelectorAll(sel)],
    click: async sel => { d.querySelector(sel).click(); await wait(20); },
    saved: () => JSON.parse(localStorage.getItem(STORAGE_KEY))
  };
}

// Runs a test page and reports a summary; the page title becomes PASSED or FAILED when it is done.
function test(fn) {
  (async () => {
    try { await fn(); } catch (err) { ok('no exception', false, err && err.stack); }
    const failed = results.filter(r => !r.pass).length;
    out.textContent += `${results.length - failed} passed, ${failed} failed\n`;
    document.title = failed || !results.length ? 'FAILED' : 'PASSED';
  })();
}

// Test data. A nine-hole course with par per hole and index 1–9 in hole order.
function holeData(pars = [4, 4, 4, 4, 4, 4, 4, 4, 4]) {
  const data = {};
  pars.forEach((par, i) => { data[i + 1] = { par, length: 300, index: i + 1 }; });
  return data;
}

function strokes(n, prefix = 's', club = '7i') {
  return Array.from({ length: n }, (_, i) => ({ id: `${prefix}${i}`, t: i + 1, club }));
}

function makeRound(id, extra = {}) {
  return Object.assign({ id, name: id, createdAt: Date.now(), holeCount: 9, startHole: 1, currentHole: 1,
    locked: [], holeData: holeData(), holes: {} }, extra);
}
