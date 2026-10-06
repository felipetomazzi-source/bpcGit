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

// "Change" expands the setup panel and focuses the branch after the animation.
{
  const calls = [];
  let done;
  const panel = { setExpanded: v => calls.push('expand:' + v),
    $: () => ({ children: sel => { calls.push('children:' + sel); return { promise: () => ({ done: f => { done = f; } }) }; } }) };
  const branch = { focus: () => calls.push('focus') };
  methods.onChangeRepository.call({ byId: id => ({ repositoryPanel: panel, branchInput: branch })[id] });
  assert.deepEqual(calls, ['expand:true', 'children:.sapMPanelContent']);
  done();
  assert.equal(calls[2], 'focus');
  assert.ok(view.includes('press=".onChangeRepository"'));
}

// Opening the branch dropdown loads branches only when they are not loaded yet.
{
  const base = { configured: true, connection: null, connectionBusy: false,
    config: { url: 'https://h/r.git' }, savedRepositoryUrl: 'https://h/r.git' };
  const run = state => {
    let loads = 0;
    methods.onBranchListOpen.call({
      _model: { getProperty: p => p.slice(1).split('/').reduce((o, k) => o && o[k], state) },
      _testConnection: () => { loads++; }
    });
    return loads;
  };
  assert.equal(run(base), 1);
  assert.equal(run(Object.assign({}, base, { connection: { branches: [] } })), 0, 'already loaded');
  assert.equal(run(Object.assign({}, base, { connectionBusy: true })), 0, 'request running');
  assert.equal(run(Object.assign({}, base, { configured: false })), 0, 'not set up');
  assert.equal(run(Object.assign({}, base, { config: { url: 'https://h/other.git' } })), 0, 'unsaved URL');
}
