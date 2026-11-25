// Read adjacent metadata on demand; PNGs and geometry remain lazy-loaded.
"use strict";
function swcMonthContext(base, get = globalThis.fetch.bind(globalThis)) {
  const allowed = new Set(['daily-data.json','circulation-manifest.json','circulation-means-manifest.json','storm-reports-manifest.json','hazard-timeline.json']);
  const cache = new Map();
  const reportUrls=new Map();
  const imagePaths=new Map();
  const json = url => {url=String(url);if(!cache.has(url))cache.set(url,get(url,{cache:'no-store'}).then(r=>{if(!r.ok)throw Error(`Archive metadata HTTP ${r.status}`);return r.json();}));return cache.get(url);};
  const shift=(date,n)=>{const d=new Date(`${date}T12:00:00Z`);d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
  const rebase=(paths,url)=>Object.fromEntries(Object.entries(paths||{}).map(([k,p])=>{
    const absolute=new URL(p,url).href;imagePaths.set(absolute,p);return [k,absolute];
  }));
  const unique=(rows,key)=>[...new Map(rows.map(r=>[key(r),r])).values()];
  let context;
  async function months() {
    if(!context)context=(async()=>{
      const [p,c]=await Promise.all([json(new URL('daily-data.json',base)),json(new URL('../../archive-catalog.json',base))]);
      if(c.wy2025_pilot!==true||!Array.isArray(p.days)||!p.days.length)throw Error('Wrong month context catalog');
      const first=shift(p.days[0].date,-29),last=shift(p.days.at(-1).date,3);
      const selected=c.months.filter(m=>m.dates.some(d=>d>=first&&d<=last));
      return {first,last,selected};
    })();
    return context;
  }
  async function merged(name) {
    const c=await months(),original=structuredClone(await json(new URL(name,base)));
    const parts=await Promise.all(c.selected.map(async m=>{
      const url=new URL(name,new URL(m.path,new URL('../../',base)));
      return {url,value:await json(url)};
    }));
    const inRange=d=>d>=c.first&&d<=c.last;
    const timeline=timing=>unique(parts.flatMap(p=>p.value.timeline?.[timing]||[]),r=>r.date).filter(r=>inRange(r.date)).sort((a,b)=>a.date.localeCompare(b.date));
    if(name==='daily-data.json') {
      original.days=unique(parts.flatMap(p=>p.value.days.map(d=>({...d,images:rebase(d.images,p.url)}))),d=>d.date).filter(d=>inRange(d.date)).sort((a,b)=>a.date.localeCompare(b.date));
      original.latest_cached_date=original.days.at(-1).date;
    } else if(name==='circulation-manifest.json'||name==='circulation-means-manifest.json') {
      const key=name==='circulation-manifest.json'?'days':'periods';
      original[key]=unique(parts.flatMap(p=>(p.value[key]||[]).map(d=>({...d,images:rebase(d.images,p.url)}))),d=>`${d.end}/${d.days}`).filter(d=>inRange(d.end));
    } else if(name==='storm-reports-manifest.json') {
      original.days=unique(parts.flatMap(p=>p.value.days.map(d=>{
        if(!/^reports\/\d{4}-\d{2}-\d{2}\.json$/.test(d.path))throw Error('Invalid archive report path');
        reportUrls.set(d.path,new URL(d.path,p.url).href);return {...d};
      })),d=>d.date).sort((a,b)=>a.date.localeCompare(b.date));
      original.stale_dates=[...new Set(parts.flatMap(p=>p.value.stale_dates||[]))];
      original.start=original.days[0].date;original.end_exclusive=shift(original.days.at(-1).date,1);
      original.timeline={prism:timeline('prism'),utc:timeline('utc')};
    } else {
      original.types=unique(parts.flatMap(p=>p.value.types),r=>JSON.stringify(r));
      original.timeline={prism:timeline('prism'),utc:timeline('utc')};
      original.start=parts.map(p=>p.value.start).sort()[0];original.end_exclusive=parts.map(p=>p.value.end_exclusive).sort().at(-1);
    }
    return original;
  }
  return {
    canonical:path=>imagePaths.get(path)||path,
    fetch:async(name,options)=>allowed.has(name)?new Response(JSON.stringify(await merged(name)),{status:200,headers:{'Content-Type':'application/json'}}):get(name,options),
    fetchReport:async path=>{await merged('storm-reports-manifest.json');if(!reportUrls.has(path))throw Error('Unlisted archive report path');return get(reportUrls.get(path));}
  };
}
if(typeof module!=='undefined')module.exports=swcMonthContext;
else globalThis.SWCMonthContext=swcMonthContext(location.href);
