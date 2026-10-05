const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let methods;
vm.runInNewContext(fs.readFileSync('src/zbpc_git.wapa.controller_-app.controller.js', 'utf8'), {
  sap: { ui: { define(names, factory) { factory.apply(null, names.map(name =>
    name.endsWith('/Controller') ? { extend(name, value) { methods = value; } } : { show() {} })); } } }
});
(async function () {
  const data = { environment: 'ENV', config: { url: 'https://example.invalid/repo.git', branch: 'main', rootFolder: 'content/bpc' } };
  const controller = Object.assign({}, methods, {
    _model: { getProperty(key) { return key.slice(1).split('/').reduce((o, p) => o[p], data); },
      setProperty(key, value) { const parts = key.slice(1).split('/'); const last = parts.pop(); parts.reduce((o,p)=>o[p],data)[last]=value; } },
    _importRepositoryLogin() { return true; }, onLoadScopeChange() {}, _loadModels() {}
  });
  let sent;
  controller._request = async (resource, params, method) => {
    sent = { resource, params, method };
    return Object.assign({}, params, { configured: true });
  };
  controller.onSave(); await new Promise(resolve => setImmediate(resolve));
  assert.equal(sent.params.rootFolder, 'content/bpc');
  assert.equal(data.config.rootFolder, 'content/bpc');
  controller._showConfig({ configured: true, url: 'https://example.invalid/old.git' });
  assert.equal(data.config.rootFolder, '', 'Old responses retain legacy empty root');
  console.log('Root folder configuration round-trip checks passed');
})();
