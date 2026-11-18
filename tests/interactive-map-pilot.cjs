// Offline numerical/controller checks; built assets required, no basemap/network.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {cellAt,decode,category,styles,styleFor,resolveSelection,shiftDate,pointStats,companions} = require('../scripts/interactive-map-assets/pilot.js');
const folder = process.argv[2] || 'data/diagnostics/interactive-map-pilot';
const manifest=JSON.parse(fs.readFileSync(path.join(folder,'manifest.json')));
assert.deepEqual(Object.keys(manifest.basemaps),['street','terrain','satellite']);
for(const b of Object.values(manifest.basemaps)){
  assert.ok(b.url.startsWith('https://'));
  for(const token of ['{z}','{x}','{y}'])assert.ok(b.url.includes(token));
  assert.ok(b.attribution.includes('href='));
}
assert.deepEqual(Object.keys(manifest.reference_overlays),['roads','places']);
for(const b of Object.values(manifest.reference_overlays)){
  assert.ok(b.url.startsWith('https://'));
  for(const token of ['{z}','{x}','{y}'])assert.ok(b.url.includes(token));
  assert.ok(b.attribution.includes('href='));
}
let cells=0;
assert.equal(manifest.schema,5);
// Context stays identical when only the monthly color metric changes.
const point={mean_temperature_f:[75.3],departure_f:[1.2],percentile:[77.7],warm_rank:[30.5],sample_years:[132],record:[2]};
const monthlyPoint=pointStats({frequency:'monthly',variable:'temperature',metric:'ranking'},point,0);
for(const metric of ['mean','departure'])assert.deepEqual(pointStats({frequency:'monthly',variable:'temperature',metric},point,0),monthlyPoint);
assert.deepEqual(monthlyPoint.rows,[['Mean temperature','75.3 °F'],['Departure from normal','+1.2 °F'],['Historical percentile','77.7'],['Warm rank / years','30.5 / 132']]);
assert.equal(monthlyPoint.note,'Tied record warm');
assert.match(monthlyPoint.reference,/1991–2020.*1895/);
const missingPoint=pointStats({frequency:'monthly',variable:'temperature'},Object.fromEntries(Object.keys(point).map(k=>[k,[NaN]])),0);
assert.ok(missingPoint.rows.every(r=>r[1]==='Unavailable'));assert.equal(missingPoint.note,'');
const currentPoint=pointStats({frequency:'current',variable:'temperature',metric:'ranking'},{value:[77.7]},0,{mean:75.3,departure:1.2});
assert.deepEqual(currentPoint.rows,monthlyPoint.rows.slice(0,3));
assert.match(currentPoint.reference,/Rank and sample size are not available/);
const dailyPoint=pointStats({frequency:'daily',variable:'temperature',metric:'high_departure'},{observed:[90],normal:[88],departure:[2]},0);
assert.deepEqual(dailyPoint.rows,[['High temperature','90.0 °F'],['Reference temperature','88.0 °F'],['Departure from normal','+2.0 °F']]);
const currentSelection=resolveSelection(manifest,{frequency:'current',variable:'temperature',metric:'mean',period:'water_year'});
const currentLayer=manifest.layers[currentSelection.id];
assert.equal(companions(manifest,currentSelection,currentLayer).length,2);
assert.equal(companions(manifest,currentSelection,{...currentLayer,date:'1900-01-01'}).length,0);
assert.equal(companions(manifest,currentSelection,{...currentLayer,start_date:'1900-01-01'}).length,0);
const spiSelection=resolveSelection(manifest,{frequency:'monthly',variable:'precipitation',metric:'spi',duration:12});
assert.equal(companions(manifest,spiSelection,manifest.layers[spiSelection.id])[0].id,'precipitation-12month');
assert.equal(companions(manifest,spiSelection,{period:'Different window'}).length,0);
const rainPoint={total_precipitation_inches:[3],departure_inches:[-.5],percentile:[40],wet_rank:[80],sample_years:[132],record:[0]};
const spiPoint=pointStats(spiSelection,{spi:[-.2],sample_years:[126],spi_status:[0]},0,rainPoint);
assert.deepEqual(spiPoint.rows.slice(-2),[['SPI-12','-0.20'],['SPI calibration years','126']]);
assert.deepEqual(spiPoint.rows[3],['Wet rank / years','80 / 132']);
assert.deepEqual(spiPoint.rows[1],['Departure from normal','-0.50 in.']);
assert.equal(Object.values(manifest.layers).filter(x=>!x.frequency).length,12);
let currentCombinations=0;
for(const [variable,v] of Object.entries(manifest.current.variables))for(const [measure,m] of Object.entries(v.measures))for(const metric of Object.keys(m.metrics))for(const period of Object.keys(m.periods[metric])){
  const s=resolveSelection(manifest,{frequency:'current',variable,measure,metric,period});
  assert.equal(s.variable,variable);assert.equal(s.metric,metric);assert.equal(s.period,period);
  assert.equal(s.measure,measure);assert.ok(styleFor(s));currentCombinations++;
}
assert.equal(currentCombinations,39);
assert.equal(resolveSelection(manifest,{frequency:'current',variable:'precipitation',metric:'ranking',period:'1day'}).period,'7day');
assert.equal(resolveSelection(manifest,{frequency:'current',variable:'precipitation',metric:'percent_normal',period:'7day'}).period,'30day');
assert.equal(resolveSelection(manifest,{frequency:'current',variable:'temperature',metric:'mean',period:'30day'}).period,'water_year');
assert.equal(resolveSelection(manifest,{frequency:'current',variable:'precipitation',metric:'ranking',period:'water_year'}).period,'water_year');
const absentCurrent={...manifest,layers:{...manifest.layers}};
delete absentCurrent.layers['current-pcpn_total_07day'];
assert.equal(resolveSelection(absentCurrent,{frequency:'current',variable:'precipitation',metric:'total',period:'7day'}).available,false);
let combinations=0;
for(const [variable,definition] of Object.entries(manifest.variables))for(const metric of Object.keys(definition.metrics))for(const duration of manifest.durations){
  const s=resolveSelection(manifest,{variable,metric,duration});
  assert.equal(s.variable,variable);assert.equal(s.metric,metric);assert.equal(s.duration,duration);
  assert.equal(manifest.layers[s.id].duration,duration);
  assert.ok(styles[`${variable}-${metric}`]);combinations++;
}
assert.equal(combinations,28);
assert.deepEqual(resolveSelection(manifest,{variable:'temperature',metric:'spi',duration:6}),{frequency:'monthly',variable:'temperature',metric:'mean',duration:6,id:'temperature-06month',available:true});
assert.equal(resolveSelection(manifest,{variable:'precipitation',metric:'mean',duration:12}).metric,'total');
for(const variable of ['temperature','precipitation'])for(const metric of ['ranking','departure']){
  const s=resolveSelection(manifest,{variable,metric,duration:3});assert.equal(s.metric,metric);assert.equal(s.duration,3);
}
assert.equal(resolveSelection(manifest,{variable:'bad',metric:'bad',duration:99}).id,'precipitation-01month');
let dailyCombinations=0;
for(let date=manifest.daily.first_date;date<=manifest.daily.latest_date;date=shiftDate(date,1)){
  for(const [variable,v] of Object.entries(manifest.daily.variables))for(const metric of Object.keys(v.metrics)){
    const s=resolveSelection(manifest,{frequency:'daily',variable,metric,date});
    assert.equal(s.date,date);assert.equal(s.variable,variable);assert.equal(s.metric,metric);
    assert.equal(typeof s.available,'boolean');dailyCombinations++;
  }
}
assert.equal(dailyCombinations,manifest.daily.retained_days*7);
assert.equal(shiftDate('2026-10-31',1),'2026-11-01');
assert.equal(shiftDate('2024-02-28',1),'2024-02-29');
assert.equal(shiftDate('2024-02-29',1),'2024-03-01');
assert.equal(shiftDate('2026-01-01',-1),'2025-12-31');
for(const date of ['', '2026-02-29','bad'])assert.throws(()=>shiftDate(date,1),/valid daily date/);
assert.throws(()=>resolveSelection(manifest,{frequency:'daily',date:shiftDate(manifest.daily.latest_date,1)}),/between/);
const gap={...manifest,layers:{...manifest.layers}};
delete gap.layers[`daily-pcpn-${manifest.daily.latest_date}`];
const absent=resolveSelection(gap,{frequency:'daily',variable:'precipitation',date:manifest.daily.latest_date});
assert.equal(absent.available,false);assert.equal(absent.date,manifest.daily.latest_date);
const highId=`daily-maxt-${manifest.daily.latest_date}`;
if(manifest.layers[highId]){
  gap.layers[highId]={...manifest.layers[highId],normal_available:false};
  assert.equal(resolveSelection(gap,{frequency:'daily',variable:'temperature',metric:'high',date:manifest.daily.latest_date}).available,true);
  assert.equal(resolveSelection(gap,{frequency:'daily',variable:'temperature',metric:'high_departure',date:manifest.daily.latest_date}).available,false);
}
assert.equal(resolveSelection(manifest,{frequency:'daily',variable:'temperature',metric:'ranking'}).metric,'mean');
for(const [id,layer] of Object.entries(manifest.layers)){
  const bytes=fs.readFileSync(path.join(folder,layer.file));
  const data=decode(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),layer);
  const g=layer.grid,n=g.rows*g.cols;
  const daily=layer.frequency==='daily';
  const dailyMetric={pcpn:'precipitation-total',maxt:'temperature-high',mint:'temperature-low',tmean:'temperature-mean'}[layer.family];
  const current=layer.frequency==='current',p=current?manifest.current.products[layer.product]:null;
  const relevant=current?[styleFor({frequency: 'current',...p})]:daily?[`daily-${dailyMetric}`,...(layer.family==='pcpn'?[]:[`daily-${dailyMetric}_departure`])]:layer.family==='spi'?['precipitation-spi']:Object.keys(styles).filter(k=>!styles[k].daily&&!styles[k].current&&k.startsWith(layer.family+'-')&&!k.endsWith('-spi'));
  for(let i=0;i<n;i++){
    const r=Math.floor(i/g.cols),c=i%g.cols;
    assert.equal(cellAt(g,g.north-(r+.5)*g.dy,g.west+(c+.5)*g.dx),i);
    for(const key of relevant){
      const style=typeof key==='string'?styles[key]:key,k=category(style,data,i);
      assert.ok(k>=-1&&k<style.colors.length);
      if(style.kind==='binned'&&!Number.isFinite(data[style.field][i]))assert.equal(k,-1);
      if(style.kind==='rank'){
      assert.ok(!Number.isFinite(data.percentile[i])||(data.percentile[i]>=0&&data.percentile[i]<=100));
      if(data.record[i]===1||data.record[i]===2)assert.equal(k,8);
      if(data.record[i]===3||data.record[i]===4)assert.equal(k,0);
      if(!Number.isFinite(data.percentile[i]))assert.equal(k,-1);
      }
    }
    if(layer.derived_departure){
      const expected=data.observed[i]-data.normal[i];
      assert.ok(Object.is(data.departure[i],expected)||data.departure[i]===expected);
    }
    cells++;
  }
  assert.equal(cellAt(g,g.north,g.west),0);
  assert.equal(cellAt(g,g.south,g.west),-1);
  assert.equal(cellAt(g,g.north,g.east),-1);
  assert.equal(cellAt(g,g.north+.001,g.west),-1);
  assert.equal(cellAt(g,NaN,g.west),-1);
  assert.throws(()=>decode(new ArrayBuffer(3),layer),/length/);
  assert.ok(layer.bytes<1024*1024,'Additional layer exceeds 1 MiB target');
}
const temp={percentile:new Float32Array([0,2,10,33,67,90,98,100,99,1,NaN]),record:new Float32Array([0,0,0,0,0,0,0,0,2,4,NaN])};
for(const key of ['temperature-ranking','precipitation-ranking'])assert.deepEqual(Array.from(temp.percentile,(_,i)=>category(styles[key],temp,i)),[1,1,2,3,4,5,6,7,8,0,-1]);
const spi={spi:Float32Array.from([-2,-1.5,-1,0,1,1.5,2,NaN,NaN]),spi_status:Float32Array.from([0,0,0,0,0,0,0,1,NaN])};
assert.deepEqual(Array.from(spi.spi,(_,i)=>category(styles['precipitation-spi'],spi,i)),[0,1,2,3,4,5,6,7,-1]);
for(const style of Object.values(styles)){
  assert.equal(style.colors.length,style.labels.length);
  if(style.kind==='binned'){
    assert.equal(style.bounds.length,style.colors.length);
    for(let j=0;j<style.bounds.length;j++)if(Number.isFinite(style.bounds[j])){
      const d={[style.field]:Float64Array.of(style.bounds[j],style.bounds[j]+1e-6,NaN)};
      assert.equal(category(style,d,0),j);assert.equal(category(style,d,1),j+1<style.bounds.length?j+1:-1);assert.equal(category(style,d,2),-1);
    }
  }
}
console.log(`PASS: ${currentCombinations} current, ${combinations} monthly and ${dailyCombinations} daily combinations; valid-period filtering, calendar steps, missing inputs, ${cells} cells, exact values/masks, bin boundaries and payload sizes.`);

