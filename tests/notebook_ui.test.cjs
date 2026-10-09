const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let methods;
const controls = [];
function Control(settings) { this.settings = settings || {}; this.items = []; controls.push(this); }
Control.prototype.addItem = function (item) { this.items.push(item); };
Control.prototype.addStyleClass = function () { return this; };
Control.prototype.open = function () {};
Control.prototype.destroy = function () {};
vm.runInNewContext(fs.readFileSync('src/zbpc_git.wapa.controller_-app.controller.js', 'utf8'), {
  sap: { ui: { define: (names, factory) => factory.apply(null, names.map(name =>
    name.endsWith('/Controller') ? { extend: (name, m) => { methods = m; } } : Control)) } },
  jQuery: { extend: Object.assign }, Promise
});
const row = methods._toRow({ path: 'NOTEBOOKS/revenue/notebook.json', kind: 'NOTEBOOK',
  notebookTitle: 'Revenue calculation', notebookRevision: 3, status: 'MODIFIED_GIT', inBpc: true });
assert.equal(row.name, 'Revenue calculation');
assert.equal(row.typeText, 'Notebook');
assert.equal(row.restorable, true);
assert.equal(methods._canDiff(row), true);
assert.equal(methods._toRow({ path: row.path, kind: 'NOTEBOOK', status: 'DELETED_GIT' }).restorable, false);
const values = { '/workbooks': [Object.assign(row, { selected: true })], '/overview': { commit: 'a'.repeat(40) } };
const controller = Object.assign({}, methods, {
  _model: { getProperty: key => values[key], setProperty: (key, value) => { values[key] = value; } },
  _createTransportPicker: () => { throw new Error('Notebook must never discover/create transport requests'); },
  getView: () => ({ addDependent() {} })
});
controller._updateSelection();
assert.equal(values['/selectedTransport'], 0);
controller.onAddToTransport();
assert.equal(controls.length, 0, 'Notebook transport action refuses before opening a dialog');
controller._openRestoreDialog([row]);
const dialog = controls.find(control => control.settings.title && control.settings.title.startsWith('Restore'));
assert.ok(dialog, 'Notebook restore dialog opens without transport lookup');
assert.ok(controls.some(control => /Transport recording is not supported/.test(control.settings.text || '')));
console.log('Notebook display, diff, deletion and transport isolation checks passed');
