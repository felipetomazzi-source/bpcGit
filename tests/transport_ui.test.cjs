const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let methods;
function Control(settings) {
  this.settings = settings || {};
  this.items = (this.settings.items || []).slice();
  this.visible = this.settings.visible;
}
Control.prototype.attachChange = function (callback) { this.change = callback; };
Control.prototype.setSelectedKey = function (key) { this.selectedKey = key; return this; };
Control.prototype.getSelectedKey = function () { return this.selectedKey; };
Control.prototype.insertItem = function (item, index) { this.items.splice(index, 0, item); return this; };
Control.prototype.setVisible = function (value) { this.visible = value; return this; };
Control.prototype.setText = function (value) { this.text = value; return this; };
Control.prototype.getValue = function () { return this.value || ''; };
Control.prototype.setValueState = function (state) { this.valueState = state; return this; };
Control.prototype.setValueStateText = function () { return this; };
Control.prototype.addStyleClass = function () { return this; };
Control.prototype.addItem = function (item) { this.items.push(item); return this; };
Control.prototype.setBusy = function (value) { this.busy = value; return this; };
Control.prototype.open = function () { this.opened = true; };
Control.prototype.close = function () { this.closed = true; };
const toasts = [];
const warnings = [];
vm.runInNewContext(fs.readFileSync('src/zbpc_git.wapa.controller_-app.controller.js', 'utf8'), {
  sap: { ui: { define: (names, factory) => factory.apply(null, names.map(name =>
    name.endsWith('/Controller') ? { extend: (name, m) => { methods = m; } } :
    name.endsWith('/MessageToast') ? { show: text => toasts.push(text) } :
    name.endsWith('/MessageBox') ? { warning: text => warnings.push(text) } : Control)) } },
  jQuery: { trim: s => s.trim() },
  Promise: Promise
});
const tick = () => new Promise(resolve => setImmediate(resolve));

(async function () {
  // Open requests are listed after "No transport request"; the last choice is preselected.
  const posts = [];
  const context = Object.assign({}, methods, {
    _lastTransport: 'NPLK900200',
    _request: function (resource, params, method) {
      if (resource === 'transports') {
        return Promise.resolve({ requests: [{ request: 'NPLK900200', text: 'BPC fixes' }, { request: 'NPLK900201', text: '' }] });
      }
      posts.push({ resource, params, method });
      return Promise.resolve({ request: 'NPLK900300' });
    }
  });
  const picker = context._createTransportPicker();
  await tick();
  const select = picker.control.settings.items[1];
  const input = picker.control.settings.items[2];
  assert.deepEqual(Array.from(select.items, item => item.settings.key), ['__NONE__', 'NPLK900200', 'NPLK900201', '__NEW__']);
  assert.equal(select.items[1].settings.text, 'NPLK900200 - BPC fixes');
  assert.equal(select.getSelectedKey(), 'NPLK900200');
  assert.equal(await picker.resolve(), 'NPLK900200');

  // A new request needs a description and is created once, then reused.
  select.setSelectedKey('__NEW__'); select.change();
  assert.equal(input.visible, true);
  await assert.rejects(picker.resolve(), /description/);
  assert.equal(input.valueState, 'Error');
  input.value = '  Restore Capex reports  ';
  assert.equal(await picker.resolve(), 'NPLK900300');
  assert.equal(JSON.stringify(posts), JSON.stringify([{ resource: 'transport', params: { text: 'Restore Capex reports' }, method: 'POST' }]));
  assert.equal(select.getSelectedKey(), 'NPLK900300');
  assert.equal(await picker.resolve(), 'NPLK900300');
  assert.equal(posts.length, 1);
  assert.equal(context._lastTransport, 'NPLK900300');

  // No request chosen
  const none = Object.assign({}, methods, { _request: () => Promise.resolve({ requests: [] }) })._createTransportPicker();
  await tick();
  assert.equal(await none.resolve(), '');

  // Outcome text
  assert.equal(methods._transportOutcome(undefined), '');
  assert.equal(methods._transportOutcome({ request: 'R1', count: 2, error: '', skipped: [] }),
    'Recorded 2 objects in transport request R1');
  assert.equal(methods._transportOutcome({ request: 'R1', count: 0, error: 'Released', skipped: [{ path: 'P', message: 'M' }] }),
    'Not recorded in transport request R1: Released\nNot in transport: P: M');
  // Adding objects without a restore: a request is required, the first open one is preselected.
  const required = Object.assign({}, methods, {
    _request: () => Promise.resolve({ requests: [{ request: 'NPLK900200', text: 'BPC fixes' }] })
  })._createTransportPicker(true);
  await tick();
  const requiredSelect = required.control.settings.items[1];
  assert.deepEqual(Array.from(requiredSelect.items, item => item.settings.key), ['NPLK900200', '__NEW__']);
  assert.equal(await required.resolve(), 'NPLK900200');

  const rows = [{ path: 'M/EEXCEL/R.XLSX', name: 'R.XLSX', model: 'M', folder: 'EEXCEL', inBpc: true, selected: true },
    { path: 'M/EEXCEL/OTHER.XLSX', name: 'OTHER.XLSX', inBpc: true, selected: false }];
  const requests = [];
  let dialog;
  const add = Object.assign({}, methods, {
    _model: { getProperty: key => ({ '/workbooks': rows, '/environment': 'ENV' })[key] },
    getView: () => ({ addDependent: control => { dialog = control; } }),
    _request: function (resource, params, method) {
      requests.push({ resource, params, method });
      return Promise.resolve(resource === 'transports' ? { requests: [{ request: 'NPLK900200', text: '' }] }
        : { transport: { request: params.transport, count: 1, error: '', skipped: [] } });
    }
  });
  add.onAddToTransport();
  await tick();
  assert.equal(dialog.opened, true);
  dialog.settings.beginButton.settings.press();
  await tick(); await tick();
  const record = requests.find(call => call.resource === 'transport/record');
  assert.equal(JSON.stringify(record), JSON.stringify({ resource: 'transport/record',
    params: { environment: 'ENV', transport: 'NPLK900200', paths: 'M/EEXCEL/R.XLSX' }, method: 'POST' }));
  assert.equal(dialog.closed, true);
  assert.equal(toasts.pop(), 'Recorded 1 object in transport request NPLK900200');

  // Objects that are not in BPC cannot be added.
  rows[0].inBpc = false; dialog = undefined;
  add.onAddToTransport();
  assert.equal(dialog, undefined);
  console.log('transport UI: ok');
})().catch(error => { console.error(error); process.exitCode = 1; });
