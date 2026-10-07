const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let methods;
vm.runInNewContext(fs.readFileSync('src/zbpc_git.wapa.controller_-app.controller.js', 'utf8'), {
  sap: { ui: { define: (names, factory) => factory.apply(null, names.map(name =>
    name.endsWith('/Controller') ? { extend: (name, m) => { methods = m; } } : { show() {} })) } }
});
(async function () {
  const keep = { path: 'M/EEXCEL/REPORTS/OTHER.XLSX', status: 'MODIFIED_BPC', selected: true };
  const chosen = { path: 'M/EEXCEL/REPORTS/ONE.XLSX' };
  const data = { environment: 'ENV', loadedScope: { kind: 'REPORT', model: 'M' },
    overview: { commit: 'old' }, workbooks: [chosen, keep] };
  const c = Object.assign({}, methods, { _loadSequence: 1, _toRow: x => x,
    _applyFilter() {}, _updateSelection() {},
    _model: { getProperty: p => data[p.slice(1)], setProperty: (p,v) => {data[p.slice(1)] = v;} } });
  let sent;
  c._gitRequest = async (resource, params) => { sent = { resource, params }; return { commit: 'new', branch: 'main', workbooks: [{path: chosen.path, status: 'UNCHANGED'}] }; };
  await c._refreshCommittedRows([chosen], 'new');
  assert.equal(sent.params.paths, chosen.path);
  assert.equal(sent.params.kind, 'REPORT'); assert.equal(sent.params.model, 'M');
  assert.equal(data.workbooks.length, 2); assert.ok(data.workbooks.includes(keep));
  assert.equal(keep.status, 'MODIFIED_BPC'); assert.equal(keep.selected, true);
  assert.equal(data.overview.commit, 'new'); assert.equal(data.workbooksBusy, false);
  c._gitRequest = async () => ({commit: 'delete', branch:'main', workbooks: []});
  await c._refreshCommittedRows([chosen], 'delete');
  assert.deepEqual(data.workbooks, [keep], 'Deleted paths disappear without losing unrelated rows');
  c._gitRequest = async () => ({commit: 'concurrent', workbooks: []});
  await c._refreshCommittedRows([keep], 'expected');
  assert.equal(data.overview.commit, 'delete', 'Concurrent head never advances an unrefreshed overview');
  assert.match(data.workbooksError, /commit succeeded/i);
  c._gitRequest = async () => { c._loadSequence++; return {commit:'ignored',workbooks:[]}; };
  await c._refreshCommittedRows([keep], 'ignored');
  assert.equal(data.overview.commit, 'delete', 'Stale replies cannot modify another scope');
  assert.match(methods._openCommitDialog.toString(), /_refreshCommittedRows/);
  console.log('Selected-path commit refresh checks passed');
})();
