"use strict";
(() => {
  const $ = id => document.getElementById(id), frame = $("archive-viewer");
  let catalog, current = null, state = {}, sequence = 0;
  const label = d => new Date(`${d}T12:00:00Z`).toLocaleDateString("en-US",{month:"short",day:"numeric",year:"numeric",timeZone:"UTC"});
  const shift = (d,n) => {const x = new Date(`${d}T12:00:00Z`);x.setUTCDate(x.getUTCDate()+n);return x.toISOString().slice(0,10);};
  function options(el,rows,value) {el.replaceChildren(...rows.map(([v,t]) => {const o=document.createElement("option");o.value=v;o.textContent=t;return o;}));el.value=value;el.disabled=false;}
  function show(date) {
    const m=SWCArchive.partition(catalog,date);if(!m)throw Error("This date has not been built in the local archive. No other date was substituted.");
    const years=[...new Set(catalog.months.map(m=>m.water_year))].sort((a,b)=>b-a);
    options($("archive-year"),years.map(y=>[String(y),`WY${y} · Oct ${y-1}–Sep ${y}`]),String(m.water_year));
    options($("archive-month"),catalog.months.filter(x=>x.water_year===m.water_year).sort((a,b)=>a.month.localeCompare(b.month)).map(x=>[x.month,new Date(`${x.month}-15T12:00:00Z`).toLocaleDateString("en-US",{month:"long",year:"numeric",timeZone:"UTC"})]),m.month);
    $("archive-date").disabled=false;$("archive-date").value=date;
    const dates=catalog.months.flatMap(x=>x.dates).sort();$("archive-date").min=dates[0];$("archive-date").max=dates.at(-1);
    $("archive-previous").disabled=!SWCArchive.partition(catalog,shift(date,-1));$("archive-next").disabled=!SWCArchive.partition(catalog,shift(date,1));
    $("archive-latest").disabled=date===catalog.latest;
    $("archive-state").textContent=`${label(date)} · ${m.full?"Full July suite: PRISM, daily/7-/30-day weather, storm reports and archived NWS hazards.":"PRISM sample dates only. Weather, reports and hazards have not been built for this month."}`;
    return m;
  }
  function urlState(date) {
    const url=new URL(location.href);url.searchParams.set("date",date);
    for(const key of ["region","variable","view","compare","weatherPeriod","timing","eventWindow"])if(state[key])url.searchParams.set(key,state[key]);
    history.replaceState(null,"",url);
  }
  function fail(e) {frame.hidden=true;$("archive-error").textContent=e.message;$("archive-error").hidden=false;$("archive-state").textContent="Archive selection unavailable. No previous month's data is being substituted.";}
  function navigate(date) {
    try {
      const m=show(date);if(!SWCArchive.safe(m.viewer)||!m.viewer.endsWith("/index.html"))throw Error("Invalid month viewer path.");
      sequence++;current={date,viewer:m.viewer,full:m.full===true,token:String(sequence)};
      const u=new URL(m.viewer,location.href);u.searchParams.set("date",date);u.searchParams.set("archiveToken",current.token);
      for(const key of ["region","variable","view","compare","weatherPeriod","timing","eventWindow"])if(state[key])u.searchParams.set(key,state[key]);
      frame.hidden=false;frame.style.visibility="hidden";$("archive-error").hidden=true;$("archive-state").textContent="Loading the selected archive month…";
      frame.src=u.href;urlState(date);
    }catch(e){fail(e);}
  }
  window.addEventListener("message",event=>{
    const m=event.data;
    if(event.origin!==location.origin||event.source!==frame.contentWindow||m?.type!=="swc:archive-month"||!current||m.token!==current.token)return;
    if(!m.date||!SWCArchive.partition(catalog,m.date))return;
    const entry=SWCArchive.partition(catalog,m.date);
    if(current.full&&(!m.capabilities?.weather||!m.capabilities?.reports||!m.capabilities?.hazards)){fail(Error("The full July modules did not initialize. Reload this month; no sample data were substituted."));return;}
    for(const [key,value]of Object.entries(m.selection||{}))if(typeof value==="string"&&value)state[key]=value;
    if(entry.viewer!==current.viewer){navigate(m.date);return;}
    current.date=m.date;show(m.date);urlState(m.date);$("archive-error").hidden=true;frame.hidden=false;frame.style.visibility="visible";
    if(Number.isFinite(m.height))frame.style.height=`${Math.min(40000,Math.max(900,Math.ceil(m.height)+6))}px`;
  });
  frame.addEventListener("error",()=>fail(Error("The selected month viewer could not be loaded.")));
  $("archive-year").addEventListener("change",()=>{const m=catalog.months.filter(x=>x.water_year===Number($("archive-year").value)).sort((a,b)=>a.month.localeCompare(b.month)).at(-1);navigate(m.dates.at(-1));});
  $("archive-month").addEventListener("change",()=>{const m=catalog.months.find(x=>x.month===$("archive-month").value);navigate(m.dates.at(-1));});
  $("archive-date").addEventListener("change",()=>navigate($("archive-date").value));
  $("archive-previous").addEventListener("click",()=>navigate(shift(current.date,-1)));
  $("archive-next").addEventListener("click",()=>navigate(shift(current.date,1)));
  $("archive-latest").addEventListener("click",()=>navigate(catalog.latest));
  (async()=>{try {
    const r=await fetch("archive-catalog.json",{cache:"no-store"});if(!r.ok)throw Error(`Archive catalog unavailable (${r.status}).`);
    catalog=SWCArchive.validate(await r.json());if(catalog.archive_integration_pilot!==true)throw Error("Wrong archive catalog.");
    const q=new URL(location.href).searchParams;for(const key of ["region","variable","view","compare","weatherPeriod","timing","eventWindow"])if(q.has(key))state[key]=q.get(key);
    navigate(q.get("date")||catalog.latest);
  }catch(e){fail(e);}})();
})();
