const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
let methods;
vm.runInNewContext(fs.readFileSync('src/zbpc_git.wapa.controller_-app.controller.js', 'utf8'), {
 sap:{ui:{define:(names,factory)=>factory.apply(null,names.map(name=>name.endsWith('/Controller')?{extend:(n,m)=>{methods=m;}}:{}))}}
});
const data={};
const c=Object.assign({},methods,{_model:{getProperty:p=>data[p],setProperty:(p,v)=>{data[p]=v;}}});
for(let i=0;i<60;i++) c._recordPerformance('commit','completed',Date.now()-10,1,
 {bpcMs:1,gitMs:2,pushMs:3,totalMs:6,token:'fake-secret',url:'https://fake-secret@example.invalid',message:'private'});
const log=data['/performanceLog'];
assert.equal(log.length,50);
assert.equal(log[0].objects,1);
assert.equal(log[0].timings.gitMs,2);
assert.ok(log[0].elapsedMs>=0);
assert.ok(!JSON.stringify(log).includes('fake-secret'));
assert.ok(!JSON.stringify(log).includes('private'));
assert.match(methods._openCommitDialog.toString(), /_recordPerformance\("commit", "failed"/);
console.log('Performance event allowlist and retention checks passed');

(async function () {
  data['/environment'] = 'ENV';
  data['/loadScope'] = { kind: 'SCRIPT', model: 'MODEL' };
  c._toRow = x => x; c._applyFilter = () => {}; c._updateSelection = () => {};
  c._gitRequest = async () => ({ branch: 'main', branchFound: true, commit: 'head',
    workbooks: [{path:'MODEL/SCRIPTS/A.LGF'}], timings: {gitMs:74,bpcMs:1,compareMs:2} });
  c._loadWorkbooks(true); await new Promise(r => setImmediate(r));
  let last = data['/performanceLog'].at(-1);
  assert.equal(last.operation, 'load'); assert.equal(last.state, 'completed');
  assert.equal(last.timings.gitMs, 74); assert.equal(last.objects, 1);
  c._loadWorkbooks(false); await new Promise(r => setImmediate(r));
  assert.equal(data['/performanceLog'].at(-1).operation, 'refresh');
  c._gitRequest = async () => { throw {cancelled: true}; };
  c._loadWorkbooks(false); await new Promise(r => setImmediate(r));
  assert.equal(data['/performanceLog'].at(-1).state, 'cancelled');
  console.log('Manual load/refresh timing checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
