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