const drySelection=resolveSelection(manifest,{frequency:'current',variable:'precipitation',measure:'dry_spell',metric:'ranking',period:'water_year'});
assert.equal(drySelection.period,'current');assert.equal(drySelection.product,'pcpn_current_dry_spell_percentile');
assert.equal(companions(manifest,drySelection,manifest.layers[drySelection.id]).length,1);
const dryPoint=pointStats(drySelection,{value:[95]},0,{length:45});
assert.deepEqual(dryPoint.rows,[['Current dry spell','45 days'],['Historical percentile','95.0']]);
assert.match(dryPoint.reference,/Higher percentiles mean longer/);
assert.notEqual(styleFor(drySelection),styles['current-precipitation-ranking']);
const changeSelection=resolveSelection(manifest,{frequency:'current',variable:'precipitation',measure:'rank_change',metric:'ranking',period:'7day'});
assert.equal(changeSelection.metric,'change');assert.equal(changeSelection.period,'30day');
assert.equal(companions(manifest,changeSelection,manifest.layers[changeSelection.id]).length,0);
assert.deepEqual(pointStats(changeSelection,{value:[-25]},0).rows,[['14-day change in 30-day percentile','-25.0 points']]);
const highSelection=resolveSelection(manifest,{frequency:'current',variable:'temperature',measure:'high',metric:'ranking',period:'water_year'});
assert.equal(highSelection.metric,'departure');assert.equal(highSelection.period,'30day');
assert.equal(companions(manifest,highSelection,manifest.layers[highSelection.id]).length,0);
assert.equal(resolveSelection(manifest,{frequency:'current',variable:'temperature',measure:'dry_spell'}).measure,'mean');
console.log('PASS: measure filtering, dry-spell companions, percentile direction and rank-change units.');

