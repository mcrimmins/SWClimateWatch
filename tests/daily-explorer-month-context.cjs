const assert=require('node:assert/strict');
const context=require('../scripts/daily-explorer-archive-assets/month-context.js');
const root='http://example.test/preview/';
const months=['2024-10','2024-11','2024-12'];
const days=months.map((m,i)=>[{date:`${m}-${i===0?'31':'01'}`,images:{pcpn_observed:`maps/${m}.png`}}]);
const catalog={wy2025_pilot:true,months:months.map((m,i)=>({month:m,path:`months/${m}/daily-data.json`,dates:days[i].map(d=>d.date)}))};
const docs=new Map([[`${root}archive-catalog.json`,catalog]]);
for(let i=0;i<months.length;i++) {
  const base=`${root}months/${months[i]}/`;
  docs.set(`${base}daily-data.json`,{days:days[i]});
  docs.set(`${base}storm-reports-manifest.json`,{days:[{date:days[i][0].date,path:`reports/${days[i][0].date}.json`,status:'EMPTY'}],timeline:{prism:[{date:days[i][0].date}],utc:[]},stale_dates:[]});
  docs.set(`${base}reports/${days[i][0].date}.json`,{date:days[i][0].date,reports:[]});
  docs.set(`${base}circulation-manifest.json`,{days:[{date:days[i][0].date,end:days[i][0].date,days:1,images:{height500:'circulation/map.png'}}]});
  docs.set(`${base}circulation-means-manifest.json`,{periods:[{end:days[i][0].date,days:30,images:{height500:'circulation/mean.png'}}]});
  docs.set(`${base}hazard-timeline.json`,{start:days[i][0].date,end_exclusive:days[i][0].date,types:['Flood Warning'],timeline:{prism:[{date:days[i][0].date}],utc:[]}});
}
const requests=[];
const get=async url=>{requests.push(String(url));const data=docs.get(String(url));assert.ok(data,`Unexpected request ${url}`);return new Response(JSON.stringify(data));};
(async()=>{
  const client=context(`${root}months/2024-11/index.html`,get);
  const p=await(await client.fetch('daily-data.json')).json();
  assert.deepEqual(p.days.map(d=>d.date),['2024-10-31','2024-11-01']);
  assert.equal(p.days[0].images.pcpn_observed,`${root}months/2024-10/maps/2024-10.png`);
  const reports=await(await client.fetch('storm-reports-manifest.json')).json();
  assert.equal(reports.days.length,2);assert.equal(reports.days[0].path,'reports/2024-10-31.json');
  const report=await(await client.fetchReport(reports.days[0].path)).json();assert.equal(report.date,'2024-10-31');
  await assert.rejects(()=>client.fetchReport('../secret.json'),/Unlisted/);
  assert.equal(reports.timeline.prism.length,2);
  const weather=await(await client.fetch('circulation-manifest.json')).json();assert.equal(weather.days.length,2);
  assert.equal(client.canonical(weather.days[0].images.height500),'circulation/map.png');
  const means=await(await client.fetch('circulation-means-manifest.json')).json();assert.equal(means.periods.length,2);
  const hazards=await(await client.fetch('hazard-timeline.json')).json();assert.equal(hazards.timeline.prism.length,2);assert.deepEqual(hazards.types,['Flood Warning']);
  assert.ok(!requests.some(u=>u.includes('2024-12')),'Months outside the context window are not fetched');
  assert.ok(!requests.some(u=>u.endsWith('.png')),'No images fetched by metadata loader');
  const before=requests.length;await client.fetch('daily-data.json');assert.equal(requests.length,before,'Repeated metadata uses cached promises');
  // The same loader supports the next completed year; reject unknown catalogs.
  docs.set(`${root}archive-catalog.json`,{...catalog,wy2025_pilot:false,wy2026_pilot:true,schema_version:1});
  const next=await(await context(`${root}months/2024-11/index.html`,get).fetch('daily-data.json')).json();
  assert.equal(next.days.length,2);
  docs.set(`${root}archive-catalog.json`,{...catalog,wy2025_pilot:false});
  await assert.rejects(()=>context(`${root}months/2024-11/index.html`,get).fetch('daily-data.json'),/Wrong month context catalog/);
  const years='http://example.test/archive/';
  const cross=[{dates:['2025-09-30'],path:'months/2025-09/daily-data.json'},
    {dates:['2025-10-01'],path:'../wy2026/months/2025-10/daily-data.json'}];
  docs.set(`${years}wy2025/archive-catalog.json`,{wy2025_pilot:true,months:cross});
  for(const [owner,month,day]of [['wy2025','2025-09','30'],['wy2026','2025-10','01']])
    docs.set(`${years}${owner}/months/${month}/daily-data.json`,{days:[{date:`${month}-${day}`,images:{pcpn_observed:'maps/observed.png'}}]});
  const spanning=await(await context(`${years}wy2025/months/2025-09/index.html`,get).fetch('daily-data.json')).json();
  assert.deepEqual(spanning.days.map(d=>d.date),['2025-09-30','2025-10-01']);
  assert.equal(spanning.days[1].images.pcpn_observed,`${years}wy2026/months/2025-10/maps/observed.png`);
  console.log('PASS: adjacent month dates, rebased map/report paths, weather means, both event timelines, request reuse and lazy image loading.');
})().catch(e=>{console.error(e);process.exitCode=1;});
