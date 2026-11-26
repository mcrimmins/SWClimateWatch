const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const messages=[],queued=[];
const error={hidden:false,textContent:'Could not load the local explorer: Wrong month context catalog'};
const sandbox={URL,location:{href:'http://example.test/months/2025-10/index.html?archiveToken=7',origin:'http://example.test'},
  parent:{postMessage:(message,origin)=>messages.push({message,origin})},window:{},
  document:{getElementById:id=>id==='error'?error:null,querySelector:()=>({}),addEventListener:()=>{}},
  requestAnimationFrame:f=>queued.push(f),MutationObserver:class{observe(){}},ResizeObserver:class{observe(){}}};
vm.runInNewContext(fs.readFileSync('scripts/daily-explorer-archive-assets/archive-month-bridge.js','utf8'),sandbox);
queued.shift()();
assert.equal(messages.length,1);
assert.equal(messages[0].message.error,error.textContent);
assert.equal(messages[0].message.token,'7');
assert.equal(messages[0].message.type,'swc:archive-month');
assert.equal(messages[0].origin,'http://example.test');
console.log('PASS: month errors reach the archive parent before date initialization.');
