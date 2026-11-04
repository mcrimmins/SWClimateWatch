const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const controls = {};
function element(tag='div') {return {children:[],style:{},attributes:{},value:'',textContent:'',hidden:false,
  listeners:{},append(...nodes){this.children.push(...nodes);if(tag==='option')return;
    if(this===controls.station && !this.value)this.value=nodes[0].value;},
  replaceChildren(){this.children=[];},setAttribute(key,value){this.attributes[key]=value;},
  addEventListener(key,value){this.listeners[key]=value;}};}
const get = id => controls[id] || (controls[id]=element());
get('period').value='to-date';
const catalog={schema_version:1,as_of:'2026-10-06',stations:[1,2,3].map(uid=>({uid,name:`Station ${uid}`,state:'AZ',file:`${uid}.json`}))};
function payload(uid) {return {schema_version:1,uid,sid:'TEST',name:`Station ${uid}`,state:'AZ',role:'fixed',
  as_of:'2026-10-06',water_year:2027,previous_water_year:2026,
  baseline:{water_years:[1991,2020],sample_years:30,available:true},
  comparison_years:[{water_year:2026,annual_total:18.2,file:`history/${uid}/2026.json`},
    {water_year:2025,annual_total:9.1,file:`history/${uid}/2025.json`}],
  annual_history:{first_year:2024,last_year:2026,normal_inches:10},
  current:{total:0.5,missing_days:0,flagged_days:0},
  historical_context:{available:true,sample_years:50,first_year:1976,last_year:2026,
    cutoff_date:'2026-10-06',current_status:'WITHIN_RANGE'},
  closest_match:{available:true,water_year:2025,days_compared:6,early_season:true,
    cutoff_date:'2026-10-06',tied_years:[2025,2024]},
  points:Array.from({length:365},(_,i)=>({date:new Date(Date.UTC(2026,9,1+i)).toISOString().slice(0,10),
    month_day:new Date(Date.UTC(2026,9,1+i)).toISOString().slice(5,10),
    current:i<6?i/10:null,previous:i/20,normal:i/30,lower:i/40,upper:i/25,status:i<6?'AVAILABLE':'FUTURE',
    subtotal:i<6?i/10:null,missing_days:0,flagged_days:0,previous_missing:0,previous_flagged:0,
    record_low:i/50,record_high:i/5,low_years:'1980,1981',high_years:'1995'}))};}
const requests=[];
const historical=(uid,year)=>({schema_version:1,uid,water_year:year,calendar:'month-day-365',
  values:Array.from({length:365},(_,i)=>i/40)});
const context=vm.createContext({URLSearchParams,document:{getElementById:get,createElement:element},
  fetch:async path=>{requests.push(path);return {ok:true,json:async()=>{
    if(path==='stations.json')return catalog;
    if(path.startsWith('history/')){const [,uid,year]=path.match(/history\/(\d+)\/(\d+)\.json/);return historical(Number(uid),Number(year));}
    return payload(Number(path.split('.')[0]));
  }};}});
