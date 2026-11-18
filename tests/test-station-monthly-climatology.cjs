const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const context=vm.createContext({window:{}});
vm.runInContext(fs.readFileSync('scripts/station-monthly-climatology-assets/monthly-climatology.js','utf8'),context);
assert.equal(fs.readFileSync('scripts/station-explorer-assets/monthly-climatology.js','utf8'),
  fs.readFileSync('scripts/station-monthly-climatology-assets/monthly-climatology.js','utf8'));
assert.equal(fs.readFileSync('scripts/station-explorer-assets/monthly-climatology.css','utf8'),
  fs.readFileSync('scripts/station-monthly-climatology-assets/monthly-climatology.css','utf8'));
const integrated=fs.readFileSync('scripts/station-explorer-assets/explorer.js','utf8');
assert(integrated.includes('SWCStationMonthlyClimatology.section(detail.monthly_climatology)'));
assert(integrated.includes('SWCStationMonthlyClimatology.mount'));
assert(!integrated.includes('station-explorer-prototype/seasonal/'));
const ui=context.window.SWCStationMonthlyClimatology;
const reference={minimum_years:20,method:'Test <method>',monthly:Array.from({length:12},(_,i)=>({month:i+1,
  precip_inches:i===4?null:0,high_f:i===4?null:80,low_f:i===4?null:50,precipitation_years:i===4?19:30,temperature_years:i===4?19:30}))};
