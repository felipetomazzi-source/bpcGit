// Local demo of the real bpcGit UI with fictitious sample data, used for the
// screenshots in docs/bpcGit-consultant-guide.pdf. Nothing is written anywhere.
// Run: node tests/demo/server.cjs, then open http://127.0.0.1:4174
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const modules = path.join(root, 'tests/opa/node_modules');
const libraries = ['sap.ui.core', 'sap.m', 'sap.ui.layout', 'sap.ui.unified', 'themelib_sap_belize'];
const builder = new (require(path.join(modules, 'less-openui5')).Builder)();
const themes = new Map();
const files = {
  '/app/Component.js': 'src/zbpc_git.wapa.component.js',
  '/app/manifest.json': 'src/zbpc_git.wapa.manifest.json',
  '/app/controller/App.controller.js': 'src/zbpc_git.wapa.controller_-app.controller.js',
  '/app/view/App.view.xml': 'src/zbpc_git.wapa.view_-app.view.xml'
};
const index = `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>bpcGit</title>
<style>html, body, #content { height: 100%; margin: 0; }</style>
<script>try { localStorage.clear(); } catch (e) {}</script>
<script id="sap-ui-bootstrap" src="/resources/sap-ui-core.js" data-sap-ui-theme="sap_belize"
  data-sap-ui-libs="sap.m" data-sap-ui-compatVersion="edge" data-sap-ui-language="en"
  data-sap-ui-resourceroots='{"bpc.git": "/app/"}'></script>
<script>sap.ui.getCore().attachInit(function () {
  sap.ui.require(["sap/ui/core/ComponentContainer"], function (ComponentContainer) {
    new ComponentContainer({ name: "bpc.git", height: "100%" }).placeAt("content");
  });
});</script></head>
<body class="sapUiBody sapUiSizeCompact" id="content"></body></html>`;

const HEAD = '4f1c2a9e7b3d5f60a1c8e2b94d7f0a3c6e9b1d25';
const day = d => '2026-10-0' + d;
const script = (model, name, status, changedAt, changedBy, size) => ({
  path: 'ADMINAPP/' + model + '/' + name, kind: 'SCRIPT', model, team: '', status,
  inBpc: status !== 'NEW_GIT' && status !== 'DELETED_BPC', changedAt, changedBy, size
});
const SCRIPTS = [
  script('FINANCE', 'DEFAULT.LGF', 'UNCHANGED', day(1) + ' 09:12', 'ANNA.SMITH', 2100),
  script('FINANCE', 'CLEAR_FORECAST.LGF', 'MODIFIED_BPC', day(6) + ' 14:37', 'J.TAYLOR', 1400),
  script('FINANCE', 'COPY_ACTUAL_TO_FCST.LGF', 'UNCHANGED', day(2) + ' 11:05', 'ANNA.SMITH', 1900),
  script('FINANCE', 'CURRENCY_CONVERSION.LGF', 'MODIFIED_GIT', day(3) + ' 16:20', 'M.CHEN', 3300),
  script('FINANCE', 'INTERCO_ELIMINATION.LGF', 'NEW_BPC', day(6) + ' 10:48', 'J.TAYLOR', 2700),
  script('OPEX', 'DEFAULT.LGF', 'UNCHANGED', day(1) + ' 09:15', 'ANNA.SMITH', 900),
  script('OPEX', 'ALLOCATE_OVERHEAD.LGF', 'CONFLICT', day(5) + ' 15:02', 'M.CHEN', 4200),
  script('OPEX', 'HEADCOUNT_COSTS.LGF', 'UNCHANGED', day(4) + ' 08:30', 'R.PATEL', 2600),
  script('OPEX', 'SEED_BUDGET.LGF', 'NEW_GIT', '', '', 0)
];
const workbook = (model, rest, status, changedAt, changedBy, size, team) => ({
  path: model + '/' + (team ? 'TEAM FILES/' + team + '/' : '') + 'EEXCEL/' + rest, kind: 'WORKBOOK',
  model, team: team || '', status, inBpc: true, changedAt, changedBy, size
});
const WORKBOOKS = [
  workbook('FINANCE', 'REPORTS/PL_MONTHLY.XLSX', 'UNCHANGED', day(2) + ' 10:10', 'ANNA.SMITH', 412000),
  workbook('FINANCE', 'REPORTS/BALANCE_SHEET.XLSX', 'MODIFIED_BPC', day(6) + ' 13:22', 'J.TAYLOR', 388000),
  workbook('FINANCE', 'INPUT SCHEDULES/FORECAST_INPUT.XLSM', 'UNCHANGED', day(3) + ' 09:41', 'M.CHEN', 655000),
  workbook('OPEX', 'INPUT SCHEDULES/OPEX_BUDGET.XLSM', 'NEW_BPC', day(6) + ' 08:55', 'R.PATEL', 702000, 'CONTROLLERS')
];

const GIT_TEXT = [
  '// Clears forecast data before a new forecast cycle',
  '*XDIM_MEMBERSET CATEGORY = FORECAST',
  '*XDIM_MEMBERSET TIME = %TIME_SET%',
  '*XDIM_MEMBERSET AUDITTRAIL = INPUT',
  '',
  '*WHEN ACCOUNT',
  '*IS *',
  '  *REC(EXPRESSION = 0)',
  '*ENDWHEN',
  '*COMMIT',
  ''
].join('\r\n');
const BPC_TEXT = [
  '// Clears forecast data before a new forecast cycle',
  '// Only open periods are cleared; closed periods keep their values',
  '*XDIM_MEMBERSET CATEGORY = FORECAST',
  '*XDIM_MEMBERSET TIME = %TIME_SET%',
  '*XDIM_MEMBERSET AUDITTRAIL = INPUT, MANUAL_ADJ',
  '*XDIM_FILTER TIME = [TIME].properties("PERIOD_STATUS") = "OPEN"',
  '',
  '*WHEN ACCOUNT',
  '*IS *',
  '  *REC(EXPRESSION = 0)',
  '*ENDWHEN',
  '*COMMIT',
  ''
].join('\r\n');

