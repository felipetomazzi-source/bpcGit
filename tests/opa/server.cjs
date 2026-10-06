// Local-only UI5 harness: serves the real BSP sources with a read-only mock API.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const libraries = ['sap.ui.core', 'sap.m', 'sap.ui.layout', 'sap.ui.unified', 'themelib_sap_belize'];
const builder = new (require('less-openui5').Builder)();
const themes = new Map();
const files = {
  '/app/Component.js': 'src/zbpc_git.wapa.component.js',
  '/app/manifest.json': 'src/zbpc_git.wapa.manifest.json',
  '/app/controller/App.controller.js': 'src/zbpc_git.wapa.controller_-app.controller.js',
  '/app/view/App.view.xml': 'src/zbpc_git.wapa.view_-app.view.xml',
  '/': 'tests/opa/index.html',
  '/journey.js': 'tests/opa/journey.js',
  '/embedded.html': 'tests/opa/embedded.html',
  '/embedded.js': 'tests/opa/embedded.js'
};
http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const theme = /^\/resources\/(sap\/[^]+)\/themes\/(sap_belize(?:_plus)?)\/library(?:-parameters\.json|\.css)$/.exec(url.pathname);
  if (theme) {
    const library = theme[1];
    const key = library + theme[2];
    try {
      if (!themes.has(key)) {
        themes.set(key, builder.build({ lessInputPath: library + '/themes/' + theme[2] + '/library.source.less',
          rootPaths: libraries.map(name => path.join(__dirname, 'node_modules/@openui5', name, 'src')),
          library: { name: library.replace(/\//g, '.') }, rtl: false }));
      }
      const result = await themes.get(key);
      const json = url.pathname.endsWith('.json');
      res.writeHead(200, { 'Content-Type': json ? 'application/json' : 'text/css' });
      res.end(json ? JSON.stringify(result.variables) : result.css);
    } catch (error) { console.error(error); res.writeHead(500); res.end('Theme build failed'); }
    return;
  }
  if (url.pathname.startsWith('/sap/bc/zbpc_git/')) {
    const resource = url.pathname.split('/').pop();
    const fixtures = {
      ping: { abapGit: true },
      environments: { environments: [{ id: 'TEST', text: 'Local test environment' }, { id: 'HOST_A' }, { id: 'HOST_B' }] },
      config: { configured: true, url: 'https://example.invalid/test.git', branch: 'main', changedBy: 'TEST', changedAt: '2026-10-04' },
      models: { models: ['PLAN'] },
      dimensions: { dimensions: ['ACCOUNT', 'ENTITY'] }
    };
    if (resource === 'workbooks' && req.method === 'POST') {
      let body = '';
      req.on('data', chunk => { body += chunk; });
      req.on('end', () => {
        const params = new URLSearchParams(body);
        if (params.get('kind') !== 'DIMMEMBER' || params.get('dimension') !== 'ACCOUNT' || params.get('model')) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: { message: 'Unexpected member load scope' } }));
          return;
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ branch: 'main', branchFound: true, commit: 'a'.repeat(40),
          workbooks: [{ path: 'DIMENSIONS/ACCOUNT/MEMBERS/CASH%20TOTAL.xml', kind: 'DIMMEMBER',
            model: '', team: '', status: 'MODIFIED_BPC', memberDescription: 'Cash total', generated: true }] }));
      });
      return;
    }
    res.writeHead(fixtures[resource] && req.method === 'GET' ? 200 : 405, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(fixtures[resource] || { error: { message: 'Writes are disabled in the local harness' } }));
    return;
  }
  let file = files[url.pathname];
  if (url.pathname.startsWith('/resources/')) {
    const relative = url.pathname.slice('/resources/'.length);
    if (relative.split('/').some(part => part === '..')) { res.writeHead(400); res.end(); return; }
    for (const library of libraries) {
      const candidate = path.join('tests/opa/node_modules/@openui5', library, 'src', relative);
      if (fs.existsSync(path.join(root, candidate)) && fs.statSync(path.join(root, candidate)).isFile()) { file = candidate; break; }
    }
  }
  if (!file) { res.writeHead(404); res.end(); return; }
  const types = { '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json', '.xml': 'application/xml', '.css': 'text/css', '.woff': 'font/woff', '.ttf': 'font/ttf' };
  res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
  res.end(fs.readFileSync(path.join(root, file)));
}).listen(4173, '127.0.0.1', () => console.log('OPA5 harness: http://127.0.0.1:4173'));
