// Run the real adapter with small DOM controls; no HTTP or browser dependency.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function element(value='',values=[]){const handlers={};return {value,options:values.map(value=>({value})),open:false,
  addEventListener(type,fn){(handlers[type]??=[]).push(fn);},dispatchEvent(e){for(const fn of handlers[e.type]||[])fn(e);},
  append(){},setAttribute(){},getAttribute(){return null;},scrollIntoView(){}};}
const controls={
  'streamflow-panel':element(),'streamflow-frame':element(),
  'streamflow-view-window':element('7',['1','7','30','90']),
  'streamflow-view-region':element('AZNM',['AZNM','AZ','NM']),
  date:element('2026-11-25'),compare:element('single',['single','7','30']),region:element('AZNM',['AZNM','AZ','NM'])
};
controls['streamflow-frame'].contentWindow={postMessage(){}};
const docEvents={},windowEvents={},messages=[];
const document={getElementById:id=>controls[id]||null,
  querySelector:()=>({src:'https://example.test/climate/watch-staging/daily-explorer/streamflow-trial/explorer-streamflow.swc-123.js'}),
  createElement:()=>element(),
  addEventListener(type,fn){(docEvents[type]??=[]).push(fn);},
  dispatchEvent(e){for(const fn of docEvents[e.type]||[])fn(e);}
};
const window={addEventListener(type,fn){(windowEvents[type]??=[]).push(fn);}};
const parent={postMessage:m=>messages.push(m)};
class Event{constructor(type,options={}){this.type=type;Object.assign(this,options);}}
const daily=()=>document.dispatchEvent(new Event('swc:daily-selection',{detail:{date:controls.date.value,region:controls.region.value}}));
document.addEventListener('swc:request-selection',daily);
for(const id of ['region','compare'])controls[id].addEventListener('change',daily);
vm.runInNewContext(fs.readFileSync(require.resolve('../scripts/streamflow-assets/explorer-streamflow.js'),'utf8'),
  {document,window,parent,URL,location:{origin:'https://example.test',href:'https://example.test/current/index.html?archiveToken=1'},Event,CustomEvent:Event,requestAnimationFrame:fn=>fn()});
assert.equal(controls['streamflow-view-window'].value,'7');
assert.equal(controls.compare.value,'single','Default flow window must not change the single-day map');
assert.equal(controls['streamflow-panel'].open,false);
controls['streamflow-view-region'].value='AZ';controls['streamflow-view-region'].dispatchEvent(new Event('change'));
assert.equal(controls.region.value,'AZ');assert.equal(controls.compare.value,'single','Region changes must preserve the map window');
controls['streamflow-view-window'].value='30';controls['streamflow-view-window'].dispatchEvent(new Event('change'));
assert.equal(controls.compare.value,'30');
controls.compare.value='single';controls.compare.dispatchEvent(new Event('change'));
assert.equal(controls['streamflow-view-window'].value,'7');assert.equal(controls.compare.value,'single');
controls['streamflow-view-window'].value='1';controls['streamflow-view-window'].dispatchEvent(new Event('change'));
assert.equal(controls['streamflow-view-window'].value,'1','An explicit one-day flow selection remains available');
controls['streamflow-view-window'].value='90';controls['streamflow-view-window'].dispatchEvent(new Event('change'));
assert.equal(controls.compare.value,'single','The 90-day flow option must not change Map view');
console.log('PASS: seven-day flow default, unchanged single-day map, region-only changes, linked 30-day selection and explicit one-/90-day flow options.');
