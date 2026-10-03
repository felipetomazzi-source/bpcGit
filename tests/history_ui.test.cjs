const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
let controller;
const controls = [];
const toasts = [];
function Control(settings) {
  this.settings = settings || {};
  this.items = [];
  this.values = {};
  this.enabled = this.settings.enabled;
  controls.push(this);
}
['setBusy', 'setVisible', 'setEnabled', 'setText'].forEach(function (name) {
  Control.prototype[name] = function (value) { this[name.slice(3).toLowerCase()] = value; return this; };
});
Control.prototype.addItem = function (item) { this.items.push(item); return this; };
Control.prototype.destroyItems = function () { this.items = []; };
Control.prototype.data = function (key, value) {
  if (arguments.length === 1) { return this.values[key]; }
  this.values[key] = value; return this;
};
Control.prototype.attachSelectionChange = function (callback) { this.select = callback; };
Control.prototype.open = function () { this.opened = true; };
Control.prototype.close = function () { if (this.settings.afterClose) { this.settings.afterClose(); } };
Control.prototype.destroy = function () { this.destroyed = true; };
Control.prototype.addStyleClass = function () { return this; };
const messageBox = {
  Action: { OK: 'OK', CANCEL: 'CANCEL' },
  confirm: function (text, options) { this.text = text; this.answer = options.onClose; }
};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../src/zbpc_git.wapa.controller_-app.controller.js'), 'utf8'), {
  sap: { ui: { define: function (names, factory) {
    const modules = names.map(function (name) {
      if (name.endsWith('/Controller')) { return { extend: function (name, methods) { controller = methods; } }; }
      if (name.endsWith('/MessageToast')) { return { show: function (text) { toasts.push(text); } }; }
      if (name.endsWith('/MessageBox')) { return messageBox; }
      return Control;
    });
    factory.apply(null, modules);
  } } },
  jQuery: { extend: Object.assign },
  Date: Date,
  Math: Math
});
const tick = function () { return new Promise(function (resolve) { setImmediate(resolve); }); };
function fixture(response) {
  controls.length = 0;
  const row = { path: 'MODEL/DATAMANAGER/TRANSFORMATIONFILES/IMPORT.XLS', name: 'IMPORT.XLS', selected: true };
  const values = { '/workbooks': [row], '/environment': 'ENV' };
  const calls = [];
  const instance = Object.assign({}, controller, {
    _model: { getProperty: function (key) { return values[key]; }, setProperty: function (key, value) { values[key] = value; } },
    getView: function () { return { addDependent: function () {} }; },
    _gitRequest: function (resource, params) {
      calls.push({ resource: resource, params: params });
      return Promise.resolve(resource === 'history' ? response : { results: [{ ok: true }] });
    },
    _loadWorkbooks: function () { this.reloaded = true; }
  });
  return { instance: instance, row: row, calls: calls, values: values };
}
(async function () {
  const version = { commit: 'a'.repeat(40), author: 'Consultant', date: '2026-10-03 UTC',
    message: 'Restore comma delimiter\nFull message', present: true, complete: true };
  let f = fixture({ head: 'b'.repeat(40), truncated: true, versions: [version] });
  f.instance.onSelectionChange();
  assert.equal(f.row.selected, true, 'unchanged items remain selectable for history');
  assert.equal(f.values['/selectedCommit'], 0);
  f.instance.onHistory();
  await tick();
  assert.equal(f.calls[0].resource, 'history');
  assert.equal(f.calls[0].params.path, f.row.path);
  const list = controls.find(function (c) { return c.settings.mode === 'SingleSelectLeft'; });
  const restore = controls.find(function (c) { return c.settings.text === 'Restore selected version'; });
  const older = controls.find(function (c) { return c.settings.text === 'Load older history'; });
  assert.equal(restore.enabled, false);
  list.select({ getParameter: function () { return list.items[0]; } });
  assert.equal(restore.enabled, true);
  restore.settings.press();
  messageBox.answer('CANCEL');
  assert.equal(f.calls.length, 1, 'cancellation performs no restore');
  restore.settings.press();
  messageBox.answer('OK');
  await tick();
  assert.equal(f.calls[1].resource, 'restore');
  assert.equal(f.calls[1].params.version, version.commit);
  assert.equal(f.calls[1].params.commit, 'b'.repeat(40), 'freshness uses current head, not historical commit');
  assert.equal(f.calls[1].params.paths, f.row.path, 'backend receives the logical workbook path');
  assert.equal(f.instance.reloaded, true);

  f = fixture({ head: 'b'.repeat(40), truncated: true, versions: [Object.assign({}, version, { complete: false })] });
  f.instance.onHistory(); await tick();
  const incompleteList = controls.find(function (c) { return c.settings.mode === 'SingleSelectLeft'; });
  const incompleteRestore = controls.find(function (c) { return c.settings.text === 'Restore selected version'; });
  incompleteList.select({ getParameter: function () { return incompleteList.items[0]; } });
  assert.equal(incompleteRestore.enabled, false, 'incomplete pairs cannot be restored');
  incompleteRestore.settings.press();
  assert.equal(f.calls.length, 1);
  const more = controls.find(function (c) { return c.settings.text === 'Load older history'; });
  more.settings.press(); await tick();
  assert.equal(f.calls[1].params.depth, 200);

  f = fixture({ head: 'b'.repeat(40), truncated: false, versions: [Object.assign({}, version, { present: false })] });
  f.instance.onHistory(); await tick();
  const deletionList = controls.find(function (c) { return c.settings.mode === 'SingleSelectLeft'; });
  deletionList.select({ getParameter: function () { return deletionList.items[0]; } });
  controls.find(function (c) { return c.settings.text === 'Restore selected version'; }).settings.press();
  assert.match(messageBox.text, /deletes this item from BPC/, 'deletion snapshots have an explicit warning');
  f = fixture({ head: 'b'.repeat(40), truncated: false, versions: [version] });
  f.row.path = 'MODEL/BPF/CONNECTION%20REVENUE.xml';
  f.row.name = 'CONNECTION REVENUE.xml';
  f.row.kind = 'BPF';
  f.instance.onHistory(); await tick();
  const bpfList = controls.find(function (c) { return c.settings.mode === 'SingleSelectLeft'; });
  bpfList.select({ getParameter: function () { return bpfList.items[0]; } });
  controls.find(function (c) { return c.settings.text === 'Restore selected version'; }).settings.press();
  assert.match(messageBox.text, /editable draft/);
  messageBox.answer('OK'); await tick();
  assert.equal(f.calls[1].params.paths, f.row.path, 'BPF history retains its encoded identity');
  assert.equal(f.calls[1].params.version, version.commit);
  assert.equal(f.calls[1].params.commit, 'b'.repeat(40));
  f = fixture({ head: 'b'.repeat(40), truncated: false, versions: [Object.assign({}, version, { present: false })] });
  f.row.path = 'MODEL/BPF/CONNECTION%20REVENUE.xml'; f.row.kind = 'BPF';
  f.instance.onHistory(); await tick();
  const bpfDeletedList = controls.find(function (c) { return c.settings.mode === 'SingleSelectLeft'; });
  bpfDeletedList.select({ getParameter: function () { return bpfDeletedList.items[0]; } });
  const bpfDeletedRestore = controls.find(function (c) { return c.settings.text === 'Restore selected version'; });
  assert.equal(bpfDeletedRestore.enabled, false, 'BPF deletion snapshots cannot delete instances');
  bpfDeletedRestore.settings.press();
  assert.equal(f.calls.length, 1);
  console.log('History UI regression checks passed');
})().catch(function (error) { console.error(error); process.exitCode = 1; });