const freezeSelection=resolveSelection(manifest,{frequency:'current',variable:'temperature',measure:'freeze_nights',metric:'anomaly',period:'30day'});
assert.deepEqual(pointStats(freezeSelection,{value:[2.25]},0,{count:0}).rows,[['Freeze nights','0 nights'],['Departure from normal count','+2.3 nights']]);
assert.equal(companions(manifest,freezeSelection,manifest.layers[freezeSelection.id]).length,1);
const wetSelection=resolveSelection(manifest,{frequency:'current',variable:'precipitation',measure:'wet_intensity',metric:'ranking',period:'90day'});
assert.deepEqual(pointStats(wetSelection,{value:[70]},0,{intensity:NaN}).rows,[['Mean precipitation per wet day','Unavailable'],['Historical percentile','70.0']]);
assert.equal(companions(manifest,wetSelection,manifest.layers[wetSelection.id]).length,1);
const wySelection=resolveSelection(manifest,{frequency:'current',variable:'precipitation',measure:'wy_extremes',metric:'ranking',period:'water_year'});
assert.equal(companions(manifest,wySelection,manifest.layers[wySelection.id]).length,2);
assert.deepEqual(pointStats(wySelection,{value:[90]},0,{maximum:1.5,share:75}).rows,[['Maximum 3-day precipitation','1.50 in.'],['Share from maximum 3-day period','75.0 %'],['Historical percentile','90.0']]);
assert.equal(pointStats(wySelection,{value:[NaN]},0,{maximum:0,share:NaN}).rows[1][1],'Unavailable');
assert.notEqual(styleFor(wetSelection),styles['current-precipitation-ranking']);
console.log('PASS: freeze count/anomaly, rainfall character and water-year extreme readouts; masked shares remain unavailable.');