vm.runInContext(fs.readFileSync('scripts/station-cumulative-assets/cumulative.js','utf8').replace(/initialize\(\);\s*$/,''),context);
const run=code=>vm.runInContext(code,context);
(async()=>{
  const paths=run('linePaths([{v:0},{v:1},{v:null},{v:3}],"v",i=>i,v=>v)');
  assert.equal(paths.length,2); assert.match(paths[0],/^M0\.00,0\.00 L1\.00,1\.00/);
  assert.equal(run('bandPaths([{lower:0,upper:1},{lower:1,upper:2},{lower:null,upper:null},{lower:2,upper:3}],i=>i,v=>v).length'),2);
  await run('initialize()');
  assert.deepEqual(requests,['stations.json','1.json']);
  assert.equal(controls['station-card'].hidden,false);
  assert.equal(controls.inspect.max,'5');
  assert.equal(controls['comparison-year'].value,'2026');
  assert.match(controls.plot.innerHTML,/fill="#d5e8e3"/);
  assert.match(controls['station-title'].textContent,/Station 1/);
  assert.equal(controls['annual-history'].hidden,false);
  assert.match(controls['annual-note'].textContent,/2 complete.*1 incomplete/);
  assert.match(controls['annual-readout'].textContent,/Current WY2027.*0.50 in.*incomplete water year/);
  assert.doesNotMatch(controls['annual-readout'].textContent,/%/);
  assert.match(controls['annual-current'].textContent,/hatched bar.*excluded/);
  assert.match(controls['annual-plot'].innerHTML,/fill="url\(#current-year-hatch\)"/);
  run('inspectAnnual(2)');
  assert.match(controls['annual-readout'].textContent,/WY2026: 18.20 in.*182%/);
  run('inspectAnnual(0)');
  assert.match(controls['annual-readout'].textContent,/WY2024: Incomplete.*no total/);
  assert.doesNotMatch(controls['annual-readout'].textContent,/0.00 in/);
  run('data.annual_history.normal_inches=0; renderAnnual(); inspectAnnual(2)');
  assert.match(controls['annual-readout'].textContent,/Percent of average unavailable/);
  run('data.annual_history.normal_inches=null; renderAnnual()');
  assert.equal(controls['annual-normal-label'].hidden,true);
  run('data.annual_history.normal_inches=10; renderAnnual()');
  assert.equal(controls['annual-normal-label'].hidden,false);
  run('data.current.total=null; data.current.observed_subtotal=1.2; data.current.missing_days=2; renderAnnual()');
  assert.match(controls['annual-readout'].textContent,/≥1.20 in. recorded; 2 missing/);
  assert.doesNotMatch(controls['annual-readout'].textContent,/%/);
  run('data.current.observed_subtotal=null; renderAnnual()');
  assert.match(controls['annual-readout'].textContent,/Unavailable/);
  assert.doesNotMatch(controls['annual-plot'].innerHTML,/data-current-year=/);
  run('data.current.total=0; data.current.missing_days=0; renderAnnual()');
  assert.match(controls['annual-readout'].textContent,/0.00 in/);
  assert.match(controls['annual-plot'].innerHTML,/data-current-year="2027"/);
  run('data.current.total=100; renderAnnual()');
  const currentY=Number(controls['annual-plot'].innerHTML.match(/data-current-year="2027"[^>]* y="([\d.-]+)"/)[1]);
  assert.ok(currentY>=24,'A current record amount must fit the plotted scale');
  run('data.current.total=0.5; data.current.observed_subtotal=0.5; renderAnnual()');
  controls.period.value='full'; controls.period.listeners.change();
  assert.equal(controls.inspect.max,'364');
  run('inspect(40)');
  assert.ok(controls.readout.children.some(x=>/Not yet observed/.test(x.textContent)));
  assert.ok(controls.readout.children.some(x=>/Typical range:/.test(x.textContent)));
  assert.ok(controls.readout.children.some(x=>/Historical high:.*WY1995/.test(x.textContent)));
  assert.match(controls['history-status'].textContent,/Within historical range/);
  controls['comparison-year'].value='2025'; await run('selectComparison()');
  assert.equal(requests.filter(x=>x==='history/1/2025.json').length,1);
  controls['comparison-year'].value='closest'; await run('selectComparison()');
  assert.equal(run('comparisonYear'),2025);
  assert.match(controls['comparison-status'].textContent,/2 tied.*Early-season.*Not a forecast/);
  assert.equal(controls['previous-label'].textContent,'WY2025 (closest)');
  assert.equal(run('comparisonValues.at(-1)'),9.1);
  controls['comparison-year'].value='none'; await run('selectComparison()');
  assert.equal(run('comparisonValues'),null);
  assert.equal(controls['previous-label'].hidden,true);
  controls['comparison-year'].value='2025'; await run('selectComparison()');
  assert.equal(requests.filter(x=>x==='history/1/2025.json').length,1);
  run('data.points[3].current=null; data.points[3].subtotal=0.2; data.points[3].missing_days=1; inspect(3)');
  assert.ok(controls.readout.children.some(x=>/≥0.20 in. recorded; 1 missing/.test(x.textContent)));
  // Switching back reuses the compact station payload; no full history fetched.
  controls.station.value='3'; await run('selectStation()');
  controls.station.value='1'; await run('selectStation()');
  assert.equal(requests.filter(x=>x==='1.json').length,1);
  // A slower prior selection must not replace a newly selected station.
  let resolve;
  context.fetch=path=>new Promise(r=>resolve=()=>r({ok:true,json:async()=>payload(2)}));
  controls.station.value='2'; const slow=run('selectStation()');
  assert.equal(controls['station-card'].hidden,true);
  assert.equal(controls['annual-history'].hidden,true);
  controls.station.value='3'; await run('selectStation()');
  resolve(); await slow;
  assert.match(controls['station-title'].textContent,/Station 3/);
  assert.equal(controls['station-card'].hidden,false);
  // A comparison finishing after None was selected must not reappear.
  context.fetch=()=>new Promise(r=>resolve=()=>r({ok:true,json:async()=>historical(3,2025)}));
  controls['comparison-year'].value='2025'; const slowYear=run('selectComparison()');
  controls['comparison-year'].value='none'; await run('selectComparison()');
  resolve(); await slowYear;
  assert.equal(run('comparisonYear'),null); assert.equal(run('comparisonValues'),null);
  // Wrong-station comparison data are rejected without hiding current/reference.
  run('comparisonCache.delete("history/3/2025.json")');
  context.fetch=async()=>({ok:true,json:async()=>historical(999,2025)});
  controls['comparison-year'].value='2025'; await run('selectComparison()');
  assert.equal(run('comparisonValues'),null);
  assert.match(controls['comparison-status'].textContent,/do not match/);
  assert.equal(controls['station-card'].hidden,false);
  // A failed station cannot leave a different station's plot under its name.
  context.fetch=async()=>{throw Error('offline');};
  run('cache.delete(2)'); controls.station.value='2'; await run('selectStation()');
  assert.equal(controls['station-card'].hidden,true);
  assert.match(controls.error.textContent,/offline/);
  // Embedded charts must honor the parent's station and verified page date.
  const classes=[];
  context.window={location:{search:'?embedded=1&uid=2&as_of=2026-10-06'}};
  context.document.body={classList:{add:value=>classes.push(value)}};
  context.fetch=async path=>({ok:true,json:async()=>path==='stations.json'?catalog:payload(Number(path.split('.')[0]))});
  run('cache.clear()'); await run('initialize()');
  assert.ok(classes.includes('embedded'));
  assert.match(controls['station-title'].textContent,/Station 2/);
  context.window.location.search='?embedded=1&uid=999&as_of=2026-10-06';
  await run('initialize()'); assert.match(controls.error.textContent,/unavailable for this station/);
  context.window.location.search='?embedded=1&uid=2&as_of=2026-10-07';
  await run('initialize()'); assert.match(controls.error.textContent,/do not match this station page date/);
  console.log('Cumulative pilot UI passed: line gaps, hover values, periods, lazy caching and station races.');
})().catch(error=>{console.error(error);process.exitCode=1;});
