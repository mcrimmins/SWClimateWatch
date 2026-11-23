// Execute the shipped report controller against fixtures: no external requests.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
function element(tag='div') {
  return {tag,children:[],value:'',textContent:'',dataset:{},style:{setProperty(){}},open:true,
    get outerHTML(){return this.textContent;},
    classList:{toggle(){},add(){}},listeners:{},append(...x){for(const child of x)child.parent=this;this.children.push(...x);},
    querySelector(selector){return this.children.find(x=>selector==='.storm-day-summary'?x.className==='storm-day-summary':x.tag===selector)||null;},
    remove(){if(this.parent)this.parent.children=this.parent.children.filter(x=>x!==this);},
    replaceChildren(...x){this.children=x;if(tag==='select')this.value=x[0]?.value||'';},
    attributes:{},setAttribute(k,v){this.attributes[k]=v;},closest(){return {offsetTop:0,scrollTop:0};},offsetTop:0,
    addEventListener(k,fn){this.listeners[k]=fn;}};
}
const html=fs.readFileSync('scripts/storm-reports-assets/storm-reports-panel.html','utf8');
const controls=Object.fromEntries([...html.matchAll(/<(\w+)[^>]*\bid="([^"]+)"/g)].map(([,tag,id])=>[id,element(tag)]));
controls.date={min:'2026-09-01',max:'2026-09-05'};
controls['storm-type'].value='all';controls['storm-window'].value='1';
controls['storm-timing'].value='utc'; // Legacy-calendar regression suite first.
assert.match(html,/value="prism" selected/); // Browser default is map-aligned.
controls['storm-clear'].disabled=true;
controls.region={value:'AZNM'};
const timelineButtons=['2026-09-01','2026-09-02','2026-09-04'].map(date=>Object.assign(element('button'),{dataset:{reportDate:date},title:'Climate metric'}));
controls.timeline=Object.assign(element(),{querySelectorAll:()=>timelineButtons});
for(const id of ['storm-timeline-note','storm-timeline-detail','storm-timeline-legend'])controls[id]=element();
const report=(id,date='2026-09-01',state='AZ')=>({id,date,valid:`${date}T${state==='AZ'?'11:59:59':'12:00:00'}Z`,state,type:state==='AZ'?'RAIN':'FLASH FLOOD',magnitude:state==='AZ'?'4.29':'',unit:'INCH',qualifier:'Measured',city:'Test',county:'Test',source:'Public',wfo:'TWC',product_id:'202609011300-KTWC-NWUS55-LSRTWC',remark:'<script>unsafe()</script>',mapped:true,lat:32.2,lon:-110.9});
const days=['2026-09-01','2026-09-02','2026-09-03'].map((date,i)=>({date,status:i===1?'EMPTY':'READY',reports:i===1?0:2,path:`reports/${date}.json`}));
const manifest={schema_version:1,fetched_utc:'2026-11-22T00:00:00Z',start:'2026-09-01',end_exclusive:'2026-09-04',days};
const summary=(date,total,complete=true)=>({date,complete,regions:{AZNM:{total,types:total?{RAIN:1,'FLASH FLOOD':total-1}:{}},AZ:{total:total?1:0,types:total?{RAIN:1}:{}},NM:{total:Math.max(0,total-1),types:total>1?{'FLASH FLOOD':total-1}:{}}}});
manifest.timeline={utc:[summary('2026-09-01',2),summary('2026-09-02',0)],prism:[summary('2026-09-01',1,false),summary('2026-09-02',1)]};
const listeners={},requests=[];let failDay=false,releaseFirst=null,holdFirst=false;
const markerInstances=[],panCalls=[],mapEvents={};let containsPoint=()=>true;
const fakeMap={setView(){return this;},panTo(p){panCalls.push(p);},invalidateSize(){},fitBounds(){},
  on(k,fn){mapEvents[k]=fn;return this;},getBounds(){return {contains:p=>containsPoint(p)};}};
const leaflet={map:()=>fakeMap,tileLayer:()=>({addTo(){}}),layerGroup:()=>({addTo(){return this;},clearLayers(){markerInstances.length=0;}}),
  divIcon:x=>x,marker:(p,options)=>{const e=element(),m={position:p,options,events:{},getElement:()=>e,
    on(k,fn){this.events[k]=fn;return this;},addTo(){markerInstances.push(this);return this;}};return m;}};
const context=vm.createContext({console,Date,Map,Set,Promise,URLSearchParams,
  L:leaflet,
  StormReportStats:require('../scripts/storm-reports-assets/report-view-stats.js'),
  Option:function(text,value){return Object.assign(element('option'),{textContent:text,value});},
  CustomEvent:class{constructor(type,args={}){this.type=type;this.detail=args.detail;}},
  document:{getElementById:id=>controls[id],createElement:element,
    addEventListener:(k,fn)=>{listeners[k]=fn;},dispatchEvent:e=>listeners[e.type]?.(e)},
  fetch:async url=>{
    requests.push(url);if(url==='storm-reports-manifest.json')return {ok:true,json:async()=>manifest};
    if(url==='reports/2026-09-03.json'&&failDay)return {ok:false,status:503};
    if(url==='reports/2026-09-01.json'&&holdFirst)await new Promise(resolve=>{releaseFirst=resolve;});
    const date=url.slice(8,18);return {ok:true,json:async()=>({schema_version:1,date,
      reports:date==='2026-09-02'?[]:[report('a'+date,date),report('b'+date,date,'NM')]})};
  }});
vm.runInContext(fs.readFileSync('scripts/storm-reports-assets/storm-reports.js','utf8'),context);
const flush=async()=>{for(let i=0;i<5;i++)await new Promise(setImmediate);};
const select=async(date,region='AZNM')=>{controls.region.value=region;listeners['swc:daily-selection']({detail:{date,region}});await flush();};
const change=async(id,value)=>{controls[id].value=value;await controls[id].listeners.change();await flush();};
(async()=>{
  holdFirst=true;await select('2026-09-01');assert.ok(releaseFirst);
  await select('2026-09-02');releaseFirst();await flush();
  assert.match(controls['storm-status'].textContent,/0 reports/); // Old response cannot replace new date.
  assert.match(controls['storm-window-caption'].textContent,/Sep 2, 2026, 00:00 UTC/);
  await select('2026-09-01','AZ');assert.match(controls['storm-status'].textContent,/1 reports/);
  assert.equal(timelineButtons[0].querySelector('.storm-day-summary').children[0].textContent,'1');
  assert.equal(timelineButtons[1].querySelector('.storm-day-summary').children[0].textContent,'0');
  assert.equal(timelineButtons[2].querySelector('.storm-day-summary').children[0].textContent,'?');
  timelineButtons[0].onfocus();assert.match(controls['storm-timeline-detail'].textContent,/RAIN: 1/);
  assert.equal(controls['storm-rows'].children.length,1);
  assert.equal(controls['storm-view-count'].textContent,'1 report in view');
  assert.match(controls['storm-view-extremes'].children[0].children[1].textContent,/4.29 in/);
  containsPoint=()=>false;mapEvents.moveend();assert.equal(controls['storm-view-count'].textContent,'0 reports in view');
  assert.match(controls['storm-view-context'].textContent,/1 outside map/);
  containsPoint=()=>true;mapEvents.moveend();
  assert.match(markerInstances[0].options.icon.className,/rain-amount/);
  assert.equal(markerInstances[0].options.icon.html,'4+');
  assert.equal(markerInstances[0].options.icon.iconSize.join(','),'26,18');
  assert.match(markerInstances[0].getElement().attributes['aria-label'],/4.29 INCH/);
  assert.equal(controls['storm-clear'].disabled,true);
  markerInstances[0].events.mouseover();
  assert.equal(controls['storm-clear'].disabled,true); // Hover never selects.
  assert.equal(controls['storm-rows'].children[0].listeners.mouseenter,undefined);
  assert.equal(controls['storm-rows'].children[0].children[1].children[0].listeners.focus,undefined);
  controls['storm-rows'].children[0].listeners.click();
  assert.equal(controls['storm-detail'].children[0].children[2].textContent,'<script>unsafe()</script>');
  assert.equal(panCalls.length,1);
  const chosen=controls['storm-detail'].children[0];markerInstances[0].events.mouseover();markerInstances[0].events.mouseout();
  assert.equal(controls['storm-detail'].children[0],chosen); // Hover leaves full details pinned.
  assert.equal(markerInstances[0].options.title,undefined); // No competing browser tooltip.
  controls['storm-clear'].listeners.click();assert.equal(controls['storm-clear'].disabled,true);
  controls['storm-view-types'].children[0].listeners.click();
  assert.equal(controls['storm-type'].value,'RAIN');
  assert.equal(controls['storm-view-reset-types'].disabled,false);
  controls['storm-search'].value='Test';
  controls['storm-view-reset-types'].listeners.click();
  assert.equal(controls['storm-type'].value,'all');
  assert.equal(controls['storm-view-reset-types'].disabled,true);
  assert.equal(controls['storm-search'].value,'Test'); // Type reset retains other filters.
  assert.equal(controls['storm-timing'].value,'utc');assert.equal(controls['storm-window'].value,'1');
  controls['storm-search'].value='';
  controls['storm-view-extremes'].children[0].children[1].listeners.click();
  assert.equal(controls['storm-clear'].disabled,false); // Extreme selects the same pinned report.
  controls['storm-clear'].listeners.click();
  await change('storm-type','SNOW');assert.match(controls['storm-page-status'].textContent,/0 matching/);
  await select('2026-09-02');assert.equal(controls['storm-type'].value,'SNOW'); // No silent filter reset.
  await change('storm-type','all');await change('storm-window','7');
  assert.match(controls['storm-status'].textContent,/PARTIAL.*Aug 27, 2026, 00:00 UTC/);
  failDay=true;await change('storm-window','1');await select('2026-09-03');
  assert.match(controls['storm-status'].textContent,/0 reports.*UNAVAILABLE/);
  assert.equal(controls['storm-view-count'].textContent,'Report data unavailable');
  failDay=false;await select('2026-09-04');await select('2026-09-03');
  assert.match(controls['storm-status'].textContent,/2 reports.*Complete/); // Failed cache entry retries.
  assert.equal(markerInstances.length,1); // Exact coincident reports share a numbered marker.
  assert.ok(controls['storm-legend'].children.some(x=>x.textContent.includes('Rainfall')));
  assert.ok(controls['storm-legend'].children.some(x=>x.textContent.includes('Flash flood')));
  assert.doesNotMatch(markerInstances[0].options.icon.className,/rain-amount/); // Shared-location count is not an amount.
  markerInstances[0].events.click();assert.equal(controls['storm-location-choice'].hidden,false);
  assert.equal(controls['storm-clear'].disabled,true); // Opening the chooser is not a selection.
  const choices=controls['storm-location-choice'].children[2].children;
  assert.equal(choices.length,2);choices[1].children[0].listeners.click();
  assert.equal(controls['storm-location-choice'].hidden,true); // One details panel after choosing.
  assert.equal(controls['storm-clear'].disabled,false);
  assert.equal(controls['storm-rows'].children[1].dataset.id,'b2026-09-03');
  await change('storm-type','all');assert.equal(controls['storm-clear'].disabled,false); // Kept while still visible.
  await change('storm-window','30');assert.match(controls['storm-status'].textContent,/PARTIAL/);
  await change('storm-window','1');await select('2026-09-05');assert.match(controls['storm-status'].textContent,/UNAVAILABLE/);
  await change('storm-timing','prism');await select('2026-09-02');
  assert.equal(timelineButtons[0].querySelector('.storm-day-summary').children[0].textContent,'1+');
  assert.equal(timelineButtons[0].children.filter(x=>x.className==='storm-day-summary').length,1); // Rebuilt strips never duplicate.
  assert.match(controls['storm-status'].textContent,/1 reports.*Complete/);
  assert.equal(controls['storm-rows'].children[0].dataset.id,'b2026-09-01'); // Start exactly noon included, prior second excluded.
  assert.match(controls['storm-window-caption'].textContent,/Sep 1, 2026, 12:00 UTC.*Sep 2, 2026, 12:00 UTC/);
  await select('2026-09-03');assert.equal(controls['storm-rows'].children[0].dataset.id,'a2026-09-03'); // End exactly noon excluded.
  await select('2026-09-04');assert.equal(controls['storm-rows'].children[0].dataset.id,'b2026-09-03'); // Same noon report belongs to next map day.
  assert.match(controls['storm-status'].textContent,/PARTIAL.*Sep 4, 2026, 00:00 UTC.*Sep 4, 2026, 12:00 UTC/);
  await select('2026-09-03');await change('storm-window','7');
  assert.match(controls['storm-window-caption'].textContent,/Aug 27, 2026, 12:00 UTC.*Sep 3, 2026, 12:00 UTC/);
  await change('storm-window','30');assert.match(controls['storm-window-caption'].textContent,/Aug 4, 2026, 12:00 UTC.*Sep 3, 2026, 12:00 UTC/);
  await change('storm-window','1');await select('2027-01-01');
  assert.match(controls['storm-window-caption'].textContent,/Dec 31, 2026, 12:00 UTC.*Jan 1, 2027, 12:00 UTC/);
  await select('2024-03-01');assert.match(controls['storm-window-caption'].textContent,/Feb 29, 2024, 12:00 UTC.*Mar 1, 2024, 12:00 UTC/);
  manifest.timeline.utc[0].stale=true;manifest.stale_dates=['2026-09-01'];
  await change('storm-timing','utc');await select('2026-09-01','AZ');
  assert.equal(timelineButtons[0].querySelector('.storm-day-summary').children[0].textContent,'1*');
  assert.match(controls['storm-status'].textContent,/refresh pending/);
  assert.match(controls['storm-view-context'].textContent,/retained pending refresh/);
  manifest.timeline.utc[1].available=false;manifest.timeline.utc[1].complete=false;days[1].status='UNAVAILABLE';
  await select('2026-09-02');
  assert.equal(timelineButtons[1].querySelector('.storm-day-summary').children[0].textContent,'?');
  assert.equal(controls['storm-view-count'].textContent,'Report data unavailable');
  assert.ok(!requests.some(x=>/^https?:/.test(x)));
  console.log('PASS: PRISM/UTC windows (1/7/30 days), noon boundaries, leap/year rollover, linked filters, missing data/retries and report selection.');
})().catch(e=>{console.error(e);process.exitCode=1;});
