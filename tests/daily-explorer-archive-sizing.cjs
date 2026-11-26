const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const model=require('../scripts/daily-explorer-archive-assets/archive-model.js');
const catalog={schema_version:1,archive_pilot:true,archive_integration_pilot:true,latest:'2025-11-01',months:[
  {month:'2025-10',water_year:2026,path:'months/2025-10/daily-data.json',viewer:'months/2025-10/index.html',dates:['2025-10-31'],full:true},
  {month:'2025-11',water_year:2026,path:'months/2025-11/daily-data.json',viewer:'months/2025-11/index.html',dates:['2025-11-01'],full:true}]};
class El{constructor(){this.dataset={};this.events={};this.style={};this.contentWindow={};this.replacements=0;}
  addEventListener(n,f){this.events[n]=f;}replaceChildren(...o){this.options=o;this.replacements++;}}
const ids=['year','month','date','previous','next','latest','state','error','viewer'];
const els=Object.fromEntries(ids.map(id=>[`archive-${id}`,new El()])),events={},timers=new Map();let timer=0,urlWrites=0;
const location={href:'http://example.test/?date=2025-10-31',origin:'http://example.test'};
const context={URL,SWCArchive:model,location,document:{getElementById:id=>els[id],createElement:()=>({})},
  window:{addEventListener:(n,f)=>events[n]=f},history:{replaceState:()=>urlWrites++},
  setTimeout:f=>{timers.set(++timer,f);return timer;},clearTimeout:i=>timers.delete(i),
  fetch:async()=>({ok:true,json:async()=>catalog})};
vm.runInNewContext(fs.readFileSync('scripts/daily-explorer-archive-assets/archive-shell.js','utf8'),context);
const frame=els['archive-viewer'],settle=()=>{const f=[...timers.values()];timers.clear();f.forEach(fn=>fn());};
const emit=(date,height,token='1')=>events.message({origin:location.origin,source:frame.contentWindow,
  data:{type:'swc:archive-month',date,height,token,selection:{compare:'30'},capabilities:{weather:true,reports:true,hazards:true}}});
(async()=>{
  await new Promise(r=>setImmediate(r));await new Promise(r=>setImmediate(r));
  emit('2025-11-01',9999);assert.equal(timers.size,0,'Initializing frame cannot redirect to its context-end day');
  emit('2025-10-31',2300);emit('2025-10-31',2400);assert.equal(timers.size,1);assert.equal(frame.style.height,'1400px');settle();
  assert.equal(frame.style.height,'2406px');
  const replacements=els['archive-month'].replacements,writes=urlWrites;
  emit('2025-10-31',2401);settle();assert.equal(frame.style.height,'2406px','Tiny size changes are ignored');
  assert.equal(els['archive-month'].replacements,replacements);assert.equal(urlWrites,writes,'Height-only messages do not rewrite controls or history');
  els['archive-next'].events.click();assert.equal(frame.style.height,'2406px','Keep previous frame height while a new month loads');
  emit('2025-10-31',10000,'1');assert.equal(timers.size,0,'Stale frame size cannot change new selection');
  emit('2025-11-01',2500,'2');settle();assert.equal(frame.style.height,'2506px');
  console.log('PASS: settled archive sizes, stable controls, retained loading height and date/token guards.');
})().catch(e=>{console.error(e);process.exitCode=1;});
