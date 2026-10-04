const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let methods;
vm.runInNewContext(fs.readFileSync('src/zbpc_git.wapa.controller_-app.controller.js', 'utf8'), {
  sap: { ui: { define: (names, factory) => factory.apply(null, names.map(name =>
    name.endsWith('/Controller') ? { extend: (name, m) => { methods = m; } } : function () {})) } }
});
function configReply(reply) {
  const properties = {};
  methods._showConfig.call({ _model: { setProperty: (p, v) => { properties[p] = v; } } }, reply);
  return properties['/config'];
}
const existing = configReply({ url: 'https://bitbucket.org/test/repo.git', configured: true });
assert.equal(existing.lfsEnabled, false, 'existing repository remains opt-out');
assert.equal(existing.lfsThresholdMb, 5);
const opted = configReply({ url: existing.url, branch: 'main', lfsEnabled: true, lfsThresholdMb: 10 });
assert.equal(opted.lfsEnabled, true);
assert.equal(opted.lfsThresholdMb, 10);
let saved;
const context = {
  _model: { getProperty: p => p === '/config' ? opted : 'ENV', setProperty: () => {} },
  _importRepositoryLogin: () => true,
  _request: (resource, body) => { saved = body; return { then: () => {} }; },
  _setupFailed: () => {}
};
methods.onSave.call(context);
assert.equal(saved.lfsEnabled, true);
assert.equal(saved.lfsThresholdMb, 10);
opted.lfsThresholdMb = 0;
methods.onSave.call(context);
assert.equal(saved.lfsThresholdMb, 0, 'invalid input reaches backend validation instead of silently becoming 5');
opted.lfsEnabled = false;
methods.onSave.call(context);
assert.equal(saved.lfsEnabled, false);
console.log('LFS setup UI checks passed');
