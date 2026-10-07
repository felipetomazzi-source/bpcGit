const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let methods;
vm.runInNewContext(fs.readFileSync('src/zbpc_git.wapa.controller_-app.controller.js', 'utf8'), {
  sap: { ui: { define: (names, factory) => factory.apply(null, names.map(name =>
    name.endsWith('/Controller') ? { extend: (name, m) => { methods = m; } } : { show() {} })) } }
});

function controller(rows) {
  const values = {
    '/workbooks': rows, '/workbooksView': [],
    '/filter': { search: '', model: 'ALL', type: 'ALL', location: 'ALL', status: 'ALL', hideBackups: false }
  };
  const context = Object.assign({}, methods, {
    _model: {
      getProperty: key => key.indexOf('/filter/') === 0 ? values['/filter'][key.slice(8)] : values[key],
      setProperty: (key, value) => { values[key] = value; },
      refresh: () => { values.refreshed = (values.refreshed || 0) + 1; }
    },
    _canDiff: () => false
  });
  return { context, values };
}
function item(object, selected) {
  return { getBindingContext: () => ({ getObject: () => object }), getSelected: () => selected };
}
function event(params) { return { getParameter: name => params[name] }; }
const row = (kind, name) => ({ kind, name, path: kind + '/' + name, status: 'NEW_BPC', statusText: 'New in BPC',
  selected: false, inBpc: true, committable: true });

// Several object types: one collapsed group row each, in display order.
const rows = [row('SCRIPT', 'A.LGF'), row('SCRIPT', 'B.LGF'), row('WORKBOOK', 'R.XLSX')];
const { context, values } = controller(rows);
context._applyFilter();
let view = values['/workbooksView'];
assert.deepEqual(Array.from(view, r => r.name), ['EPM workbooks (1)', 'Logic scripts (2)']);
assert.ok(view.every(r => r.isGroup && !r.expanded && !r.selected));
assert.equal(values['/workbooksTitle'], 'Files (3)');

// Selecting a collapsed group selects its objects.
const scripts = view[1];
context.onSelectionChange(event({ listItems: [item(scripts, true)] }));
assert.deepEqual(rows.map(r => r.selected), [true, true, false]);
assert.equal(values['/selectedCount'], 2);
view = values['/workbooksView'];
assert.equal(view[1].selected, true);
assert.equal(view[1].folder, '2 selected');

// Expanding shows its objects; clearing one object updates the group in place.
context.onGroupPress(event({ listItem: item(view[1]) }));
view = values['/workbooksView'];
assert.deepEqual(Array.from(view, r => r.name), ['EPM workbooks (1)', 'Logic scripts (2)', 'A.LGF', 'B.LGF']);
rows[0].selected = false;
const before = values['/workbooksView'];
context.onSelectionChange(event({ listItems: [item(rows[0], false)] }));
assert.equal(values['/workbooksView'], before, 'object changes keep the list');
assert.equal(before[1].selected, false);
assert.equal(before[1].folder, '1 selected');
assert.equal(values['/selectedCount'], 1);

// Select all includes collapsed groups; clearing a group clears its objects.
context.onSelectionChange(event({ selectAll: true, listItems: [] }));
assert.ok(rows.every(r => r.selected));
context.onSelectionChange(event({ listItems: [item(values['/workbooksView'][0], false)] }));
assert.deepEqual(rows.map(r => r.selected), [true, true, false]);

// A search shows matches expanded; a single type is expanded too.
values['/filter'].search = 'R.X';
context._applyFilter();
assert.deepEqual(Array.from(values['/workbooksView'], r => r.name), ['EPM workbooks (1)', 'R.XLSX']);
const single = controller([row('PACKAGE', 'P.xml')]);
single.context._applyFilter();
assert.deepEqual(Array.from(single.values['/workbooksView'], r => r.name), ['Data Manager packages (1)', 'P.xml']);

// "Select BPC changes" works on the listed objects, not the group rows.
values['/filter'].search = '';
context._applyFilter();
rows.forEach(r => { r.selected = false; r.bpcChange = r.kind === 'SCRIPT'; });
context._selectWhere('bpcChange', 'none');
assert.deepEqual(rows.map(r => r.selected), [true, true, false]);
assert.equal(values['/workbooksView'].find(r => r.name === 'Logic scripts (2)').selected, true);
console.log('group UI: ok');