const VERSIONS = [
  { commit: 'c41d9a07e2f3b81640ad5c2e9f7b3a1d8e6c0f42', message: 'Clear forecast only for the selected time set',
    author: 'Anna Smith', date: '2026-10-02 11:05' },
  { commit: '9b7e2c41f0a3d6e85c1b4a7f2e9d0c3b6a8f1e57', message: 'Add MANUAL_ADJ audit trail to the clearing scope',
    author: 'Mei Chen', date: '2026-09-24 16:40' },
  { commit: '2e8f1a6c9d3b7e40f5a2c8d1b6e9f3a7c0d4e215', message: 'Initial version of forecast clearing',
    author: 'James Taylor', date: '2026-09-10 09:18' }
].map(v => Object.assign({ present: true, complete: true }, v));

const json = (res, status, body) => {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
};
const body = req => new Promise(resolve => {
  let text = '';
  req.on('data', chunk => { text += chunk; });
  req.on('end', () => resolve(new URLSearchParams(text)));
});

async function api(req, res, resource) {
  const params = req.method === 'POST' ? await body(req) : new URL(req.url, 'http://x').searchParams;
  switch (resource) {
    case 'ping': return json(res, 200, { abapGit: true });
    case 'environments':
      return json(res, 200, { environments: [{ id: 'CORP_PLAN', text: 'Corporate Planning' }, { id: 'CONSOL', text: 'Consolidation' }] });
    case 'config':
      return json(res, 200, { configured: true, url: 'https://bitbucket.org/acme-finance/bpc-content.git', branch: 'main',
        rootFolder: 'bpc', changedBy: 'ANNA.SMITH', changedAt: '2026-10-01' });
    case 'models': return json(res, 200, { models: ['FINANCE', 'OPEX'] });
    case 'dimensions': return json(res, 200, { dimensions: ['ACCOUNT', 'ENTITY', 'TIME'] });
    case 'connection': return json(res, 200, { branches: ['main', 'develop', 'release/2026-11'] });
    case 'workbooks': {
      const kind = params.get('kind');
      const model = params.get('model');
      let rows = kind === 'SCRIPT' ? SCRIPTS : kind ? WORKBOOKS : SCRIPTS.concat(WORKBOOKS);
      if (model) { rows = rows.filter(row => row.model === model); }
      return json(res, 200, { branch: 'main', branchFound: true, commit: HEAD, workbooks: rows });
    }
    case 'diff':
      return json(res, 200, { head: HEAD.slice(0, 7), parts: [{ path: params.get('path'), inGit: true, inBpc: true,
        gitSize: GIT_TEXT.length, bpcSize: BPC_TEXT.length, changed: true, textAvailable: true,
        gitText: GIT_TEXT, bpcText: BPC_TEXT }] });
    case 'history':
      return json(res, 200, { head: HEAD, truncated: false, versions: VERSIONS });
    case 'transports':
      return json(res, 200, { requests: [{ request: 'DEVK900245', text: 'Forecast clearing fix' },
        { request: 'DEVK900231', text: 'OPEX allocation Q4' }] });
    default:
      return json(res, 405, { error: { message: 'The demo does not change anything' } });
  }
}

http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const theme = /^\/resources\/(sap\/[^]+)\/themes\/(sap_belize(?:_plus)?)\/library(?:-parameters\.json|\.css)$/.exec(url.pathname);
  if (theme) {
    const key = theme[1] + theme[2];
    try {
      if (!themes.has(key)) {
        themes.set(key, builder.build({ lessInputPath: theme[1] + '/themes/' + theme[2] + '/library.source.less',
          rootPaths: libraries.map(name => path.join(modules, '@openui5', name, 'src')),
          library: { name: theme[1].replace(/\//g, '.') }, rtl: false }));
      }
      const result = await themes.get(key);
      const isJson = url.pathname.endsWith('.json');
      res.writeHead(200, { 'Content-Type': isJson ? 'application/json' : 'text/css' });
      res.end(isJson ? JSON.stringify(result.variables) : result.css);
    } catch (error) { console.error(error); res.writeHead(500); res.end('Theme build failed'); }
    return;
  }
  if (url.pathname.startsWith('/sap/bc/zbpc_git/')) {
    await api(req, res, url.pathname.slice('/sap/bc/zbpc_git/'.length));
    return;
  }
  if (url.pathname === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(index);
    return;
  }
  let file = files[url.pathname];
  if (url.pathname.startsWith('/resources/')) {
    const relative = url.pathname.slice('/resources/'.length);
    if (relative.split('/').some(part => part === '..')) { res.writeHead(400); res.end(); return; }
    for (const library of libraries) {
      const candidate = path.join(modules, '@openui5', library, 'src', relative);
      if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) { file = candidate; break; }
    }
  }
  if (!file) { res.writeHead(404); res.end(); return; }
  const types = { '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json', '.xml': 'application/xml',
    '.css': 'text/css', '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf' };
  res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
  res.end(fs.readFileSync(path.isAbsolute(file) ? file : path.join(root, file)));
}).listen(4174, '127.0.0.1', () => console.log('bpcGit demo: http://127.0.0.1:4174'));
