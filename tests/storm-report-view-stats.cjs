const assert=require('node:assert/strict');
const {summarize,comparable}=require('../scripts/storm-reports-assets/report-view-stats.js');
const row=(id,type,magnitude,unit,extra={})=>({id,type,magnitude,unit,mapped:true,lat:33,lon:-110,qualifier:'Measured',...extra});
const rows=[row('r1','RAIN','4.29','Inch'),row('r2','RAIN','108.966','mm'),row('h','HAIL','2','INCH'),
  row('w','TSTM WND GST','60','KT',{qualifier:'Estimated'}),row('w2','NON-TSTM WND GST','65','MPH'),
  row('damage','TSTM WND DMG','200','MPH'),row('unknown','RAIN','999','unknown'),row('blank','RAIN','','Inch'),
  row('zero','RAIN','0','Inch'),row('no-position','RAIN','100','Inch',{mapped:false}),row('outside','HAIL','10','INCH',{lon:-100})];
const stats=summarize(rows,r=>r.lon<-105);
assert.equal(stats.total,11);assert.equal(stats.inView,9);assert.equal(stats.outside,1);assert.equal(stats.unmapped,1);
assert.equal(stats.types.reduce((sum,[,n])=>sum+n,0),stats.inView);
assert.ok(Math.abs(stats.extremes.rain.value-4.29)<1e-10);
assert.deepEqual(stats.extremes.rain.reports.map(r=>r.id),['r1','r2']);
assert.equal(stats.extremes.hail.value,2);
assert.equal(stats.extremes.wind.reports[0].id,'w');
assert.ok(Math.abs(stats.extremes.wind.value-69.04676688141)<1e-8);
assert.equal(stats.extremes.wind.reports[0].qualifier,'Estimated');
assert.equal(comparable(rows[5],'wind'),null); // Damage estimates in text/type are not observed gusts.
assert.equal(comparable(row('bad','HAIL','-1','INCH'),'hail'),null);
assert.equal(comparable(row('missing','RAIN','','Inch'),'rain'),null);
assert.equal(comparable(row('unknown','RAIN','500','unknown'),'rain'),null);
assert.equal(comparable(row('z','RAIN','0','Inch'),'rain'),0);
assert.equal(summarize([],()=>true).extremes.rain.value,null);
assert.equal(summarize(rows,()=>false).inView,0);
assert.equal(summarize(rows,()=>false).extremes.hail.value,null);
console.log('PASS: viewport counts, unmapped/empty reports, rainfall/hail/wind units, gust screening, maxima and ties.');
