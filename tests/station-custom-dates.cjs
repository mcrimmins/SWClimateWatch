'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const M=require('../scripts/station-custom-dates-assets/model.js');
assert.equal(M.day('2020-03-01')-M.day('2020-02-28'),2);
assert.throws(()=>M.day('2020-02-30'));assert.throws(()=>M.day('2020-13-01'));
const chunk=M.decode({schema:1,uid:1,year:2020,start:'2020-02-28',end:'2020-03-01',n:3,
  pcpn:[0,null,2],pcpn_status:[2,0,1],maxt:[70,null,80],maxt_status:[1,3,1],mint:[40,null,50],mint_status:[1,3,1]},1);
const rows=M.select([chunk],'2020-02-28','2020-03-01'),s=M.summarize(rows);
assert.equal(s.days,3);assert.equal(s.p.value,2);assert.equal(s.p.valid,2);assert.equal(s.p.trace,1);
assert.equal(s.t.mean,60);assert.equal(s.t.paired,2);assert.equal(s.t.flagged,1);
assert.equal(s.p.complete,false);assert.equal(M.bins(rows,2).values.length,2);
assert.throws(()=>M.select([chunk],'2020-02-28','2020-03-02'));
assert.throws(()=>M.select([chunk,chunk],'2020-02-28','2020-03-01'));
assert.throws(()=>M.select([chunk],'2020-03-01','2020-02-28'));
assert.throws(()=>M.decode({...chunk,uid:2},1));
const empty=M.decode({schema:1,uid:1,year:2020,start:'2020-01-01',end:'2020-01-01',n:1,
  pcpn:null,pcpn_status:0,maxt:null,maxt_status:0,mint:null,mint_status:0},1);
assert.equal(M.summarize(M.select([empty],'2020-01-01','2020-01-01')).p.value,null);
assert.match(M.csv(rows,{uid:1,sid:'id',name:'=UNSAFE'}),/"'=UNSAFE"/);
const root=process.argv[2];
if(root){
  const fixtures=JSON.parse(fs.readFileSync(path.join(root,'checks/fixtures.json'),'utf8'));
  for(const f of fixtures){
    const chunks=(Array.isArray(f.files)?f.files:[f.files]).map(file=>M.decode(JSON.parse(fs.readFileSync(path.join(root,file),'utf8')),f.uid));
    const result=M.summarize(M.select(chunks,f.start,f.end));
    assert.equal(result.days,f.expected.days);assert.equal(result.p.valid,f.expected.precipitation_valid);
    assert.equal(result.p.flagged,f.expected.precipitation_flagged);assert.equal(result.p.trace,f.expected.precipitation_trace);
    assert.equal(result.t.paired,f.expected.paired_days);
    for(const [a,b] of [[result.p.value,f.expected.precipitation],[result.t.mean,f.expected.mean_temperature]])
      if(b==null)assert.equal(a,null);else assert.ok(Math.abs(a-b)<1e-8,`${f.uid} ${f.start}: ${a} != ${b}`);
    assert.ok(M.bins(M.select(chunks,f.start,f.end)).values.length<=600);
  }
  console.log(`PASS: browser model matches R for ${fixtures.length} real station/range cases.`);
}
console.log('PASS: leap day, missing/flagged/trace values, singleton chunks, date guards, coverage, CSV safety and display bounds.');
