"use strict";
const SWCConnected=(()=>{
  const safe=p=>typeof p==='string'&&/^[A-Za-z0-9_./-]+$/.test(p)&&!p.startsWith('/')&&!p.split('/').some(x=>!x||x==='.'||x==='..');
  const iso=d=>typeof d==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(d)&&!isNaN(Date.parse(d))&&new Date(`${d}T12:00:00Z`).toISOString().slice(0,10)===d;
  const year=d=>Number(d.slice(0,4))+(Number(d.slice(5,7))>=10?1:0);
  const keys=['region','variable','view','compare','weatherPeriod','timing','eventWindow','metric','openWeather','openReports','openHazards'];
  function validate(c){
    if(c.schema_version!==1||c.connected_explorer!==true||!Array.isArray(c.months)||!c.months.length)throw Error('Invalid connected Explorer catalog.');
    const seen=new Set(),months=new Set();
    for(const m of c.months){
      if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(m.month)||months.has(m.month)||!['current','archive'].includes(m.kind)||!safe(m.viewer)||!m.viewer.endsWith('/index.html')||!Array.isArray(m.dates)||!m.dates.length)throw Error('Invalid connected month.');
      months.add(m.month);
      if(m.dates.join()!==[...m.dates].sort().join())throw Error('Unsorted connected dates.');
      for(const d of m.dates){if(!iso(d)||!d.startsWith(m.month)||year(d)!==m.water_year||seen.has(d))throw Error('Invalid or duplicate connected date.');seen.add(d);}
    }
    const current=c.months.filter(m=>m.kind==='current').flatMap(m=>m.dates).sort();
    if(!current.length||c.latest!==current.at(-1))throw Error('Latest must match the current cache.');
    return c;
  }
  const partition=(c,d)=>c.months.find(m=>m.dates.includes(d));
  function selection(value){return Object.fromEntries(keys.filter(k=>typeof value?.[k]==='string'&&value[k].length<=80).map(k=>[k,value[k]]));}
  const height=h=>Number.isFinite(h)&&h>=100&&h<=40000?Math.ceil(h)+6:null;
  return{validate,partition,selection,height,safe,keys};
})();
if(typeof module!=='undefined')module.exports=SWCConnected;
