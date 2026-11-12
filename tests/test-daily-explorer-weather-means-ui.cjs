const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
function element(tag='div'){return {tag,children:[],attributes:{},listeners:{},value:'',hidden:false,open:false,textContent:'',style:{},classList:{toggle(){}},
  get selectedOptions(){return [this.children.find(x=>x.value===this.value)||{textContent:this.value}];},
  append(...nodes){this.children.push(...nodes);if(this.tag==='select'&&!this.value)this.value=nodes[0].value;},
  replaceChildren(...nodes){this.children=nodes;if(this.tag==='select')this.value=nodes[0]?.value||'';},
  setAttribute(k,v){this.attributes[k]=v;},getAttribute(k){return k==='src'?this.src||null:this.attributes[k]||null;},
  removeAttribute(k){delete this.attributes[k];delete this[k];},addEventListener(k,v){this.listeners[k]=v;},focus(){},scrollIntoView(){}};}
const html=fs.readFileSync('scripts/daily-explorer-assets/index.html','utf8');
const controls=Object.fromEntries([...html.matchAll(/<(\w+)([^>]*\bid="([^"]+)"[^>]*)>/g)].map(([,tag,,id])=>[id,element(tag)]));
for(const [id,value] of Object.entries({season:'all',region:'AZNM',variable:'pcpn',view:'departure',compare:'single','circulation-compare':'single','circulation-period':'1'}))controls[id].value=value;
const dates=Array.from({length:35},(_,i)=>new Date(Date.UTC(2026,8,i+1)).toISOString().slice(0,10));
const fields=['height500','jet250','moisture'];
const days=dates.map(date=>({date,water_year:date<'2026-10-01'?2026:2027,
 images:Object.fromEntries(['pcpn_observed','maxt_observed','maxt_departure','mint_observed','mint_departure','tmean_observed','tmean_departure'].map(k=>[k,`maps/${date}-${k}.png`])),
 regions:Object.fromEntries(['AZNM','AZ','NM'].map(region=>[region,Object.fromEntries(['pcpn','maxt','mint','tmean'].map(variable=>[variable,{mean:1,departure:2,rain010:3,rain050:4,rain100:5,spatial_p99:6,warm:7,cold:8,freeze:9}]))]))}));
const weather={schema_version:1,days:dates.map(date=>({date,status:'available',images:Object.fromEntries(fields.map(f=>[f,`circulation/maps/${date}-${f}.png`]))}))};
const means={schema_version:1,periods:[{days:7,start:'2026-09-29'},{days:30,start:'2026-09-06'}].map(p=>({...p,end:'2026-10-05',images:Object.fromEntries(fields.map(f=>[f,`circulation/means/2026-10-05-${p.days}day-${f}.png`]))}))};
const counts={daily:0,means:0};let production=false,publicMeans=false;
const context=vm.createContext({URLSearchParams,document:{getElementById:id=>controls[id],createElement:element},fetch:async url=>({ok:true,json:async()=>{
 if(url==='daily-data.json')return {schema_version:1,days,latest_cached_date:'2026-10-05',baseline:'1991-2020',circulation_enabled:true,circulation_period_means_preview:true,circulation_period_means_enabled:publicMeans,publication_mode:production};
 if(url==='circulation-manifest.json'){counts.daily++;return weather;}
 assert.equal(url,'circulation-means-manifest.json');counts.means++;return means;
}})});
vm.runInContext(fs.readFileSync('scripts/daily-explorer-assets/explorer.js','utf8').replace(/initialize\(\);\s*$/,''),context);
const run=expression=>vm.runInContext(expression,context);
const active=()=>controls['circulation-maps'].children.find(x=>!x.hidden);
async function change(id,value){controls[id].value=value;await controls[id].listeners.change();await run('renderCirculation()');}
(async()=>{
 await run('initialize()');assert.equal(controls.date.value,'2026-10-05');assert.deepEqual(counts,{daily:0,means:0});
 assert.equal(controls['circulation-period-control'].hidden,false);
 controls['circulation-panel'].open=true;await controls['circulation-panel'].listeners.toggle();
 assert.deepEqual(counts,{daily:1,means:0});
 for(const period of ['1','7','30'])for(const mode of ['single','7','30'])for(const variable of ['pcpn','tmean','maxt','mint']){
   await change('circulation-period',period);await change('circulation-compare',mode);await change('variable',variable);
   for(const region of ['AZNM','AZ','NM']){
     await change('region',region);
     for(const field of fields){
       controls[`circulation-tab-${field}`].listeners.click();
       const image=active().children[0];
       assert.equal(image.src,period==='1'?`circulation/maps/2026-10-05-${field}.png`:`circulation/means/2026-10-05-${period}day-${field}.png`);
       assert.equal(active().circulationActions.children[0].href,image.src);
       assert.equal(controls.date.value,controls['circulation-date-input'].value);
       assert.equal(controls.compare.value,controls['circulation-compare'].value);
       assert.equal(active().circulationGrid.children.length,mode==='single'?0:Number(mode));
       if(mode!=='single')assert(active().circulationCaption.textContent.startsWith('Daily maps'));
       assert(controls['discussion-date'].textContent.includes('Oct 5'));
     }
   }
 }
 assert.deepEqual(counts,{daily:1,means:1});
 // Daily thumbnails always open the map they depict, even from mean mode.
 for (const period of ['7','30']) {
   run('selectDate("2026-10-05")');await run('renderCirculation()');
   await change('circulation-period',period);await change('circulation-compare','7');
   assert.match(active().circulationCaption.textContent,/Select a tile to show its daily map/);
   const tile=active().circulationGrid.children.find(b=>b.attributes['aria-label'].includes('Oct 4'));
   tile.listeners.click();await run('renderCirculation()');
   assert.equal(controls['circulation-period'].value,'1');assert.equal(controls.date.value,'2026-10-04');
   assert.equal(controls['circulation-date-input'].value,'2026-10-04');
   assert.equal(active().children[0].src,'circulation/maps/2026-10-04-moisture.png');
   assert.equal(controls.compare.value,'7');
 }
 run('selectDate("2026-10-05")');await run('renderCirculation()');
 // Calendar stepping updates both sections and retains averaging/tab choices.
 await change('circulation-period','7');await change('circulation-compare','single');
 controls['circulation-previous'].listeners.click();await run('renderCirculation()');
 assert.equal(controls.date.value,'2026-10-04');assert.equal(controls['circulation-date-input'].value,'2026-10-04');
 assert.match(controls['circulation-status'].textContent,/7-day.*unavailable.*Oct 4.*No other date/);
 assert.equal(controls['circulation-maps'].children.length,0); // Never substitute Oct 5 mean.
 assert.equal(controls['circulation-show-daily'].hidden,false);
 controls['circulation-show-daily'].listeners.click();await run('renderCirculation()');
 assert.equal(controls['circulation-period'].value,'1');assert(active().children[0].src.includes('2026-10-04-moisture'));
 assert.equal(controls['circulation-show-daily'].hidden,true);
 await change('circulation-period','7');
 controls['circulation-latest'].listeners.click();await run('renderCirculation()');assert(active().children[0].src.includes('7day-moisture'));
 await change('circulation-date-input','2026-09-30');assert.equal(controls.year.value,'2026');
 assert.equal(controls.date.value,'2026-09-30');assert.equal(controls['circulation-period'].value,'7');
 controls.latest.listeners.click();await run('renderCirculation()');assert.equal(controls.year.value,'2027');
 await change('circulation-period','30');assert.match(active().children[0].alt,/2026-09-06 through 2026-10-05/);
 assert.throws(()=>run(`validateCirculationMeansManifest({schema_version:1,periods:[{days:7,start:'2026-10-01',end:'2026-10-05'}]})`),/period/);
 assert.throws(()=>run(`validateCirculationMeansManifest({schema_version:1,periods:[{days:7,start:'2026-09-29',end:'2026-10-05',images:{height500:'https://example.com/a.png'}}]})`),/path/);
 const originalFetch=context.fetch;let resolve;
 context.fetch=()=>new Promise(r=>resolve=r);
 const old=run('circulationMeansPromise=null; circulationShownDate=""; $("circulation-period").value="7"; renderCirculation()');
 const current=run('selectedDate="2026-10-04"; $("circulation-period").value="30"; renderCirculation()');
 resolve({ok:true,json:async()=>means});await Promise.all([old,current]);
 assert.match(controls['circulation-status'].textContent,/30-day.*Oct 4/);
 assert.equal(controls['circulation-maps'].children.length,0);
 context.fetch=originalFetch;run('selectDate("2026-10-05")');await run('renderCirculation()');
 // Failed mean availability is isolated from daily PRISM and can be retried.
 context.fetch=async()=>{throw Error('offline');};await run('circulationMeansPromise=null; circulationShownDate=""; renderCirculation()');
 assert.match(controls['circulation-status'].textContent,/could not be loaded/);assert.equal(controls['circulation-retry'].hidden,false);
 assert.equal(controls.date.value,'2026-10-05');assert.equal(controls.map.hidden,false);
 context.fetch=originalFetch;production=true;await run('initialize()');
 assert.equal(controls['circulation-period-control'].hidden,true);assert.equal(run('circulationPeriod()'),'1');
 publicMeans=true;await run('initialize()');assert.equal(controls['circulation-period-control'].hidden,false);
 run('circulationMeansPromise=null');await change('circulation-period','7');assert(active().children[0].src.includes('7day-moisture'));
 console.log('PASS: all weather-period/tab/grid/variable/region combinations, shared dates, cross-year navigation, exact missing windows and network isolation.');
})().catch(e=>{console.error(e);process.exitCode=1;});
