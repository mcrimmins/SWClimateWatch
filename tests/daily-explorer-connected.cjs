const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const model=require('../scripts/daily-explorer-archive-assets/connected-model.js');
const catalog={schema_version:1,connected_explorer:true,latest:'2026-10-02',months:[
  {month:'2025-08',water_year:2025,kind:'archive',dates:['2025-08-31'],viewer:'archive/wy2025/months/2025-08/index.html'},
  {month:'2025-09',water_year:2025,kind:'archive',dates:['2025-09-29','2025-09-30'],viewer:'archive/wy2025/months/2025-09/index.html'},
  {month:'2026-09',water_year:2026,kind:'current',dates:['2026-09-30'],viewer:'current/index.html'},
  {month:'2026-10',water_year:2027,kind:'current',dates:['2026-10-01','2026-10-02'],viewer:'current/index.html'}]};
assert.equal(model.validate(catalog),catalog);
assert.equal(model.partition(catalog,'2025-10-01'),undefined);
assert.equal(model.partition(catalog,'2026-10-01').water_year,2027);
assert.throws(()=>model.validate({...catalog,latest:'2025-09-30'}),/Latest/);
assert.throws(()=>model.validate({...catalog,months:[{...catalog.months[0],viewer:'../bad/index.html'}]}),/Invalid/);
assert.deepEqual(model.selection({region:'AZ',weatherPeriod:'30',metric:'mean',unsafe:'drop',compare:30}),{region:'AZ',weatherPeriod:'30',metric:'mean'});
assert.equal(model.height(NaN),null);assert.equal(model.height(999999),null);assert.equal(model.height(1500),1506);
class El{
  constructor(){this.value='';this.dataset={};this.hidden=true;this.disabled=true;this.style={};this.events={};this.contentWindow={};this.attrs={};}
  addEventListener(n,fn){this.events[n]=fn;}replaceChildren(...rows){this.options=rows;}setAttribute(k,v){this.attrs[k]=v;}
}
const ids=['year','month','date','previous','next','current','status','error','retry','viewport','loading','viewer'];
const elements=Object.fromEntries(ids.map(k=>[`connected-${k}`,new El()]));
const listeners={},timers=new Map();let timerId=0;
const location={href:'http://example.test/',origin:'http://example.test'};
const context={console,URL,SWCConnected:model,Option:function(text,value){this.text=text;this.value=value;},location,
  document:{getElementById:id=>elements[id]},window:{addEventListener:(n,fn)=>listeners[n]=fn},
  history:{replaceState:(_a,_b,u)=>location.href=String(u)},
  setTimeout:(fn,ms)=>{const id=++timerId;timers.set(id,{fn,ms});return id;},clearTimeout:id=>timers.delete(id),
  fetch:async()=>({ok:true,json:async()=>structuredClone(catalog)})};
vm.runInNewContext(fs.readFileSync('scripts/daily-explorer-archive-assets/connected-shell.js','utf8'),context);
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const frame=elements['connected-viewer'];
const emit=(data,origin=location.origin,source=frame.contentWindow)=>listeners.message({data,origin,source});
const pending=()=>[...timers.values()].filter(t=>t.ms===160);
const settle=()=>{for(const [id,t] of [...timers])if(t.ms===160){timers.delete(id);t.fn();}};
const message=(date,token,height=3000)=>({type:'swc:connected-month',token,date,height,ready:true,
  capabilities:{weather:true,reports:true,hazards:true},selection:{region:'AZ',variable:'tmean',weatherPeriod:'30',openWeather:'true'}});
(async()=>{
  await tick();await tick();
  assert.ok(frame.src.includes('date=2026-10-02'));
  assert.ok(!frame.src.includes('connectedMonth='),'Current conditions keeps the full retained year/season view by default');
  assert.ok(elements['connected-month'].options.some(o=>o.value==='all'));
  emit(message('2026-10-02','1'),'https://foreign.test');assert.equal(pending().length,0);
  emit(message('2026-10-02','1'),location.origin,{});assert.equal(pending().length,0);
  emit(message('2026-10-02','1'));assert.equal(frame.style.visibility,'hidden');settle();
  assert.equal(frame.style.visibility,'visible');assert.equal(frame.style.height,'3006px');
  frame.contentDocument={getElementById:id=>id==='circulation-period'?{value:'7'}:undefined};
  elements['connected-year'].value='2025';elements['connected-year'].events.change();
  assert.ok(frame.src.includes('2025-09-30'));assert.ok(frame.src.includes('region=AZ'));assert.ok(frame.src.includes('weatherPeriod=7'),'Latest control changes are captured before their asynchronous message arrives');
  frame.contentDocument=null;
  assert.equal(frame.style.height,'3006px','Previous height is retained while loading');assert.equal(frame.style.visibility,'hidden');
  const requestedArchiveSrc=frame.src;
  emit(message('2026-10-02','2'));settle();
  assert.equal(frame.src,requestedArchiveSrc,'Even a matching-token frame cannot redirect to a default date during initialization');
  assert.equal(elements['connected-date'].value,'2025-09-30');
  emit(message('2026-10-02','1'));settle();assert.equal(frame.style.visibility,'hidden','Old frame token cannot reveal old data');
  emit(message('2025-09-30','2',2000));emit(message('2025-09-30','2',2100));assert.equal(pending().length,1,'Geometry updates coalesce');settle();
  assert.equal(frame.style.height,'2106px');assert.equal(elements['connected-next'].disabled,true,'Year gap remains unavailable');
  const displayedSeptember=frame.src;
  emit(message('2025-09-29','2',2100));settle();
  assert.equal(elements['connected-date'].value,'2025-09-29');assert.equal(frame.src,displayedSeptember,'Real same-month date changes work after initialization');
  emit(message('2025-08-31','2',2100));assert.ok(frame.src.includes('2025-08-31'),'Real cross-month selections still navigate after the frame is visible');
  emit(message('2025-08-31','3',2100));settle();assert.equal(frame.style.visibility,'visible');
  elements['connected-date'].value='2025-10-01';elements['connected-date'].events.change();
  assert.equal(frame.hidden,true);assert.match(elements['connected-error'].textContent,/unavailable/);
  emit(message('2025-09-30','2'));settle();assert.equal(frame.hidden,true,'A failed date cannot be replaced by a stale frame');
  elements['connected-current'].events.click();assert.ok(frame.src.includes('date=2026-10-02'));
  assert.ok(!frame.src.includes('connectedMonth='),'Returning to current restores all available current dates');
  assert.ok(frame.src.includes('variable=tmean'),'Compatible selections survive the return to current conditions');
  console.log('PASS: current/archive routing, exact year gaps, saved selections, current return, origin/token guards and stable/coalesced loading heights.');
})().catch(e=>{console.error(e);process.exitCode=1;});
