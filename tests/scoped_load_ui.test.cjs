const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let methods;
vm.runInNewContext(fs.readFileSync('src/zbpc_git.wapa.controller_-app.controller.js', 'utf8'), {
  sap: { ui: { define: function (names, factory) {
    factory.apply(null, names.map(function (name) {
      return name.endsWith('/Controller') ? { extend: function (name, value) { methods = value; } } : {};
    }));
  } } }, Date: Date, Math: Math, jQuery: { extend: Object.assign }
});
const tick = () => new Promise(resolve => setImmediate(resolve));
function fixture() {
  const data = { environment: 'ENV', loadScope: { kind: 'TRANSFORMATION', model: 'MODEL' },
    filter: { model: 'ALL', type: 'ALL', location: 'ALL' }, workbooks: [], models: [] };
  const pending = [];
  const instance = Object.assign({}, methods, {
    _model: {
      getProperty: function (key) { return key.slice(1).split('/').reduce((value, part) => value && value[part], data); },
      setProperty: function (key, value) {
        const parts = key.slice(1).split('/'); const last = parts.pop();
        parts.reduce((value, part) => value[part], data)[last] = value;
      }
    },
    _request: request, _gitRequest: request,
    _applyFilter: function () {}, _updateSelection: function () {}, _toRow: function (row) { return row; }
  });
  function request(resource, params) {
    return new Promise((resolve, reject) => pending.push({ resource, params, resolve, reject }));
  }
  return { instance, data, pending };
}
const response = { branch: 'main', branchFound: true, commit: 'a'.repeat(40),
  timings: { bpcMs: 100, gitMs: 200, compareMs: 20 }, workbooks: [{ path: 'MODEL/FILE.XLS', model: 'MODEL', team: '' }] };
(async function () {
  let f = fixture();
  f.instance._loadConfig('ENV');
  assert.equal(f.pending[0].resource, 'config');
  f.pending[0].resolve({ configured: true, branch: 'main' }); await tick();
  assert.equal(f.pending[1].resource, 'models', 'startup reads lightweight model metadata');
  f.pending[1].resolve({ models: ['MODEL', 'OTHER'] }); await tick();
  assert.equal(f.pending.length, 2, 'startup never lists or compares files');
  assert.equal(f.data.overviewLoaded, false);
  f.data.loadScope = { kind: 'TRANSFORMATION', model: 'MODEL' };
  f.instance.onLoadWorkbooks();
  assert.equal(f.pending[2].params.kind, 'TRANSFORMATION');
  assert.equal(f.pending[2].params.model, 'MODEL');
  f.pending[2].resolve(response); await tick();
  assert.equal(f.data.workbooks.length, 1);
  assert.equal(f.data.models.length, 3, 'loading one model preserves other model choices');
  assert.equal(f.data.overview.timings.gitMs, 200);
  f.data.loadScope = { kind: 'SCRIPT', model: 'ALL' };
  f.instance.onRefreshWorkbooks();
  assert.equal(f.pending[3].params.kind, 'TRANSFORMATION', 'refresh uses the loaded selection');
  f.pending[3].resolve(response); await tick();

  f = fixture();
  f.instance.onLoadWorkbooks();
  f.data.loadScope = { kind: 'PACKAGE', model: 'ALL' };
  f.instance.onLoadScopeChange();
  assert.equal(f.data.overviewLoaded, false);
  assert.equal(f.data.loadedScope, null);
  f.instance.onLoadWorkbooks();
  assert.equal(f.pending[1].params.model, '', 'All models uses an empty backend scope');
  f.pending[0].resolve(response); await tick();
  assert.equal(f.data.workbooks.length, 0, 'a previous selection cannot repopulate the table');
  assert.equal(f.data.workbooksBusy, true, 'stale completion cannot release the new request busy state');
  f.pending[1].reject(new Error('Git unavailable')); await tick();
  assert.equal(f.data.workbooksError, 'Git unavailable');
  assert.equal(f.data.workbooksBusy, false);

  f = fixture();
  f.data.loadScope = { kind: 'ALL', model: 'MODEL' };
  f.instance.onLoadWorkbooks();
  assert.equal(f.pending[0].params.kind, '', 'All objects uses the backend all-type scope');
  assert.equal(f.pending[0].params.model, 'MODEL', 'All objects preserves the selected model');
  f.pending[0].resolve(response); await tick();
  f.instance.onRefreshWorkbooks();
  assert.equal(f.pending[1].params.kind, '', 'refresh preserves All objects');
  f.pending[1].resolve(response); await tick();

  f = fixture();
  f.instance._loadConfig('ENV');
  f.data.environment = 'OTHER';
  f.pending[0].resolve({ configured: true }); await tick();
  assert.equal(f.pending.length, 1, 'stale configuration must not start metadata or Git requests');
  for (const kind of ['REPORT', 'SCHEDULE', 'OTHER']) {
    f = fixture();
    f.data.loadScope = { kind: kind, model: 'MODEL' };
    f.instance.onLoadWorkbooks();
    assert.equal(f.pending[0].params.kind, kind, 'workbook library scope reaches SAP');
    f.pending[0].resolve(response); await tick();
    f.instance.onRefreshWorkbooks();
    assert.equal(f.pending[1].params.kind, kind, 'refresh preserves the workbook library');
    f.pending[1].resolve(response); await tick();
  }
  for (const kind of ['TEAM', 'TASKPROFILE', 'DATAPROFILE']) {
    f = fixture();
    f.data.loadScope = { kind: kind, model: 'MODEL' };
    f.instance.onLoadScopeChange();
    assert.equal(f.data.loadScope.model, 'ALL', 'security objects cannot inherit a model restriction');
    f.instance.onLoadWorkbooks();
    assert.equal(f.pending[0].params.kind, kind);
    assert.equal(f.pending[0].params.model, '', 'security requests target the environment');
    f.pending[0].resolve(response); await tick();
    const row = methods._toRow({ path: 'SECURITY/TEAMS/LOCAL.xml', kind: kind, model: '', team: '', status: 'UNCHANGED' });
    assert.equal(row.type, kind, 'security types retain their own labels');
    assert.equal(row.location, 'SECURITY');
    assert.equal(row.committable, false);
  }
  console.log('Scoped loading UI regression checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
