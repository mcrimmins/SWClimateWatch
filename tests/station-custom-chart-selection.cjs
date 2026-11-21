const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const M=require('../scripts/station-custom-dates-assets/model.js');
class Element {
  constructor(){this.children=[];this.events={};this.width=1000;this.height=270;this.classList={toggle(){},add(){}};}
  set textContent(x){this.text=String(x);this.children=[];}get textContent(){return (this.text||'')+this.children.map(c=>c.textContent).join(' ');}
  append(...items){this.children.push(...items);}replaceChildren(){this.text='';this.children=[];}
  addEventListener(name,fn){this.events[name]=fn;}
  getContext(){return new Proxy({}, {get:()=>()=>{},set:()=>true});}
  getBoundingClientRect(){return {left:0,width:1000};}
  click(){this.clicked=true;}
}
const elements=new Map(),get=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id);};
const window={addEventListener(){}},document={getElementById:get,createElement:()=>new Element(),querySelectorAll:()=>[]};
let source=fs.readFileSync('scripts/station-custom-dates-assets/app.js','utf8');
source=source.replace(/\}\)\(\);\s*$/, 'window.testHistoryChart={render,setActive:(value)=>{active=value;index={uid:1};},cancel};})();');
const workers=[],urls={created:[],revoked:[],createObjectURL(blob){this.created.push(blob);return 'blob:csv-'+this.created.length;},revokeObjectURL(url){this.revoked.push(url);}};
vm.runInNewContext(source,{StationCustomModel:M,window,document,location:{search:''},URLSearchParams,
  Worker:class {constructor(){workers.push(this);this.requests=[];}terminate(){}postMessage(x){this.requests.push(x);}},URL:urls,Blob,
  fetch:()=>new Promise(()=>{}),Intl,Date,Map,Number,DOMException});
const rows=[
  {date:'2000-02-28',pcpn:0,pcpn_status:2,maxt:70,mint:40,maxt_status:1,mint_status:1},
  {date:'2000-02-29',pcpn:null,pcpn_status:3,maxt:null,mint:null,maxt_status:0,mint_status:0},
  {date:'2000-03-01',pcpn:1,pcpn_status:1,maxt:80,mint:50,maxt_status:1,mint_status:1}
];
window.testHistoryChart.render({summary:M.summarize(rows),bins:M.bins(rows)});
assert.match(get('precip-selection').textContent,/Feb 28, 2000.*0.00 in. · Trace/);
assert.match(get('temp-selection').textContent,/70.0 °F.*40.0 °F/);
assert.equal(get('precip-previous').disabled,true);
get('temp-next').events.click();
assert.match(get('precip-selection').textContent,/Feb 29, 2000.*Unavailable.*0 \/ 1.*0 \/ 1/);
assert.match(get('temp-selection').textContent,/Feb 29, 2000.*Unavailable/);
let prevented=false;
get('precip').events.keydown({key:'End',preventDefault(){prevented=true;}});
assert.equal(prevented,true);assert.match(get('temp-selection').textContent,/Mar 1, 2000.*80.0 °F/);
assert.equal(get('temp-next').disabled,true);
get('temp').events.keydown({key:'Home',preventDefault(){}});
assert.match(get('precip-selection').textContent,/Feb 28, 2000/);
get('precip').events.click({clientX:999});assert.match(get('temp-selection').textContent,/Mar 1, 2000/);
get('temp').events.pointermove({clientX:0,pointerType:'touch'});assert.match(get('temp-selection').textContent,/Mar 1, 2000/);
window.testHistoryChart.render({summary:M.summarize(rows),bins:M.bins(rows,1)});
assert.match(get('precip-selection').textContent,/Feb 28, 2000–Mar 1, 2000 · 3 days.*Observed subtotal.*1.00 in.*2 \/ 3/);
assert.match(get('temp-selection').textContent,/Interval average.*75.0 °F.*45.0 °F.*2 \/ 3/);
assert.match(get('temp-selection').textContent,/not interval extremes/);
assert.equal(get('temp-next').textContent,'Next interval →');
assert.equal(get('temp-previous').disabled,true);assert.equal(get('temp-next').disabled,true);
console.log('PASS: linked chart tables, trace/missing/flagged values, leap day, navigation bounds, keyboard, click, touch-scroll and grouped interval coverage.');
(async()=>{
  const summary=M.summarize(rows);window.testHistoryChart.setActive({key:'first',result:{summary}});
  const pending=get('download').events.click(),worker=workers.at(-1),request=worker.requests.at(-1);
  worker.onmessage({data:{id:request.id,csv:M.csv(rows,{uid:1,sid:'ID1',name:'Test'})}});await pending;
  assert.equal(get('csv-ready').download,'station-1-2000-02-28-to-2000-03-01.csv');
  assert.equal(get('csv-ready').hidden,false);assert.equal(get('csv-ready').clicked,true);
  assert.match(get('csv-status').textContent,/3 daily rows/);assert.equal(urls.created.length,1);
  const csv=await urls.created[0].text();assert.match(csv,/2000-02-29",,,,"FLAGGED","MISSING","MISSING"/);
  const next=get('download').events.click();window.testHistoryChart.cancel();await next;
  assert.equal(urls.created.length,1,'cancelled export must not create another file');
  assert.equal(get('csv-ready').hidden,true);assert.ok(urls.revoked.includes('blob:csv-1'));
  console.log('PASS: CSV filename, prepared-file fallback, blob cleanup and stale/cancelled export guards.');
})().catch(e=>{console.error(e);process.exitCode=1;});
