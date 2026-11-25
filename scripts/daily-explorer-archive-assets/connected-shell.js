"use strict";
(()=>{
  const $=id=>document.getElementById(id),frame=$('connected-viewer');
  let catalog,current=null,state={},sequence=0,timeout=null,resizeTimer=null,readyTimer=null,lastHeight=1400,loading=false,failed=false;
  const label=d=>new Date(`${d}T12:00:00Z`).toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric',timeZone:'UTC'});
  const shift=(d,n)=>{const x=new Date(`${d}T12:00:00Z`);x.setUTCDate(x.getUTCDate()+n);return x.toISOString().slice(0,10);};
  const options=(el,rows,value)=>{const signature=JSON.stringify(rows);if(el.dataset.options!==signature){el.replaceChildren(...rows.map(([v,t])=>new Option(t,v)));el.dataset.options=signature;}el.value=value;el.disabled=false;};
  function show(date,scope=current?.scope){
    const m=SWCConnected.partition(catalog,date);if(!m)throw Error('This date is unavailable. No other date has been substituted.');
    const latestYear=SWCConnected.partition(catalog,catalog.latest).water_year;
    const years=[...new Set(catalog.months.map(x=>x.water_year))].sort((a,b)=>b-a);
    options($('connected-year'),years.map(y=>[String(y),`WY${y}${y===latestYear?' · current':catalog.months.some(x=>x.water_year===y&&x.kind==='archive')?' · historic archive':' · retained dates'}`]),String(m.water_year));
    const monthRows=catalog.months.filter(x=>x.water_year===m.water_year).sort((a,b)=>a.month.localeCompare(b.month)).map(x=>[x.month,new Date(`${x.month}-15T12:00:00Z`).toLocaleDateString('en-US',{month:'long',year:'numeric',timeZone:'UTC'})]);
    if(m.kind==='current')monthRows.unshift(['all','All available dates']);
    options($('connected-month'),monthRows,m.kind==='current'&&scope==='all'?'all':m.month);
    $('connected-date').disabled=false;$('connected-date').value=date;
    const dates=catalog.months.flatMap(x=>x.dates).sort();$('connected-date').min=dates[0];$('connected-date').max=dates.at(-1);
    $('connected-previous').disabled=!SWCConnected.partition(catalog,shift(date,-1));$('connected-next').disabled=!SWCConnected.partition(catalog,shift(date,1));
    $('connected-current').disabled=date===catalog.latest&&scope==='all';
    $('connected-status').textContent=`${label(date)} · ${m.kind==='archive'?'Historic archive · PRISM, daily/7-/30-day weather, storm reports and archived NWS hazards.':`Recent cached conditions · latest local date ${label(catalog.latest)}. Available products follow this cache.`}`;
    return m;
  }
  function urlState(date){const u=new URL(location.href);u.searchParams.set('date',date);if(current)u.searchParams.set('month',current.scope);for(const [k,v] of Object.entries(state))u.searchParams.set(k,v);history.replaceState(null,'',u);}
  function sendViewport(){
    if(loading||failed||!current||frame.hidden||typeof frame.getBoundingClientRect!=='function')return;
    const box=frame.getBoundingClientRect(),top=Math.max(0,-box.top-200),bottom=Math.min(box.height,innerHeight-box.top+200);
    if(bottom>=top)frame.contentWindow.postMessage({type:'swc:connected-viewport',token:current.token,top,bottom},location.origin);
  }
  let viewportQueued=false;
  const queueViewport=()=>{if(!viewportQueued){viewportQueued=true;requestAnimationFrame(()=>{viewportQueued=false;sendViewport();});}};
  window.addEventListener('scroll',queueViewport,{passive:true});window.addEventListener('resize',queueViewport);
  function captureSelection(){
    if(!current||loading||failed)return;
    try{
      const d=frame.contentDocument;if(!d)return;const value=id=>d.getElementById(id)?.value;
      const open=id=>d.getElementById(id)?String(d.getElementById(id).open):undefined;
      state={...state,...SWCConnected.selection({region:value('region'),variable:value('variable'),view:value('view'),compare:value('compare'),metric:value('metric'),
        weatherPeriod:value('circulation-period'),timing:value('storm-timing'),eventWindow:value('storm-window'),
        openWeather:open('circulation-panel'),openReports:open('storm-panel'),openHazards:open('hazard-panel')})};
    }catch(_){/* Only the same-origin connected viewer supplies selections. */}
  }
  function fail(message){clearTimeout(timeout);clearTimeout(resizeTimer);clearTimeout(readyTimer);loading=false;failed=true;frame.hidden=true;$('connected-loading').hidden=true;$('connected-viewport').setAttribute('aria-busy','false');$('connected-error').textContent=message;$('connected-error').hidden=false;$('connected-retry').hidden=!current;$('connected-current').disabled=false;}
  function navigate(date,requestedScope){
    try{
      captureSelection();const m=SWCConnected.partition(catalog,date);if(!m)throw Error('This date is unavailable. No other date has been substituted.');
      const scope=m.kind==='current'&&(requestedScope==='all'||(!requestedScope&&(!current||current.kind!=='current'||current.scope==='all')))?'all':m.month;
      show(date,scope);clearTimeout(timeout);clearTimeout(resizeTimer);clearTimeout(readyTimer);
      current={date,viewer:m.viewer,kind:m.kind,scope,token:String(++sequence)};loading=true;failed=false;
      const u=new URL(m.viewer,location.href);u.searchParams.set('date',date);u.searchParams.set('archiveToken',current.token);if(scope!=='all')u.searchParams.set('connectedMonth',m.month);
      for(const [k,v]of Object.entries(state))u.searchParams.set(k,v);
      frame.hidden=false;frame.style.visibility='hidden';frame.style.height=`${lastHeight}px`;
      $('connected-loading').hidden=false;$('connected-error').hidden=true;$('connected-retry').hidden=true;$('connected-viewport').setAttribute('aria-busy','true');
      frame.src=u.href;urlState(date);
      timeout=setTimeout(()=>fail('The selected month did not finish loading. Retry it or return to current conditions; no previous month is being substituted.'),30000);
    }catch(e){current=null;fail(e.message);}
  }
  window.addEventListener('message',event=>{
    const m=event.data;
    if(event.origin!==location.origin||event.source!==frame.contentWindow||m?.type!=='swc:connected-month'||!current||failed||m.token!==current.token)return;
    if(m.error){fail(m.error);return;}
    const entry=SWCConnected.partition(catalog,m.date);if(!entry)return;
    // A hidden, initializing frame cannot make a user date selection. Ignore
    // its default/context dates until it has acknowledged the requested day.
    if(loading&&m.date!==current.date)return;
    if(current.kind==='archive'&&(!m.capabilities?.weather||!m.capabilities?.reports||!m.capabilities?.hazards)){fail('The archive modules did not initialize. Retry this month; no current data have been substituted.');return;}
    const oldState=JSON.stringify(state),oldDate=current.date;
    state={...state,...SWCConnected.selection(m.selection)};
    if(entry.viewer!==current.viewer||(current.scope!=='all'&&entry.month!==current.date.slice(0,7))){navigate(m.date);return;}
    current.date=m.date;if(oldDate!==m.date)show(m.date);if(oldDate!==m.date||oldState!==JSON.stringify(state))urlState(m.date);
    const h=SWCConnected.height(m.height);if(!m.ready||h===null)return;
    const token=current.token;
    const commit=()=>{if(current?.token!==token)return;clearTimeout(timeout);if(Math.abs(h-lastHeight)>=4){lastHeight=h;frame.style.height=`${h}px`;}loading=false;frame.hidden=false;frame.style.visibility='visible';$('connected-loading').hidden=true;$('connected-viewport').setAttribute('aria-busy','false');sendViewport();};
    if(loading){clearTimeout(readyTimer);readyTimer=setTimeout(commit,160);}else{clearTimeout(resizeTimer);resizeTimer=setTimeout(commit,160);}
  });
  frame.addEventListener('error',()=>fail('The selected viewer could not be loaded.'));
  $('connected-year').addEventListener('change',()=>{const months=catalog.months.filter(m=>m.water_year===Number($('connected-year').value)).sort((a,b)=>a.month.localeCompare(b.month));navigate(months.at(-1).dates.at(-1),'all');});
  $('connected-month').addEventListener('change',()=>{const value=$('connected-month').value;const months=catalog.months.filter(m=>m.water_year===Number($('connected-year').value));const m=value==='all'?months.sort((a,b)=>a.month.localeCompare(b.month)).at(-1):months.find(m=>m.month===value);navigate(m.dates.at(-1),value);});
  $('connected-date').addEventListener('change',()=>navigate($('connected-date').value));
  $('connected-previous').addEventListener('click',()=>current&&navigate(shift(current.date,-1)));
  $('connected-next').addEventListener('click',()=>current&&navigate(shift(current.date,1)));
  $('connected-current').addEventListener('click',()=>navigate(catalog.latest,'all'));
  $('connected-retry').addEventListener('click',()=>current&&navigate(current.date));
  (async()=>{try{const r=await fetch('connected-catalog.json',{cache:'no-store'});if(!r.ok)throw Error(`Catalog HTTP ${r.status}`);catalog=SWCConnected.validate(await r.json());const q=new URL(location.href).searchParams;state=SWCConnected.selection(Object.fromEntries(q));navigate(q.get('date')||catalog.latest,q.get('month')||'all');}catch(e){fail(e.message);}})();
})();
