const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let methods;
vm.runInNewContext(fs.readFileSync('src/zbpc_git.wapa.controller_-app.controller.js', 'utf8'), {
  sap: { ui: { define: (names, factory) => factory.apply(null, names.map(name =>
    name.endsWith('/Controller') ? { extend: (name, m) => { methods = m; } } : function () {})) } }
});
function check(url, clean, user, token, valid = true) {
  const data = { '/config/url': url };
  let credentials;
  const context = { _model: { getProperty: p => data[p], setProperty: (p, v) => { data[p] = v; } },
    _setCredentials: c => { credentials = c; } };
  assert.equal(methods._importRepositoryLogin.call(context), valid);
  assert.equal(data['/config/url'], clean);
  if (user) { assert.equal(credentials.user, user); assert.equal(credentials.token, token); }
  else { assert.equal(credentials, undefined); }
}
check('https://x-token-auth:fake=token:part@bitbucket.org/w/r.git',
  'https://bitbucket.org/w/r.git', 'x-token-auth', 'fake=token:part');
check('https://user%40example.com:a%40b%3Ac%25@host/r.git',
  'https://host/r.git', 'user@example.com', 'a@b:c%');
const longToken = 'fake'.repeat(150);
check('https://user:' + longToken + '@host/r.git', 'https://host/r.git', 'user', longToken);
check('https://host/r.git', 'https://host/r.git');
check('https://user@host/r.git', 'https://host/r.git', null, null, false);
check('https://user:%ZZ@host/r.git', 'https://host/r.git', null, null, false);
assert.match(methods.onSave.toString(), /_importRepositoryLogin/);
const config = { url: 'https://user:fake-secret@host/r.git', branch: 'main' };
let saved;
const saveContext = {
  _model: {
    getProperty: p => p === '/config' ? config : p === '/config/url' ? config.url : 'ENV',
    setProperty: (p, value) => { if (p === '/config/url') { config.url = value; } }
  },
  _importRepositoryLogin: methods._importRepositoryLogin,
  _setCredentials: () => {},
  _request: (resource, body) => { saved = body; return { then: () => {} }; },
  _setupFailed: () => {}
};
methods.onSave.call(saveContext);
assert.equal(saved.url, 'https://host/r.git');
assert.ok(!JSON.stringify(saved).includes('fake-secret'), 'configuration payload contains no token');
console.log('Repository URL login tests passed');
