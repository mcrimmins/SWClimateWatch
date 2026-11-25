// Exercise the real standalone 30-day shortcut with the connected adapter.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const standalone=fs.readFileSync('scripts/daily-explorer-assets/explorer.js','utf8');
const shortcut=standalone.slice(standalone.indexOf('function changeMapView('),standalone.indexOf('function comparisonDates('));
const bridge=fs.readFileSync('scripts/daily-explorer-archive-assets/connected-bridge.js','utf8');
function setup(requested,last,mode='30',missing=false){
  const messages=[],frames=[],elements={},windowHandlers={};let renders=0;
  const select=(id,value,options)=>elements[id]={value,options:options.map(value=>({value})),dispatchEvent(event){
    if(id==='compare')context.changeMapView();
    // Other restored controls can also render a transient context date.
    if(id==='region'){context.selectedDate=last;context.render();}
  }};
  select('compare','single',['single','7','30']);select('circulation-compare','single',['single','7','30']);
  select('year','2025',['2025']);
  select('region','AZNM',['AZNM','AZ','NM']);select('variable','pcpn',['pcpn','tmean']);
  select('view','departure',['departure','observed']);select('metric','mean',['mean']);
  select('circulation-period','1',['1','7','30']);select('storm-timing','prism',['prism','utc']);select('storm-window','1',['1','7','30']);
  elements.date={value:last};elements.error={hidden:true};elements.map={hidden:false,complete:false};
  for(const id of ['circulation-panel','storm-panel','hazard-panel'])elements[id]={open:false};
  elements['hazard-frame']={};
  const parent={postMessage:m=>messages.push(m)};
  const thumbnails=Array.from({length:90},(_,i)=>({dataset:{connectedSrc:`maps/${i}.png`},loading:'lazy',
    getBoundingClientRect:()=>({top:(i<30?1700:6000)+Math.floor((i%30)/5)*150,bottom:(i<30?1820:6120)+Math.floor((i%30)/5)*150,width:120,height:120}),
    closest:()=>i>=60?{}:null}));
  const context={URL,Event:class{constructor(type){this.type=type;}},window:{addEventListener:(name,fn)=>windowHandlers[name]=fn},parent,
    location:{href:`http://example.test/archive/wy2025/months/${requested.slice(0,7)}/index.html?date=${requested}&compare=${mode}&region=AZ&connectedMonth=${requested.slice(0,7)}&archiveToken=9`,origin:'http://example.test'},
    selectedDate:last,byDate:new Map((missing?[last]:[requested,last]).map(d=>[d,{}])),circulationEnabled:true,
    document:{getElementById:id=>elements[id],documentElement:{classList:{toggle(){}}},
      querySelector:()=>({getBoundingClientRect:()=>({height:1500})}),querySelectorAll:()=>thumbnails.filter(img=>'connectedSrc'in img.dataset),addEventListener(){}},
    requestAnimationFrame:fn=>frames.push(fn),MutationObserver:class{observe(){}},ResizeObserver:class{observe(){}},
    getComputedStyle:()=>({display:'block'}),$:id=>elements[id],filterDates:()=>[requested,last],
    render:()=>{renders++;elements.date.value=context.selectedDate;},selectDate:d=>{context.selectedDate=d;context.render();}};
  vm.createContext(context);vm.runInContext(shortcut,context);
  elements.compare.value='30';context.selectedDate=requested;context.changeMapView();
  assert.equal(context.selectedDate,last,'The actual standalone shortcut reproduces the jump to context end');
  elements.compare.value='single';context.selectedDate=last;context.render();
  const before=renders;vm.runInContext(bridge,context);context.render();frames.shift()();
  if(!missing)assert.equal(renders-before,1,'Control restoration produces one full render instead of repeated 30-day redraws');
  return {context,elements,messages,thumbnails,viewport:(top,bottom,token='9')=>windowHandlers.message({origin:context.location.origin,source:parent,data:{type:'swc:connected-viewport',token,top,bottom}})};
}
for(const [date,last]of [['2024-10-31','2024-11-03'],['2024-12-31','2025-01-03'],['2025-01-31','2025-02-03'],['2025-02-28','2025-03-03'],['2025-08-31','2025-09-03'],['2025-09-30','2025-09-30']]){
  for(const mode of ['single','7','30']){
    const {context,elements,messages}=setup(date,last,mode);
    assert.equal(context.selectedDate,date,`${date}/${mode}: restored controls retain the requested day`);
    assert.equal(messages[0].date,date,`${date}/${mode}: initialization never reports the next month`);
    assert.equal(messages[0].ready,true,'An incomplete image never blocks the selected-day viewer');
    assert.equal(elements.compare.value,mode);
    for(const newMode of ['7','30','single','30']){
      elements.compare.value=newMode;context.changeMapView();assert.equal(context.selectedDate,date,'User map-view changes also preserve the selected day');
    }
    context.selectDate(last);assert.equal(context.selectedDate,last,'A real date selection still works');
  }
}
const absent=setup('2025-01-31','2025-02-03','30',true);
assert.match(absent.messages[0].error,/missing/);assert.equal(absent.messages[0].date,undefined,'Missing dates do not get substituted');
const lazy=setup('2025-01-31','2025-02-03');
const loaded=()=>lazy.thumbnails.filter(img=>img.src).length;
assert.equal(loaded(),0,'No thumbnail requests during hidden-frame startup');
lazy.viewport(1700,1980,'old-token');assert.equal(loaded(),0,'Old viewport token is ignored');
lazy.viewport(0,1000);assert.equal(loaded(),0,'Below-fold comparison grids remain deferred');
lazy.viewport(1700,1980);assert.equal(loaded(),10,'Only the visible thumbnail rows are requested');
lazy.viewport(2000,2130);assert.equal(loaded(),15,'Scrolling loads the next visible row');
assert.equal(lazy.thumbnails.slice(30).filter(img=>img.src).length,0,'Weather grids and hidden fields stay unloaded');
console.log('PASS: date stability, one-pass restoration, image-independent readiness and viewport-bounded thumbnail loading.');
