const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let methods;
vm.runInNewContext(fs.readFileSync('src/zbpc_git.wapa.controller_-app.controller.js', 'utf8'), {
  sap: { ui: { define: (names, factory) => factory.apply(null, names.map(name =>
    name.endsWith('/Controller') ? { extend: (name, m) => { methods = m; } } : { show() {} })) } }
});
const cases = [
  ['https://x-token-auth:secret=tok@bitbucket.org/w/r.git', 'release/x', 'bitbucket.org/w/r', 'release/x'],
  ['https://user%40mail.com:a%40b@github.com/owner/repo.git/', '', 'github.com/owner/repo', 'main'],
  ['https://github.com/owner/repo', 'dev', 'github.com/owner/repo', 'dev'],
  ['', undefined, '', 'main']
];
for (const [url, branch, label, shownBranch] of cases) {
  const properties = {};
  methods._showConfig.call({ _model: { setProperty: (p, v) => { properties[p] = v; } } },
    { configured: !!url, url, branch, changedBy: 'U', changedAt: 'T' });
  assert.equal(properties['/savedRepositoryLabel'], label);
  assert.equal(properties['/savedBranch'], shownBranch);
  assert.ok(!properties['/savedRepositoryLabel'].includes('secret') && !properties['/savedRepositoryLabel'].includes('%40'));
  // The editable configuration keeps the complete URL.
  assert.equal(properties['/config'].url, url);
}
const view = fs.readFileSync('src/zbpc_git.wapa.view_-app.view.xml', 'utf8');
assert.ok(view.indexOf('id="repositoryPanel"') < view.indexOf('id="loadType"'), 'Repository setup precedes the object list');
assert.ok(view.indexOf('id="branchSummary"') < view.indexOf('id="setupForm"'), 'Branch summary sits in the panel header');
console.log('repository summary: ok');
