const assert=require('node:assert/strict');
const M=require('../scripts/streamflow-assets/streamflow-model.js');
assert.equal(M.valid(null),false);assert.equal(M.valid(0),true);assert.equal(M.valid('3'),false);
assert.equal(M.format(null),'Unavailable');assert.equal(M.format(0),'0');
const segments=M.segments([{cfs:0},{cfs:2},{cfs:null},{cfs:1},{cfs:null}]);
assert.deepEqual(segments,[[{i:0,value:0},{i:1,value:2}],[{i:3,value:1}]]);
const gauges=[{id:'1',name:'Zero',state:'AZ',river:'Verde',latest_cfs:0},{id:'2',name:'Missing',state:'NM',river:'Pecos',latest_cfs:null},{id:'3',name:'Flow',state:'AZ',river:'Gila',latest_cfs:20}];
assert.deepEqual(M.filtered(gauges,'all','','flow').map(g=>g.id),['3','1','2']);
assert.deepEqual(M.filtered(gauges,'AZ','verde','name').map(g=>g.id),['1']);
assert.equal(M.day('2026-11-26'),'Nov 26, 2026');
const normal={history_supported:true,p10:1,p25:2,p50:3,p75:4,p90:5};
assert.deepEqual([0,1,2,4,5,6].map(cfs=>M.categoryFor({...normal,cfs})),['Below 10th','10th–25th','25th–75th','25th–75th','75th–90th','Above 90th']);
assert.equal(M.categoryFor({...normal,cfs:0,p10:0,p25:0,p50:0}),'Tied thresholds');
assert.equal(M.categoryFor({...normal,cfs:0,history_supported:false}),'History unavailable');
assert.equal(M.categoryFor({...normal,cfs:null}),'Unavailable');
assert.equal(M.historySegments([normal,{...normal,history_supported:false},normal],'p25','p75').length,2);
const fs=require('node:fs'),path=require('node:path');
const payload=path.resolve(__dirname,'../data/diagnostics/streamflow-pilot/streamflow-data.json');
if(fs.existsSync(payload)){
  const p=JSON.parse(fs.readFileSync(payload,'utf8'));
  if(p.historical_statistics)for(const g of p.gauges){
    assert.ok(Object.hasOwn(M.categoryColors,g.historical_category),'Recognized serialized category: '+g.historical_category);
    const h=JSON.parse(fs.readFileSync(path.join(path.dirname(payload),g.hydrograph),'utf8'));
    const r=h.rows.find(r=>r.date===g.latest_date);
    if(r)assert.equal(M.categoryFor(r),g.historical_category,'R and browser classifications agree');
    for(const row of h.rows)if(row.history_supported){assert.ok(row.sample_count>=30);assert.ok([row.p10,row.p25,row.p50,row.p75,row.p90].every(M.valid));}
  }
}
console.log('PASS: zero/missing distinctions, gap segments, filtering, flow sorting and date formatting.');
