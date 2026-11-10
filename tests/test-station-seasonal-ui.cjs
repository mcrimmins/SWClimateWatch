// Exercise the real generated payloads with the local preview's controls.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=(process.argv[2] || 'data/diagnostics/station-seasonal-pilot').replace(/\/$/,'')+'/', controls={};
function element(){return {children:[],style:{},attributes:{},value:'',hidden:false,textContent:'',listeners:{},
  append(...nodes){this.children.push(...nodes);if(this===controls.station&&!this.value)this.value=String(nodes[0].value);},
  replaceChildren(){this.children=[];},setAttribute(k,v){this.attributes[k]=v;},
  addEventListener(k,v){this.listeners[k]=v;}};}
const get=id=>controls[id]||(controls[id]=element());
get('period').value='to-date';get('season').value='water';
const requests=[];
const context=vm.createContext({URLSearchParams,document:{getElementById:get,createElement:element},
  fetch:async path=>{requests.push(path);return {ok:fs.existsSync(root+path),json:async()=>JSON.parse(fs.readFileSync(root+path,'utf8'))};}});
vm.runInContext(fs.readFileSync('scripts/station-seasonal-assets/cumulative.js','utf8').replace(/initialize\(\);\s*$/,''),context);
const run=code=>vm.runInContext(code,context),flush=()=>new Promise(resolve=>setImmediate(resolve));
(async()=>{
  await run('initialize()');await flush();
  assert.equal(controls.error.hidden,true,controls.error.textContent);
  assert.equal(controls['station-card'].hidden,false);
  assert.match(controls.matched.textContent,/wet rank #/);
  assert.match(controls['annual-title'].textContent,/water year/);
  assert.match(controls['station-note'].textContent,/Water year/);
  assert.equal(run('data.points.length'),365);
  for(const season of ['cool','monsoon','water']){
    controls.season.value=season;await controls.season.listeners.change();await flush();
    assert.equal(controls.error.hidden,true,controls.error.textContent);
    assert.equal(run('data.season'),season);
    assert.equal(run('data.points.length'),{water:365,cool:182,monsoon:108}[season]);
    assert.match(controls['annual-plot'].innerHTML,/current-year-hatch/);
    controls.period.value='full';controls.period.listeners.change();
    assert.equal(Number(controls.inspect.max),run('data.points.length-1'));
    controls['comparison-year'].value=String(run('data.comparison_years[0].water_year'));
    await controls['comparison-year'].listeners.change();
    assert.equal(run('comparisonValues.length'),run('data.points.length'));
    assert.doesNotMatch(controls['comparison-status'].textContent,/could not be loaded/);
    if(season==='monsoon')assert.match(controls['annual-current'].textContent,/Complete latest season/);
  }
  controls.station.value='1403';await controls.station.listeners.change();await flush();
  assert.match(controls['station-title'].textContent,/PHOENIX/);
  assert.equal(run('data.uid'),1403);
  // A stale response from a different season must never overwrite the latest choice.
  controls.season.value='cool';const old=controls.season.listeners.change();
  controls.season.value='monsoon';const latest=controls.season.listeners.change();
  await Promise.all([old,latest]);await flush();
  assert.equal(run('data.season'),'monsoon');
  // Embedded panels must honor the parent station and snapshot, not a default station.
  const snapshot=JSON.parse(fs.readFileSync(root+'stations.json','utf8')).as_of;
  let embedded=false;
  context.document.body={classList:{add:name=>{embedded=name==='embedded';}}};
  context.window={location:{search:`?embedded=1&uid=29687&as_of=${snapshot}`}};
  await run('initialize()');await flush();
  assert.equal(embedded,true);
  assert.equal(run('data.uid'),29687);
  context.window.location.search='?embedded=1&uid=29687&as_of=1900-01-01';
  await run('initialize()');
  assert.match(controls.error.textContent,/do not match this station page date/);
  console.log('PASS: seasonal selectors, station switching, lazy comparisons, plot lengths and stale-response protection.');
})().catch(error=>{console.error(error);process.exitCode=1;});
