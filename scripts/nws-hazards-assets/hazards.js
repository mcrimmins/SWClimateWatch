/* Retrospective, isolated WWA pilot. Remote strings are always textContent. */
(() => {
  'use strict';
  const $=id=>document.getElementById(id),node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
  const geometryCache=new Map(),bundleCache=new Map();
  const embedded=new URLSearchParams(location.search).get('embedded')==='1';
  let pendingSelection=null;
  if(embedded)document.body.classList.add('hazard-embedded');
  const sendControl=()=>{if(embedded)parent.postMessage({type:'swc:hazard-control',date:$('date').value,region:$('region').value,
    days:Number($('window').value),timing:$('timing').value},location.origin);};
  function applySelection(s){
    if(!data){pendingSelection=s;return;}
    $('date').value=s.date;$('region').value=s.region;$('window').value=String(s.days);$('timing').value=s.timing;
    if(s.min)$('date').min=s.min;if(s.max)$('date').max=s.max;
    render(true);
  }
  if(embedded){
    window.addEventListener('message',e=>{
      if(e.source!==parent||e.origin!==location.origin||e.data?.type!=='swc:hazard-selection')return;
      const s=e.data;if(!/^\d{4}-\d{2}-\d{2}$/.test(s.date)||!['AZNM','AZ','NM'].includes(s.region)||![1,7,30].includes(s.days)||!['prism','utc'].includes(s.timing))return;
      applySelection(s);
    });
    new ResizeObserver(()=>parent.postMessage({type:'swc:hazard-height',height:Math.ceil(document.querySelector('main').getBoundingClientRect().height)+24},location.origin)).observe(document.querySelector('main'));
  }
  let catalog,data,currentCase,filtered=[],layers=[],selected=null,page=0,epoch=0,failedGeometry=0,windowUnavailable=false;
  const size=30,map=L.map('map',{scrollWheelZoom:false}).setView([34.5,-109],6),layer=L.layerGroup().addTo(map);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:18,attribution:'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors | NWS / IEM'}).addTo(map);
  const fmt=s=>new Date(s).toLocaleString('en-US',{month:'short',day:'numeric',year:'numeric',hour:'2-digit',minute:'2-digit',timeZone:'UTC',hour12:false})+' UTC';
  const interval=e=>`${fmt(new Date(Math.min(...e.segments.map(s=>Date.parse(s.start)))).toISOString())} – ${fmt(new Date(Math.max(...e.segments.map(s=>Date.parse(s.end)))).toISOString())}`;
  function clearDetail(){selected=null;$('detail').replaceChildren(node('h2','Selected hazard'),node('p','Select a mapped area or table row. Overlapping hazards can be selected individually from the table.'));}
  function select(e,geometryId=null){
    selected=e.id;$('hover').hidden=true;
    const shown=geometryId?{...e,segments:e.segments.filter(s=>s.geometry===geometryId)}:e;
    const clear=node('button','Clear selection');clear.addEventListener('click',()=>{clearDetail();styleLayers();renderTable();});
    $('detail').replaceChildren(node('h2',e.title),node('p',`NWS ${e.wfo} · ${e.states.join(', ')}`),node('p',interval(shown)));
    const history=`https://mesonet.agron.iastate.edu/vtec/#${e.year}-O-NEW-K${e.wfo}-${e.phenomenon}-${e.significance}-${String(e.etn).padStart(4,'0')}`;
    const products=[...new Set(shown.segments.map(s=>s.product).filter(p=>/^\d{12}-[A-Z0-9-]+$/.test(p)))].sort();
    const window=HazardModel.windowFor($('date').value,Number($('window').value),$('timing').value,data.start);
    const stamp=p=>Date.parse(`${p.slice(0,4)}-${p.slice(4,6)}-${p.slice(6,8)}T${p.slice(8,10)}:${p.slice(10,12)}:00Z`);
    const primary=HazardModel.bulletinChoice(shown.segments,window.end);
    const actions=node('div');actions.className='hazard-detail-actions';
    const a=node('a',primary?'Read NWS bulletin: details and impacts ↗':'Read NWS event history and bulletins ↗');a.className='hazard-primary-link';
    a.href=primary?`https://mesonet.agron.iastate.edu/p.php?pid=${encodeURIComponent(primary)}`:history;a.target='_blank';a.rel='noopener';actions.append(a,clear);$('detail').append(actions);
    $('detail').append(node('p',primary?`Original NWS bulletin issued ${fmt(new Date(stamp(primary)).toISOString())} · opens IEM in a new tab.`:'Opens the source archive in a new tab.'));
    const rows=HazardModel.structuredDetails(shown.segments);
    if(rows.length){
      $('detail').append(node('h3','Available hazard details'));
      const dl=node('dl');dl.className='hazard-structured-details';
      for(const [label,value]of rows)dl.append(node('dt',label),node('dd',value));$('detail').append(dl);
      $('detail').append(node('p',`${geometryId?'Details for the selected map area':'Details for the matching event areas'} and window. Tags describe NWS hazard information, not measured damage.${shown.segments.length>1?' Values can vary across matching updates.':''}`));
    }else $('detail').append(node('p','No additional structured details were supplied. Read the NWS bulletin for impacts, affected places and instructions.'));
    const metadata=node('details');metadata.className='hazard-archive-metadata';metadata.append(node('summary','Archive metadata'));
    metadata.append(node('p',`${e.id} · ${e.geometry_type}`),node('p',`Archive statuses: ${[...new Set(shown.segments.map(s=>s.status))].join(', ')}. These can reflect later lifecycle updates, not live status.`));
    const zones=[...new Set(shown.segments.map(s=>s.zone).filter(Boolean))];if(zones.length)metadata.append(node('p',`Matching zones/counties: ${zones.join(', ')}`));
    const source=node('a','Open full source event history ↗');source.href=history;source.target='_blank';source.rel='noopener';metadata.append(source);
    if(products.length){const list=node('ul');metadata.append(node('h3','Matching archived bulletins'),list);for(const p of products){const li=node('li'),link=node('a',p);link.href=`https://mesonet.agron.iastate.edu/p.php?pid=${encodeURIComponent(p)}`;link.target='_blank';link.rel='noopener';li.append(link);list.append(li);}}
    $('detail').append(metadata);
    styleLayers();renderTable();
  }
  function styleLayers(){for(const item of layers)item.layer.setStyle({weight:item.event.id===selected?4:1.3,fillOpacity:item.event.id===selected?.3:.17});}
  function colorKey(button,event){button.classList.add('hazard-key');button.style.setProperty('--hazard-color',HazardModel.appearance(event).color);}
  function resetTypes(){$('type').value='all';$('kind').value='all';render();}
  function renderTable(){
    page=Math.max(0,Math.min(page,Math.max(0,Math.ceil(filtered.length/size)-1)));$('rows').replaceChildren();
    for(const e of filtered.slice(page*size,(page+1)*size)){
      const row=node('tr');if(e.id===selected)row.className='selected';
      const cell=node('td'),button=node('button',e.title);colorKey(button,e);button.addEventListener('click',()=>select(e));cell.append(button);
      row.append(cell,node('td',`${e.wfo} · ${e.id}`),node('td',interval(e)),node('td',e.geometry_type));$('rows').append(row);
    }
    $('table-status').textContent=`${filtered.length} unique matching events. Intervals below span the selected matching pieces; separate revisions or zones may have gaps.`;
    $('page').textContent=filtered.length?`${page*size+1}–${Math.min(filtered.length,(page+1)*size)} of ${filtered.length}`:'No matching events';
    $('page-previous').disabled=page===0;$('page-next').disabled=(page+1)*size>=filtered.length;
  }
  function inView(){
    if(windowUnavailable){$('counts').textContent='Hazard data unavailable';$('types').replaceChildren();$('render-status').textContent='This window is outside the fetched archive coverage; it is not a zero-hazard day.';return;}
    const bounds=map.getBounds(),visible=new Map();
    for(const item of layers)if(bounds.intersects(item.layer.getBounds()))visible.set(item.event.id,item.event);
    $('counts').textContent=`${visible.size} events with mapped bounds in view · ${filtered.length} matching events overall`;
    $('types').replaceChildren();const types=new Map();for(const e of visible.values()){const item=types.get(e.title)||{count:0,event:e};item.count++;types.set(e.title,item);}
    for(const [type,item]of [...types].sort((a,b)=>b[1].count-a[1].count)){const b=node('button',`${type} · ${item.count}`);colorKey(b,item.event);b.setAttribute('aria-pressed',String($('type').value===type));b.addEventListener('click',()=>{$('type').value=type;render();});$('types').append(b);}
    const noGeometry=filtered.filter(e=>!e.segments.some(s=>s.geometry)).length;
    $('render-status').textContent=`${noGeometry} events without mapped geometry.${failedGeometry?` ${failedGeometry} geometry files unavailable; table and counts may exceed the mapped data. Change a filter to retry.`:''} Counts in view use bounding-box intersection.`;
  }
  async function loadGeometry(id){
    if(!/^[a-f0-9]{64}$/.test(id))throw Error('Invalid geometry reference');
    if(geometryCache.has(id))return {geometry:geometryCache.get(id),requests:0,bytes:0};
    const path=data.geometry_bundles[id[0]];
    if(!/^bundles\/[a-f0-9]{64}\.json$/.test(path))throw Error('Missing geometry bundle');
    const cold=!bundleCache.has(path);
    if(cold)bundleCache.set(path,fetch(path).then(async r=>{if(!r.ok)throw Error(`Geometry HTTP ${r.status}`);const text=await r.text(),pool=JSON.parse(text);for(const [key,g]of Object.entries(pool)){if(!/^[a-f0-9]{64}$/.test(key)||!['Polygon','MultiPolygon'].includes(g.type)||!Array.isArray(g.coordinates))throw Error('Invalid geometry');geometryCache.set(key,g);}return new TextEncoder().encode(text).length;}).catch(e=>{bundleCache.delete(path);throw e;}));
    const bytes=await bundleCache.get(path);
    if(!geometryCache.has(id))throw Error('Geometry absent from bundle');
    return {geometry:geometryCache.get(id),requests:cold?1:0,bytes:cold?bytes:0};
  }
  async function render(fromParent=false){
    if(!data)return;const token=++epoch,started=performance.now();
    if(embedded&&fromParent!==true)sendControl();
    const allTypes=$('type').value==='all'&&$('kind').value==='all';
    $('view-reset-types').disabled=allTypes;$('reset-types').disabled=allTypes;
    const window=HazardModel.windowFor($('date').value,Number($('window').value),$('timing').value,data.start);
    windowUnavailable=window.end<=Date.parse(data.start+'T00:00:00Z')||window.start>=Date.parse(data.end_exclusive+'T00:00:00Z');
    filtered=HazardModel.select(data.events,window,{region:$('region').value,kind:$('kind').value,type:$('type').value,search:$('search').value,mode:$('mode').value});
    if(windowUnavailable)filtered=[];
    if(selected&&!filtered.some(e=>e.id===selected))clearDetail();
    $('previous').disabled=$('date').value<=$('date').min;$('next').disabled=$('date').value>=$('date').max;
    $('status').textContent=`${fmt(new Date(window.start).toISOString())} – ${fmt(new Date(window.end).toISOString())} · ${filtered.length} events.${window.truncated?' PARTIAL WINDOW: dates before this review period were not fetched.':''} Loading matching geometry…`;
    page=0;renderTable();layer.clearLayers();layers=[];failedGeometry=0;$('hover').hidden=true;
    const jobs=[];const seen=new Set();
    for(const e of filtered)for(const s of e.segments)if(s.geometry&&!seen.has(`${e.id}:${s.geometry}`)){seen.add(`${e.id}:${s.geometry}`);jobs.push({event:e,id:s.geometry});}
    let index=0,requests=0,bytes=0;
    const worker=async()=>{while(index<jobs.length){const job=jobs[index++];if(token!==epoch)return;
      try{const loaded=await loadGeometry(job.id),g=loaded.geometry;if(token!==epoch)return;requests+=loaded.requests;bytes+=loaded.bytes;
        const shape=L.geoJSON(g,{style:{...HazardModel.appearance(job.event),weight:1.3,fillOpacity:.17}}).addTo(layer);
        shape.on('mouseover',()=>{const box=$('hover');box.replaceChildren(node('strong',job.event.title),node('div',`${job.event.wfo} · ${job.event.geometry_type}`),node('div','Click to select; use the table for overlapping hazards.'));box.hidden=false;});
        shape.on('mouseout',()=>{$('hover').hidden=true;});shape.on('click',()=>select(job.event,job.id));layers.push({layer:shape,event:job.event});
      }catch(e){failedGeometry++;}
    }};
    await Promise.all(Array.from({length:Math.min(6,jobs.length)},worker));if(token!==epoch)return;
    $('status').textContent=`${fmt(new Date(window.start).toISOString())} – ${fmt(new Date(window.end).toISOString())} · ${filtered.length} unique events.${window.truncated?' PARTIAL WINDOW: begins before the review-period coverage.':''}${failedGeometry?' Some map geometry unavailable; see the table.':' Archived data loaded.'}`;
    if(windowUnavailable)$('status').textContent='Hazard data unavailable for this window; no other date was substituted.';
    styleLayers();inView();
    $('performance').textContent=`Last selection: ${Math.round(performance.now()-started)} ms to filter/load/draw; ${requests} uncached geometry bundles, approximately ${(bytes/1024).toFixed(0)} KB decoded JSON; ${layers.length} displayed pieces. Browser geometry cache: ${geometryCache.size} shapes.`;
  }
  async function loadCase(){
    const token=++epoch;data=null;filtered=[];layer.clearLayers();layers=[];clearDetail();$('rows').replaceChildren();$('counts').textContent='Loading review period…';$('types').replaceChildren();$('status').textContent='Loading review period…';
    currentCase=catalog.cases.find(c=>c.id===$('case').value);
    try{
      const r=await fetch(currentCase.path);if(!r.ok)throw Error(`Case HTTP ${r.status}`);const x=await r.json();if(token!==epoch)return;
      if(x.schema_version!==1||!Array.isArray(x.events)||x.events.some(e=>!Array.isArray(e.segments)||!Array.isArray(e.states)))throw Error('Invalid event metadata');
      data=x;$('date').min=x.start;$('date').max=new Date(Date.parse(x.end_exclusive+'T00:00:00Z')-86400000).toISOString().slice(0,10);$('date').value=$('date').max;
      $('type').replaceChildren(new Option('All types','all'),...[...new Set(x.events.map(e=>e.title))].sort().map(t=>new Option(t,t)));$('kind').value='all';
      const w=catalog.workload.find(w=>w.case===currentCase.id);
      $('workload').textContent=`${w.events} unique events; ${w.raw_rows} source rows; ${w.unique_geometries} unique display geometries. Cached archive ${(w.archive_bytes/1048576).toFixed(2)} MB; metadata ${(w.metadata_bytes/1024).toFixed(0)} KB (${(w.metadata_gzip_bytes/1024).toFixed(0)} KB gzip estimate); all geometry ${(w.geometry_bytes/1048576).toFixed(2)} MB. Build: ${w.requests} downloads, ${w.cached_requests} cached responses; processing ${w.process_seconds.toFixed(2)} s, total ${w.total_seconds.toFixed(2)} s. These are the most recent build's measurements.`;
      if(embedded){parent.postMessage({type:'swc:hazard-ready'},location.origin);if(pendingSelection){applySelection(pendingSelection);pendingSelection=null;}}
      else await render();
    }catch(e){if(token!==epoch)return;$('status').textContent=`Review data unavailable: ${e.message}. This does not mean no hazards occurred.`;$('counts').textContent='Data unavailable';}
  }
  map.on('moveend',inView);
  for(const id of ['date','window','timing','region','kind','type','mode'])$(id).addEventListener('change',render);
  $('search').addEventListener('input',render);$('case').addEventListener('change',loadCase);
  for(const [id,delta]of [['previous',-1],['next',1]])$(id).addEventListener('click',()=>{const value=new Date(Date.parse($('date').value+'T00:00:00Z')+delta*86400000).toISOString().slice(0,10);if(value>=$('date').min&&value<=$('date').max){$('date').value=value;render();}});
  $('reset-types').addEventListener('click',resetTypes);
  $('view-reset-types').addEventListener('click',resetTypes);
  $('reset-map').addEventListener('click',()=>map.setView([34.5,-109],6));
  $('page-previous').addEventListener('click',()=>{page--;renderTable();});$('page-next').addEventListener('click',()=>{page++;renderTable();});
  fetch('catalog.json',{cache:'no-store'}).then(async r=>{if(!r.ok)throw Error(`Catalog HTTP ${r.status}`);catalog=await r.json();if(catalog.pilot!==true||!Array.isArray(catalog.cases))throw Error('Invalid pilot catalog');$('case').replaceChildren(...catalog.cases.map(c=>new Option(c.label,c.id)));await loadCase();}).catch(e=>{$('status').textContent=`Hazard catalog unavailable: ${e.message}`;});
})();
