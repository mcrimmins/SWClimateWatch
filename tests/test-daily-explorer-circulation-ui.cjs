const fs=require('node:fs'), vm=require('node:vm'), assert=require('node:assert/strict');
const element=()=>({children:[],hidden:false,open:false,listeners:{},attributes:{},textContent:'',
  classList:{toggle(){}},
  setAttribute(name,value){this.attributes[name]=value;},
  getAttribute(name){return name==='src' ? this.src || null : this.attributes[name] || null;},
  focus(){this.focused=true;},
  append(...nodes){this.children.push(...nodes);},replaceChildren(...nodes){this.children=nodes;},
  addEventListener(event,callback){this.listeners[event]=callback;}});
const controls=Object.fromEntries(['circulation-panel','circulation-date','circulation-maps',
  'circulation-status','circulation-retry','circulation-tabs','circulation-compare','compare',
  'circulation-view-control','circulation-view-fallback',
  'circulation-tab-height500','circulation-tab-jet250','circulation-tab-moisture'].map(id=>[id,element()]));
let requests=0;
controls.compare.value = 'single';
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
  assert.equal(controls['circulation-view-fallback'].hidden,false);
  // A grid still shows exact-date availability when its selected day is missing.
  run(`days = [{date:'2026-10-03',water_year:2027},{date:'2026-10-04',water_year:2027}];
    byDate = new Map(days.map(day => [day.date,day]));`);
  controls.compare.value = '7';
  run('selectCirculationTab("height500")');
  await run('renderCirculation()');
  assert.equal(controls['circulation-compare'].value,'7');
  assert.equal(controls['circulation-tabs'].hidden,false);
  let grid = controls['circulation-maps'].children[0].circulationGrid;
  assert.equal(grid.children.length,7);
  assert.equal(grid.children.filter(button => button.children.some(node => node.src)).length,1);
  assert.equal(grid.children.find(button => button.attributes['aria-label'].includes('Oct 4')).children[1].textContent,
    'Not built or unavailable');
  assert.match(controls['circulation-status'].textContent,/Oct 4.*No other date/);
  run('selectCirculationTab("moisture")');
  grid = controls['circulation-maps'].children[2].circulationGrid;
  assert.equal(grid.children.length,7);
  assert.equal(grid.children.find(button => button.children.some(node => node.src)).children[1].src,
    payload.days[0].images.moisture);
  // 30 days uses the same trailing window and only the active field's thumbnails.
  controls.compare.value = '30';
  await run('renderCirculation()');
  const monthFigures = controls['circulation-maps'].children;
  assert.equal(monthFigures[2].circulationGrid.children.length,30);
  assert.equal(monthFigures[0].circulationGrid.children.length,0);
  assert.match(monthFigures[2].circulationCaption.textContent,/30 days ending Oct 4/);
  assert.equal(requests,1); // One manifest request across all tabs and views.
  controls.compare.value = 'single';
  run('selectCirculationTab("jet250")');
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
  // Changing the view while availability loads must not leave the old grid.
  const oldMode = run('circulationPromise=null; selectedDate="2026-10-03"; $("compare").value="30"; renderCirculation()');
  const newMode = run('$("compare").value="7"; renderCirculation()');
  resolve({ok:true,json:async()=>payload}); await Promise.all([oldMode,newMode]);
  assert.equal(controls['circulation-maps'].children[1].circulationGrid.children.length,7);
  assert.match(controls['circulation-maps'].children[1].circulationCaption.textContent,/7 days centered/);
  context.fetch=async()=>{throw Error('offline');};
  await run('circulationPromise=null; circulationShownDate=""; renderCirculation()');
  assert.match(controls['circulation-status'].textContent,/could not be loaded/);
  assert.equal(controls['circulation-retry'].hidden,false);
  console.log('Circulation UI passed: opt-in, lazy load, exact dates, failures and request races.');
})().catch(error=>{console.error(error);process.exitCode=1;});
