const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const M=require('../scripts/streamflow-assets/streamflow-explorer-model.js');
const rows=Array.from({length:10},(_,i)=>({date:M.shift('2026-11-01',i),cfs:i,reported:true,approval:'Provisional',history_supported:true,p10:1,p25:2,p50:3,p75:4,p90:5,sample_count:40}));
assert.deepEqual(M.windowRows(rows,'2026-11-07',7).map(r=>r.date),rows.slice(0,7).map(r=>r.date));
assert.equal(M.windowRows(rows,'2026-11-07',1).length,1);
assert.equal(M.summary({id:'x'},rows,'2026-11-05').latest_cfs,4);
assert.equal(M.summary({id:'x'},rows,'2026-11-05').latest_date,'2026-11-05');
assert.equal(M.summary({id:'x'},rows,'2026-11-07').mean_7day_cfs,3);
assert.equal(M.summary({id:'x'},rows,'2026-11-05').mean_7day_cfs,null);
const gap=rows.map(r=>({...r}));gap[4].cfs=null;
assert.equal(M.summary({},gap,'2026-11-07').mean_7day_cfs,null);
assert.equal(M.summary({},gap,'2026-11-05').latest_cfs,null);
assert.equal(M.summary({},rows,'2026-10-31').latest_cfs,null);
assert.equal(M.summary({},rows,'2026-11-01').latest_cfs,0);
for(const date of ['2026-10-31','2026-11-11','2026-02-30','bad'])assert.equal(M.selection({date,days:7,region:'AZNM'},'2026-11-01','2026-11-10'),false);
assert.equal(M.selection({date:'2026-11-05',days:7,region:'AZNM'},'2026-11-01','2026-11-10'),true);
assert.equal(M.selection({date:'2026-11-05',days:8,region:'AZNM'},'2026-11-01','2026-11-10'),false);
const csv=M.csv(M.windowRows(rows,'2026-11-07',7));assert.ok(csv.includes('"2026-11-01","0"'));assert.ok(!csv.includes('2026-11-08'));
assert.ok(M.csv([{note:'quoted "text"',cfs:null}]).includes('"quoted ""text""",""'));
const release=path.resolve(__dirname,'../data/diagnostics/daily-explorer-streamflow/streamflow/streamflow-data.json');
if(fs.existsSync(release)){
  const p=JSON.parse(fs.readFileSync(release,'utf8'));assert.equal(p.gauges.length,32);
  for(const g of p.gauges){const d=JSON.parse(fs.readFileSync(path.join(path.dirname(release),g.hydrograph),'utf8')).rows;
    assert.equal(d.length,90);for(const end of [p.start,M.shift(p.start,30),p.cutoff]){
      const s=M.summary(g,d,end);assert.ok(!s.latest_date||s.latest_date<=end);for(const n of [1,7,30,90])assert.ok(M.windowRows(d,end,n).every(r=>r.date<=end));
    }
  }
}
console.log('PASS: selected-date summaries, no future leakage, complete means, missing/zero values, boundary guards and displayed-window CSVs.');
