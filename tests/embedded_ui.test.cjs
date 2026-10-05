const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let methods;
const requests = [];
vm.runInNewContext(fs.readFileSync('src/zbpc_git.wapa.controller_-app.controller.js', 'utf8'), {
  Promise, Error, encodeURIComponent,
  sap: { ui: { define(names, factory) {
    factory.apply(null, names.map(name => name.endsWith('/Controller') ? { extend(name, value) { methods = value; } } : {}));
  } } },
  jQuery: { sap: { getUriParameters() { return { get() { return '001'; } }; } },
    ajax(options) { const xhr = { abort() { this.aborted = true; options.error({ status: 0 }); } }; requests.push({ options, xhr }); return xhr; } }
});
(async function () {
  const controller = Object.assign({}, methods, { _requests: [], _environmentGeneration: 1 });
  let oldResponse = false;
  controller._request('config', { environment: 'A' }).then(() => { oldResponse = true; });
  controller._environmentGeneration += 2; // A -> B -> A, same name but different generation.
  requests[0].options.success({ configured: true });
  await Promise.resolve();
  assert.equal(oldResponse, false, 'A->B->A must discard old A response');
  const response = controller._request('config', { environment: 'A' });
  requests[1].options.success({ configured: true });
  assert.equal((await response).configured, true);
  assert.equal(requests[1].options.url, '/sap/bc/zbpc_git/config?sap-client=001', 'API remains independent of host URL');
  let lateResponse = false;
  controller._request('ping').then(() => { lateResponse = true; });
  let detached = false;
  controller.getOwnerComponent = () => ({ detachEvent() { detached = true; } });
  controller.onExit();
  requests[2].options.success({});
  await Promise.resolve();
  assert.equal(detached, true);
  assert.equal(requests[2].xhr.aborted, true, 'Destroy aborts pending client requests');
  assert.equal(lateResponse, false, 'Destroyed controller ignores late callbacks');
  console.log('Embedded request lifecycle checks passed');
})();
