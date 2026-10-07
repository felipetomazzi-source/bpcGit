// Runs the UI5 1.52 harness suites headless and exits non-zero on failure:
//   node tests/opa/run.cjs
// Starts tests/opa/server.cjs unless one already answers on port 4173, then
// drives an installed Chrome or Edge through the DevTools protocol (Node's
// built-in WebSocket; no extra packages). Set BPCGIT_BROWSER to a browser
// executable to choose one. Needs `npm ci --ignore-scripts --prefix tests/opa`.
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const BASE = 'http://127.0.0.1:4173';
const TIMEOUT_MS = 180000;
// Each suite publishes QUnit's result; the check returns null until it is done.
const SUITES = [
  { name: 'OPA5 journey', path: '/', result: 'window.opaResult || null' },
  { name: 'Embedded component', path: '/embedded.html', result: `(() => {
      const text = (document.getElementById('qunit-testresult') || {}).textContent || '';
      const match = /(\\d+) assertions of (\\d+) passed, (\\d+) failed/.exec(text);
      return match ? { passed: +match[1], total: +match[2], failed: +match[3] } : null;
    })()` }
];

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

function findBrowser() {
  const candidates = [process.env.BPCGIT_BROWSER,
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/microsoft-edge'];
  const found = candidates.find(file => file && fs.existsSync(file));
  if (!found) { throw new Error('No Chrome or Edge found; set BPCGIT_BROWSER to a browser executable'); }
  return found;
}

async function serverUp() {
  try { return (await fetch(BASE + '/')).ok; } catch (e) { return false; }
}

async function waitFor(check, timeout, what) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    const value = await check();
    if (value) { return value; }
    await sleep(250);
  }
  throw new Error('Timed out waiting for ' + what);
}

// Minimal DevTools protocol client over one page's WebSocket.
function connect(url) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    const pending = new Map();
    let id = 0;
    socket.onmessage = event => {
      const message = JSON.parse(event.data);
      if (message.id && pending.has(message.id)) {
        const { resolve: done, reject: fail } = pending.get(message.id);
        pending.delete(message.id);
        if (message.error) { fail(new Error(message.error.message)); } else { done(message.result); }
      }
    };
    socket.onerror = () => reject(new Error('Cannot connect to the browser'));
    socket.onopen = () => resolve({
      send: (method, params) => new Promise((done, fail) => {
        pending.set(++id, { resolve: done, reject: fail });
        socket.send(JSON.stringify({ id, method, params: params || {} }));
      }),
      close: () => socket.close()
    });
  });
}

async function runSuite(port, suite) {
  const target = await (await fetch(`http://127.0.0.1:${port}/json/new?${encodeURIComponent(BASE + suite.path)}`,
    { method: 'PUT' })).json();
  const page = await connect(target.webSocketDebuggerUrl);
  try {
    const evaluate = async expression => (await page.send('Runtime.evaluate',
      { expression, returnByValue: true })).result.value;
    const result = await waitFor(() => evaluate(suite.result), TIMEOUT_MS, suite.name);
    // Failed test name, then each failed assertion's message and expected/actual.
    const failures = result.failed ? await evaluate(`Array.from(document.querySelectorAll('#qunit-tests > li.fail'))
      .map(test => ((test.querySelector('.test-name') || {}).textContent || 'Test') + ':\\n' +
        Array.from(test.querySelectorAll('ol li.fail')).map(assertion =>
          '- ' + assertion.innerText.replace(/\\s+/g, ' ').trim().slice(0, 400)).join('\\n'))`) : [];
    return Object.assign({ failures }, result);
  } finally {
    page.close();
    await fetch(`http://127.0.0.1:${port}/json/close/${target.id}`).catch(() => {});
  }
}

(async function () {
  const started = [];
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'bpcgit-ui5-'));
  let ok = true;
  try {
    if (!fs.existsSync(path.join(__dirname, 'node_modules', '@openui5'))) {
      throw new Error('Harness packages missing: run npm ci --ignore-scripts --prefix tests/opa');
    }
    if (!(await serverUp())) {
      const server = spawn(process.execPath, [path.join(__dirname, 'server.cjs')], { stdio: 'ignore' });
      started.push(server);
      await waitFor(serverUp, 30000, 'the harness server on port 4173');
    }
    // A fresh server compiles the themes on first request, which is slow
    // enough to time out the OPA component start; compile them first.
    for (const library of ['sap/ui/core', 'sap/m', 'sap/ui/layout', 'sap/ui/unified']) {
      for (const file of ['library.css', 'library-parameters.json']) {
        await fetch(`${BASE}/resources/${library}/themes/sap_belize/${file}`).catch(() => {});
      }
    }
    const browser = spawn(findBrowser(), ['--headless=new', '--remote-debugging-port=0', '--no-first-run',
      '--no-default-browser-check', '--disable-gpu', '--window-size=1400,900', '--user-data-dir=' + profile,
      'about:blank'], { stdio: 'ignore' });
    started.push(browser);
    const portFile = path.join(profile, 'DevToolsActivePort');
    // The browser writes (and on Windows briefly locks) this file when ready.
    const port = await waitFor(() => {
      try { return fs.readFileSync(portFile, 'utf8').split('\n')[0]; } catch (e) { return ''; }
    }, 30000, 'the headless browser');
    for (const suite of SUITES) {
      let result = await runSuite(port, suite);
      if (result.failed !== 0 || !result.total) {
        // A cold harness occasionally fails loading UI5 modules; a real
        // failure fails again.
        console.log(`RETRY ${suite.name}: ${result.failed} failed on the first run`);
        result = await runSuite(port, suite);
      }
      const passed = result.failed === 0 && result.total > 0;
      ok = ok && passed;
      console.log(`${passed ? 'PASS' : 'FAIL'} ${suite.name}: ${result.passed} of ${result.total} assertions passed`);
      result.failures.forEach(text => console.log('  ' + text.replace(/\n/g, '\n  ')));
    }
  } catch (error) {
    ok = false;
    console.error('ERROR ' + error.message);
  } finally {
    started.reverse().forEach(child => { try { child.kill(); } catch (e) { /* already gone */ } });
    await sleep(500);
    try { fs.rmSync(profile, { recursive: true, force: true }); } catch (e) { /* browser may still hold files */ }
  }
  process.exitCode = ok ? 0 : 1;
})();
