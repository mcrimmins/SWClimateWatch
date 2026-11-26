const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('scripts/daily-explorer-archive-assets/archive-month-bridge.js','utf8');
for(const mode of ['single','7','30']){
  const els={},frames=[],messages=[];let renders=0;
  for(const [id,value,values]of [['year','2026',['2026']],['metric','mean',['mean']],['compare','single',['single','7','30']],
    ['circulation-compare','single',['single','7','30']],['region','AZNM',['AZNM']],['variable','pcpn',['pcpn']],
    ['view','departure',['departure']],['circulation-period','1',['1','7','30']],['storm-timing','prism',['prism']],['storm-window','1',['1','7','30']]])
    els[id]={value,options:values.map(value=>({value})),dispatchEvent(){}};
  els.date={value:''};els.error={hidden:true};els['hazard-frame']={};
  const c={URL,Event:class{},parent:{postMessage:m=>messages.push(m)},window:{},
    location:{href:`http://example.test/?date=2026-01-31&compare=${mode}&archiveToken=1`,origin:'http://example.test'},
    byDate:new Map([['2026-01-31',{}],['2026-02-03',{}]]),selectedDate:'2026-02-03',circulationEnabled:true,
    document:{getElementById:id=>els[id],querySelector:()=>({getBoundingClientRect:()=>({height:1500})}),addEventListener(){}},
    changeMapView:()=>{c.selectedDate='2026-02-03';},
    render:()=>{renders++;els.date.value=c.selectedDate;},selectDate:date=>{c.selectedDate=date;c.render();},
    requestAnimationFrame:f=>frames.push(f),MutationObserver:class{observe(){}},ResizeObserver:class{observe(){}}};
  vm.runInNewContext(source,c);c.render();frames.shift()();
  assert.equal(messages[0].date,'2026-01-31','Initialization does not wait for a date field that render itself must fill');
  assert.equal(renders,1,'Restore in one full render');assert.equal(els.compare.value,mode);
  c.changeMapView();assert.equal(c.selectedDate,'2026-01-31','Period controls preserve the requested date');
}
console.log('PASS: archive cold start, one-pass restoration and date stability across all map views.');
