const fs=require('node:fs'), vm=require('node:vm'), assert=require('node:assert/strict');
const element=()=>({children:[],hidden:false,open:false,listeners:{},attributes:{},textContent:'',
  setAttribute(name,value){this.attributes[name]=value;},
  getAttribute(name){return name==='src' ? this.src || null : this.attributes[name] || null;},
  focus(){this.focused=true;},
  append(...nodes){this.children.push(...nodes);},replaceChildren(...nodes){this.children=nodes;},
  addEventListener(event,callback){this.listeners[event]=callback;}});
const controls=Object.fromEntries(['circulation-panel','circulation-date','circulation-maps',
  'circulation-status','circulation-retry','circulation-tabs',
  'circulation-tab-height500','circulation-tab-jet250','circulation-tab-moisture'].map(id=>[id,element()]));
let requests=0;
const payload={schema_version:1,days:[{date:'2026-10-03',status:'available',images:{
  height500:'circulation/maps/2026-10-03-height500.png',jet250:'circulation/maps/2026-10-03-jet250.png',
  moisture:'circulation/maps/2026-10-03-moisture.png'}}]};
const context=vm.createContext({document:{getElementById:id=>controls[id],createElement:element},
  fetch:async()=>{requests++; return {ok:true,json:async()=>payload};}});
vm.runInContext(fs.readFileSync('scripts/daily-explorer-assets/explorer.js','utf8').replace(/initialize\(\);\s*$/,''),context);
const run=code=>vm.runInContext(code,context);
(async()=>{
  run('selectedDate="2026-10-03"');
  await run('renderCirculation()'); assert.equal(requests,0); // Not enabled.
  run('circulationEnabled=true');
  await run('renderCirculation()'); assert.equal(requests,0); // Closed.
  controls['circulation-panel'].open=true;
  await run('renderCirculation()');
  assert.equal(requests,1); assert.equal(controls['circulation-maps'].children.length,3);
  const image=controls['circulation-maps'].children[0].children[0];
  assert.equal(image.src,payload.days[0].images.height500);
  assert.equal(image.loading,'lazy');
  const figures=controls['circulation-maps'].children;
  assert.equal(figures[0].hidden,false); assert.equal(figures[1].hidden,true);
  assert.equal(figures[1].children[0].src,undefined); // Inactive map not fetched.
  run('setupCirculationTabs()');
  controls['circulation-tab-jet250'].listeners.click();
  assert.equal(figures[0].hidden,true); assert.equal(figures[1].hidden,false);
  assert.equal(figures[1].children[0].src,payload.days[0].images.jet250);
  assert.equal(controls['circulation-tab-jet250'].attributes['aria-selected'],'true');
  controls['circulation-tab-jet250'].listeners.keydown({key:'ArrowRight',preventDefault(){}});
  assert.equal(figures[2].hidden,false);
  assert.equal(figures[2].children[0].src,payload.days[0].images.moisture);
  controls['circulation-tab-moisture'].listeners.keydown({key:'ArrowRight',preventDefault(){}});
  assert.equal(figures[0].hidden,false);
  controls['circulation-tab-jet250'].listeners.keydown({key:'Home',preventDefault(){}});
  assert.equal(figures[0].hidden,false); assert.equal(controls['circulation-tab-height500'].focused,true);
  run('selectCirculationTab("jet250")');
  await run('renderCirculation()'); assert.equal(requests,1); // No duplicate render/fetch.
  image.listeners.error(); assert.equal(image.hidden,true);
  assert.match(controls['circulation-status'].textContent,/could not be loaded/);
  await run('selectedDate="2026-10-04"; renderCirculation()');
  assert.equal(controls['circulation-maps'].children.length,0);
  assert.match(controls['circulation-status'].textContent,/unavailable.*No other date/);
  assert.equal(requests,1);
  assert.equal(controls['circulation-tabs'].hidden,true);
  await run('selectedDate="2026-10-03"; renderCirculation()');
  assert.equal(controls['circulation-maps'].children[1].hidden,false); // Tab persists across dates.
  await run('selectedDate="2026-10-04"; renderCirculation()');
  assert.throws(()=>run('validateCirculationManifest({schema_version:1,days:[{date:"2026-02-30",status:"unavailable"}]})'),/date/);
  assert.throws(()=>run('validateCirculationManifest({schema_version:1,days:[{date:"2026-10-03",status:"available",images:{height500:"https://example.com/a.png"}}]})'),/path/);
  controls['circulation-panel'].open=false;
  await run('renderCirculation()');
  // Switch dates while the manifest request is in flight: only the new date wins.
  let resolve;
  context.fetch=()=>{requests++; return new Promise(r=>resolve=r);};
  controls['circulation-panel'].open=true;
  const old=run('circulationPromise=null; selectedDate="2026-10-03"; renderCirculation()');
  const current=run('selectedDate="2026-10-04"; renderCirculation()');
  resolve({ok:true,json:async()=>payload}); await Promise.all([old,current]);
  assert.equal(controls['circulation-maps'].children.length,0);
  assert.match(controls['circulation-status'].textContent,/Oct 4/);
  context.fetch=async()=>{throw Error('offline');};
  await run('circulationPromise=null; circulationShownDate=""; renderCirculation()');
  assert.match(controls['circulation-status'].textContent,/could not be loaded/);
  assert.equal(controls['circulation-retry'].hidden,false);
  console.log('Circulation UI passed: opt-in, lazy load, exact dates, failures and request races.');
})().catch(error=>{console.error(error);process.exitCode=1;});
