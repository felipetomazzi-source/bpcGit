const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let methods;
vm.runInNewContext(fs.readFileSync('src/zbpc_git.wapa.controller_-app.controller.js', 'utf8'), {
  sap: { ui: { define: (names, factory) => factory.apply(null, names.map(name =>
    name.endsWith('/Controller') ? { extend: (name, m) => { methods = m; } } : { show() {} })) } }
});
(async function () {
  const urls = [
    'https://x-token-auth:fake=token:part@bitbucket.org/w/r.git',
    'https://user%40example.com:a%40b%3Ac%25@host/r.git',
    'https://user:' + 'fake'.repeat(150) + '@github.com/owner/repo.git'
  ];
  for (const url of urls) {
    const data = { config: { url, branch: 'release/test' }, environment: 'ENV' };
    const context = Object.assign({}, methods, {
      _model: {
        getProperty: p => p.slice(1).split('/').reduce((o, key) => o && o[key], data),
        setProperty: (p, value) => { const keys = p.slice(1).split('/'); const last = keys.pop();
          keys.reduce((o, key) => o[key], data)[last] = value; }
      },
      onLoadScopeChange() {}, _loadModels() {},
      _setCredentials() { throw new Error('URL credentials must remain in the configured URL'); }
    });
    context.onRepositoryUrlChange();
    assert.equal(data.config.url, url);
    let sent;
    context._request = async (resource, body) => { sent = body; return Object.assign({ configured: true }, body); };
    context.onSave(); await new Promise(resolve => setImmediate(resolve));
    assert.equal(sent.url, url);
    assert.equal(data.config.url, url, 'Save response preserves the URL');
    assert.equal(data.config.branch, 'release/test');
    assert.deepEqual(Array.from(data.branches), ['release/test'], 'Saved branch remains an option after reload');
    context._gitRequest = async () => ({ branches: ['main', 'feature/new'] });
    context._testConnection(); await new Promise(resolve => setImmediate(resolve));
    assert.equal(data.config.branch, 'release/test', 'Branch advertisement must not erase the configured branch');
    assert.deepEqual(Array.from(data.branches), ['release/test', 'main', 'feature/new']);
    context.onRepositoryUrlChange();
    assert.equal(data.config.branch, 'release/test');
  }
  console.log('Repository URL preservation and branch reload checks passed');
})();
