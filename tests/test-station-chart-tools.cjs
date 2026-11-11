const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const context=vm.createContext({window:{}});
vm.runInContext(fs.readFileSync('scripts/station-explorer-assets/station-chart-tools.js','utf8'),context);
const tools=context.window.SWCStationChartTools;
const root={hits:[],querySelectorAll(){return this.hits;}};
function hit(date,type){const readout={};return {dataset:{[type]:date},tabIndex:-1,
  classList:{toggle(name,value){this[name]=value;}},closest(){return {querySelector(){return readout;}};}};}
root.hits=[hit('2026-10-01','precipitationDate'),hit('2026-10-02','precipitationDate'),
  hit('2026-10-01','temperatureDate'),hit('2026-10-02','temperatureDate')];
let rendered=[];
tools.selectDay(root,root.hits[1],h=>rendered.push(h));
assert.equal(rendered.length,2);assert.equal(root.hits[1].tabIndex,0);assert.equal(root.hits[3].tabIndex,0);
assert.equal(root.hits[0].tabIndex,-1);assert.equal(root.hits[2].classList['chart-selected'],false);
rendered=[];tools.selectDay(root,root.hits[2],h=>rendered.push(h));
assert.equal(rendered.length,2);assert.equal(root.hits[0].tabIndex,0);assert.equal(root.hits[3].tabIndex,-1);
const station={uid:123,sid:'TEST 6',name:'=bad,"name"',state:'AZ',role:'fixed',period:'7day',period_start:'2026-10-01',as_of:'2026-10-02'};
const detail={uid:123,as_of:'2026-10-02',daily:[
  {date:'2026-09-30',pcpn:99},
  {date:'2026-10-01',pcpn:0,pcpn_status:'TRACE',maxt:80,mint:-5,normal_maxt:79,record_high_years:'1991,2000'},
  {date:'2026-10-02',pcpn:null,pcpn_status:'MISSING',maxt:null,mint:40},
  {date:'2026-10-03',pcpn:99}]};
const csv=tools.dailyCsv(station,detail);
assert(csv.startsWith('\uFEFF'));assert.equal(csv.trim().split('\r\n').length,3);
assert(csv.includes('"\'=bad,""name"""'));assert(csv.includes('"TRACE"'));assert(csv.includes('"MISSING"'));
assert(csv.includes(',-5,'));assert(csv.includes('"1991,2000"'));assert(!csv.includes('2026-09-30'));assert(!csv.includes('2026-10-03'));
assert(!csv.includes('null'));assert(csv.includes('earlier_record_precipitation_inches'));
assert.throws(()=>tools.dailyCsv({...station,uid:456},detail),/does not match/);
assert.throws(()=>tools.dailyCsv({...station,as_of:'2026-10-03'},detail),/does not match/);
assert.equal(tools.dailyCsv({...station,period_start:'2026-10-02'},detail).trim().split('\r\n').length,2);
const source=fs.readFileSync('scripts/station-explorer-assets/explorer.js','utf8');
assert(source.includes('SWCStationChartTools.selectDay(detailContentEl,hit'));
assert(source.includes('SWCStationChartTools.download(exportSelection.station,exportSelection.detail)'));
assert(source.includes('exportSelection.station.period===periodEl.value'));
assert(source.includes('exportSelection = null;'));
// Exercise the page's actual hover, day-button and keyboard handlers.
const listeners={},readouts=[{},{}],figures=[0,1].map(i=>({
  querySelector:()=>readouts[i],querySelectorAll:()=>root.hits.slice(i*2,i*2+2)}));
root.contains=()=>true;root.addEventListener=(name,handler)=>{listeners[name]=handler;};
root.hits.forEach((h,i)=>{
  h.closest=selector=>selector==='.chart-day'?h:selector==='figure'?figures[Math.floor(i/2)]:null;
  h.focus=()=>listeners.focusin({target:h});
});
Object.assign(context,{detailContentEl:root,selectedUid:'123',exportSelection:null,periodEl:{value:'7day'}});
context.window.SWCStationTemperatureNormals={renderReadout(h,r){r.date=h.dataset.temperatureDate||h.dataset.precipitationDate;return true;}};
vm.runInContext(source.slice(source.indexOf('  function showChartDay('),source.indexOf('  document.getElementById("detail-close")')),context);
listeners.pointerover({target:root.hits[0]});
assert.equal(readouts[0].date,'2026-10-01');assert.equal(readouts[1].date,'2026-10-01');
const next={dataset:{chartStep:'1'},closest:s=>s==='[data-chart-step]'?next:s==='figure'?figures[1]:null};
listeners.click({target:next});
assert.equal(readouts[0].date,'2026-10-02');assert.equal(readouts[1].date,'2026-10-02');
listeners.keydown({target:root.hits[1],key:'Home',preventDefault(){}});
assert.equal(readouts[0].date,'2026-10-01');assert.equal(readouts[1].date,'2026-10-01');
console.log('PASS: linked dates in both directions, selected-period CSV, missing/trace/negative values, quoting and stale-selection guards.');
