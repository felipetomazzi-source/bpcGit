const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let methods;
const controls = [];
function Control(settings) { this.settings = settings || {}; this.items = []; controls.push(this); }
['setBusy', 'setVisible', 'setText'].forEach(name => { Control.prototype[name] = function (v) { this[name] = v; }; });
Control.prototype.addItem = function (item) { this.items.push(item); };
Control.prototype.open = function () {};
Control.prototype.destroy = function () { this.destroyed = true; };
Control.prototype.close = function () { this.settings.afterClose(); };
Control.prototype.addStyleClass = function () { return this; };
vm.runInNewContext(fs.readFileSync('src/zbpc_git.wapa.controller_-app.controller.js', 'utf8'), {
  sap: { ui: { define: (names, factory) => factory.apply(null, names.map(name => name.endsWith('/Controller') ?
    { extend: (name, m) => { methods = m; } } : Control)) } }, jQuery: { extend: Object.assign }
});
function rows(a, b, ga = true, ba = true) { return JSON.parse(JSON.stringify(methods._diffLines(a, b, ga, ba))); }
assert.deepEqual(rows('A\nDELIMITER=,\nZ', 'A\nDELIMITER=;\nZ'), [
  { type: 'same', text: 'A' }, { type: 'remove', text: 'DELIMITER=,' },
  { type: 'add', text: 'DELIMITER=;' }, { type: 'same', text: 'Z' }
]);
assert.deepEqual(rows('A\r\nB', 'A\nB').map(r => r.type), ['same', 'same']);
assert.deepEqual(rows('A', 'A\n').map(r => r.type), ['same', 'add'], 'final newline is visible');
assert.deepEqual(rows('', 'A', false).map(r => r.type), ['add']);
assert.deepEqual(rows('A', '', true, false).map(r => r.type), ['remove']);
assert.deepEqual(rows('', '').map(r => r.type), []);
// Reconstruct both sides, including duplicates and insertion/deletion shifts.
for (const [a, b] of [['A\nB\nA\nC', 'B\nA\nD\nC'], ['A\nB', 'X\nA\nB'], ['A\nB', 'A']]) {
  const result = rows(a, b);
  assert.equal(result.filter(r => r.type !== 'add').map(r => r.text).join('\n'), a);
  assert.equal(result.filter(r => r.type !== 'remove').map(r => r.text).join('\n'), b);
}
const largeA = Array.from({ length: 1100 }, (_, i) => 'old' + i).join('\n');
const largeB = Array.from({ length: 1100 }, (_, i) => 'new' + i).join('\n');
assert.equal(rows(largeA, largeB).length, 2200, 'bounded fallback preserves all changed lines');
const malicious = { gitText: '<script>alert(1)</script>', bpcText: '<img onerror="bad">', inGit: true, inBpc: true };
const rendered = methods._renderDiff(malicious);
assert.ok(!rendered.includes('<script>') && !rendered.includes('<img'));
assert.ok(rendered.includes('&lt;script&gt;') && rendered.includes('&quot;bad&quot;'));
assert.ok(methods._renderDiff({ gitText: largeA, bpcText: largeB, inGit: true, inBpc: true }).includes('first 2,000 rows'));
assert.ok(methods._renderDiff({ gitText: 'a'.repeat(200001), bpcText: '' }).includes('too large'));
for (const kind of ['SCRIPT', 'TRANSFORMATION', 'CONVERSION', 'PACKAGE', 'LINK']) { assert.equal(methods._canDiff({ kind }), true); }
assert.equal(methods._canDiff({ kind: 'WORKBOOK' }), false);
(async () => {
  const data = { '/workbooks': [{ kind: 'TRANSFORMATION', path: 'M/IMPORT.XLS', name: 'IMPORT.XLS', selected: true }], '/environment': 'ENV' };
  let resolve;
  const calls = [];
  const instance = Object.assign({}, methods, {
    _model: { getProperty: key => data[key], setProperty: (key, value) => { data[key] = value; } },
    getView: () => ({ addDependent: () => {} }),
    _gitRequest: (resource, params) => { calls.push({ resource, params }); return new Promise(r => { resolve = r; }); }
  });
  instance._updateSelection(); assert.equal(data['/selectedDiff'], true);
  instance.onDiff();
  assert.equal(calls[0].resource, 'diff'); assert.equal(calls[0].params.path, 'M/IMPORT.XLS');
  assert.equal(calls[0].params.environment, 'ENV');
  const dialog = controls.find(c => c.settings.title === 'Diff - IMPORT.XLS');
  dialog.close(); resolve({ head: 'a'.repeat(40), parts: [] });
  await new Promise(r => setImmediate(r));
  assert.equal(dialog.destroyed, true, 'late response cannot populate a closed dialog');
  data['/workbooks'].push({ selected: true, kind: 'SCRIPT' });
  instance._updateSelection(); assert.equal(data['/selectedDiff'], false);
  instance.onDiff(); assert.equal(calls.length, 1, 'multiple selection cannot issue a diff');
  console.log('Diff UI regression checks passed');
})();