assert.equal(ui.months(reference,'water')[0].month,10);assert.equal(ui.months(reference,'water')[11].month,9);
assert.equal(ui.months(reference)[0].month,1);
const html=ui.section(reference);
assert(html.includes('Typical climate at this station'));assert(!/<details[^>]* open/.test(html));
assert(html.includes('Not official NOAA normals'));assert(html.includes('Test &lt;method&gt;'));
assert(html.includes('0.00 in.'));assert(html.includes('May · Median precipitation Unavailable'));
assert(html.includes('data-month-readout="precipitation"'));assert(html.includes('data-month-readout="temperature"'));
for(const title of html.matchAll(/<title>(.*?)<\/title>/g)){
  assert(title[1].length<130);assert(!title[1].includes('eligible years'));
}
const path=ui.chart(ui.months(reference),true);
assert(!path.includes('NaN'));assert(/M[^\"]+M/.test(path));
const varied={...reference,monthly:reference.monthly.map(r=>({...r,
  precip_p25:r.month===5?null:.5,precip_p75:r.month===5?null:2,
  high_p25:r.month===5?null:75,high_p75:r.month===5?null:85,
  low_p25:r.month===5?null:45,low_p75:r.month===5?null:55,
  precip_median:r.month===5?null:1,precip_min:r.month===5?null:0,precip_max:r.month===5?null:8,
  high_min:r.month===5?null:65,high_max:r.month===5?null:95,
  low_min:r.month===5?null:30,low_max:r.month===5?null:65,
  precip_min_years:'1991,1992',precip_max_years:'2020',high_max_years:'2010'}))};
assert.equal((ui.chart(ui.months(varied),true).match(/monthly-variability-band/g)||[]).length,4);
assert.equal((ui.chart(ui.months(varied),false).match(/monthly-range-whisker/g)||[]).length,11);
assert.equal((ui.chart(ui.months(varied),false).match(/monthly-precipitation-box/g)||[]).length,11);
assert.equal((ui.chart(ui.months(varied),false).match(/monthly-precipitation-median/g)||[]).length,11);
assert.equal((ui.chart(ui.months(varied),true).match(/monthly-extreme-envelope/g)||[]).length,4);
assert(ui.panel(varied).includes('8.00 in. (2020)'));
assert(ui.panel(varied).includes('1991, 1992'));
assert(ui.panel(varied).includes('not individual daily temperature records'));
const zeros={...varied,monthly:varied.monthly.map(r=>({...r,precip_median:0,precip_min:0,precip_max:0,precip_p25:0,precip_p75:0}))};
assert.equal((ui.chart(ui.months(zeros),false).match(/monthly-precipitation-median/g)||[]).length,12);
assert(!ui.chart(ui.months(zeros),false).includes('NaN'));
assert(ui.panel(varied).includes('middle 50%'));
assert(ui.panel(varied).includes('75.0 °F–85.0 °F'));
assert(!ui.chart(ui.months(varied,'water'),true).includes('NaN'));
const handlers={},content={innerHTML:''};
const readouts={precipitation:{innerHTML:''},temperature:{innerHTML:''}};
const hits=Array.from({length:24},(_,i)=>({dataset:{month:String(i%12+1)},tabIndex:-1,
  classList:{toggle(name,value){this[name]=value;}}}));
const figures=[0,1].map(i=>({querySelectorAll:()=>hits.slice(i*12,i*12+12)}));
hits.forEach((h,i)=>{
  h.closest=selector=>selector==='.monthly-chart-day'?h:figures[Math.floor(i/12)];
  h.focus=()=>handlers.focusin({target:h});
});
const container={addEventListener:(name,fn)=>handlers[name]=fn,contains:h=>hits.includes(h),
  querySelectorAll:()=>hits,
  querySelector:selector=>selector==='.monthly-climatology-content'?content:
    readouts[selector.includes('precipitation')?'precipitation':'temperature']};
const full={...varied,baseline:'Full available record (1900–2025)',period_id:'record',monthly:varied.monthly.map(r=>({...r,
  precip_inches:8,precip_median:7,precip_min:0,precip_max:10,precip_p25:5,precip_p75:9,
  high_f:90,high_median:90,high_min:75,high_max:100,high_p25:85,high_p75:95,
  low_f:60,low_median:60,low_min:40,low_max:70,low_p25:55,low_p75:65,
  precipitation_years:100,temperature_years:100,precip_first_year:1900,precip_last_year:2025}))};
const combined={...varied,baseline:'1991–2020',full_record:full};
assert(ui.section(combined).includes('value="reference" selected'));
assert(!ui.section(combined).includes('value="record" selected'));
ui.mount(container,combined);
handlers.pointerover({target:hits[2]});
assert(readouts.precipitation.innerHTML.includes('Mar · 1991–2020'));
assert(readouts.temperature.innerHTML.includes('Mar · 1991–2020'));
assert.equal(hits[2].tabIndex,0);assert.equal(hits[14].tabIndex,0);assert.equal(hits[0].tabIndex,-1);
handlers.keydown({target:hits[14],key:'ArrowRight',preventDefault(){}});
assert(readouts.precipitation.innerHTML.includes('Apr · 1991–2020'));
handlers.change({target:{matches:()=>true,value:'water'}});
assert(content.innerHTML.includes('value="water" selected'));
assert(content.innerHTML.indexOf('Oct ·')<content.innerHTML.indexOf('Jan ·'));
assert(readouts.temperature.innerHTML.includes('Apr · 1991–2020'));
handlers.click({target:hits[4]});
assert(readouts.precipitation.innerHTML.includes('Unavailable'));
assert(readouts.temperature.innerHTML.includes('19'));
handlers.change({target:{matches:s=>s==='[data-climatology-period]',value:'record'}});
assert(content.innerHTML.includes('value="record" selected'));
assert(content.innerHTML.includes('value="water" selected'));
assert(readouts.precipitation.innerHTML.includes('May · Full available record (1900–2025)'));
assert(readouts.precipitation.innerHTML.includes('7.00 in.'));
assert(readouts.precipitation.innerHTML.includes('1900–2025'));
assert(readouts.temperature.innerHTML.includes('90.0 °F'));
handlers.change({target:{matches:s=>s==='[data-climatology-period]',value:'reference'}});
assert(readouts.temperature.innerHTML.includes('May · 1991–2020'));
assert(readouts.temperature.innerHTML.includes('19'));
assert(ui.readout(varied.monthly[0],false).includes('2020'));
assert(!ui.readout({...varied.monthly[0],precip_max_years:'<img onerror="bad">'},false).includes('<img'));
assert.equal(reference.monthly[0].month,1);
console.log('PASS: month ordering, null gaps versus zero, coverage labels, collapsed panel and selector updates.');
