/* Local selected-station pilot: lazy annual files, bounded cache, worker statistics. */
(() => {
  'use strict';
  const M = StationCustomModel, $ = id => document.getElementById(id);
  const format = date => new Intl.DateTimeFormat('en-US', {month:'short', day:'numeric', year:'numeric', timeZone:'UTC'}).format(new Date(date + 'T00:00:00Z'));
  const number = (value, digits=1) => value == null ? 'Unavailable' : value.toLocaleString('en-US', {minimumFractionDigits:digits, maximumFractionDigits:digits});
  const role = value => value==='fixed'?'Station':value==='threadex_comparison'?'ThreadEx comparison':value;
  const parameters=new URLSearchParams(location.search), embedded=parameters.get('embedded')==='1', requestedUid=parameters.get('uid');
  if(embedded)document.body.classList.add('embedded');
  function parentMessage(value) {
    if(embedded&&window.parent!==window&&requestedUid)window.parent.postMessage({...value,uid:requestedUid},location.origin);
  }
  if(embedded&&typeof ResizeObserver!=='undefined')new ResizeObserver(()=>{
    parentMessage({type:'swc-station-history-height',height:Math.ceil(document.querySelector('main').getBoundingClientRect().height+8)});
  }).observe(document.querySelector('main'));
  let index, stations, revision = 0, controller, worker, pending = new Map(), job = 0, active, plotting, selectedInterval = -1, benchmarking = false;
  const cache = new Map();
  let exportUrl;
  function clearExport() {
    if(exportUrl)URL.revokeObjectURL(exportUrl);exportUrl=null;
    $('csv-ready').hidden=true;$('csv-ready').href='';$('csv-status').textContent='';
  }
  function status(text, error=false) { $('status').textContent = text; $('status').classList.toggle('error', error); }
  function resetWorker() {
    if (worker) worker.terminate();
    for (const promise of pending.values()) promise.reject(new DOMException('Cancelled', 'AbortError'));
    pending.clear(); worker = new Worker('worker.js');
    worker.onmessage = ({data}) => {
      const promise = pending.get(data.id); if (!promise) return;
      pending.delete(data.id); data.error ? promise.reject(Error(data.error)) : promise.resolve(data);
    };
    worker.onerror = event => {for (const p of pending.values()) p.reject(Error(event.message)); pending.clear();};
    active = null;
  }
  function work(data) {
    const id = ++job;
    return new Promise((resolve, reject) => {pending.set(id, {resolve, reject}); worker.postMessage({...data, id});});
  }
  function cancel() {
    clearExport();
    revision++; if (controller) controller.abort(); resetWorker();
    benchmarking = false; $('cancel').disabled = true; $('download').disabled = true;
  }
  async function json(path, signal) {
    const response = await fetch(path, {signal, cache:path==='catalog.json'?'no-store':'default'});
    if (!response.ok) throw Error('History file unavailable (' + response.status + ').');
    return response.json();
  }
  function remember(path, data) {
    cache.delete(path); cache.set(path, data);
    while (cache.size > 24) cache.delete(cache.keys().next().value);
  }
  async function stationChanged() {
    cancel(); cache.clear(); index=null; $('results').hidden = true; $('coverage').textContent='Loading station coverage…';
    $('metrics').textContent=''; $('bench-results').textContent='';
    const mine = revision; controller = new AbortController();
    const selected = stations.find(s => String(s.uid) === $('station').value);
    status('Loading this station’s history index…');
    try {
      const value = await json(selected.index, controller.signal);
      if (mine !== revision) return;
      if (String(value.uid) !== String(selected.uid) || !Array.isArray(value.years)) throw Error('Station index mismatch.');
      index = {...value, source_index:selected.index};
      for (const id of ['start','end']) {$(id).min=index.first; $(id).max=index.last;}
      $('end').value=index.last; $('start').value=M.iso(Math.max(M.day(index.first), M.day(index.last)-29));
      $('coverage').textContent = `${index.name} · ${index.state} · ${role(index.role)} · Cached dates ${format(index.first)}–${format(index.last)}. Missing/flagged days remain unavailable. Cache through ${format(index.cutoff)}.`;
      status('Choose dates and select Show period. No annual history files have been requested.');
      if(embedded)await apply();
    } catch (e) {if(e.name!=='AbortError' && mine===revision) status(e.message,true);}
  }
  function bounds() {
    if (!index) throw Error('Wait for the station index to load.');
    const start=$('start').value, end=$('end').value;
    if (M.day(start)>M.day(end)) throw Error('Start date must be on or before end date.');
    if (start<index.first || end>index.last) throw Error('Choose dates within this station’s cached record.');
    return {start,end};
  }
  async function run({start,end}, cold=false) {
    if (!index) throw Error('Select a station first.');
    const snapshot=index, key=[index.uid,index.source_index,start,end].join('/');
    if (cold) {cache.clear(); resetWorker();}
    const mine=++revision; if(controller) controller.abort(); controller=new AbortController();
    const signal=controller.signal, started=performance.now();
    clearExport();
    $('cancel').disabled=false; $('download').disabled=true;
    let files=0, bytes=0, hits=0, result, reusedResult=false;
    if (active && active.key===key) {result=active.result;reusedResult=true;}
    else {
      const needed=snapshot.years.filter(y=>y.end>=start && y.start<=end), chunks=new Array(needed.length);
      let next=0, complete=0;
      async function lane() {
        while(next<needed.length) {
          const i=next++, row=needed[i];
          if(cache.has(row.file)) {chunks[i]=cache.get(row.file); remember(row.file,chunks[i]); hits++;}
          else {
            const data=M.decode(await json(row.file,signal),snapshot.uid);
            if(data.start!==row.start || data.end!==row.end || data.year!==row.year) throw Error('Annual history dates do not match the station index.');
            if(mine!==revision) throw new DOMException('Cancelled','AbortError');
            chunks[i]=data; remember(row.file,data); files++; bytes+=row.bytes;
          }
          complete++; status(`Loading ${snapshot.name}: ${complete}/${needed.length} annual files ready…`);
        }
      }
      await Promise.all(Array.from({length:Math.min(4,needed.length)},()=>lane()));
      if(mine!==revision) throw new DOMException('Cancelled','AbortError');
      result=await work({type:'compute',chunks,start,end,station:{uid:snapshot.uid,sid:snapshot.sid,name:snapshot.name}});
      if(mine!==revision) throw new DOMException('Cancelled','AbortError');
      active={key,result};
    }
    const renderStart=performance.now(); render(result);
    const report={days:result.summary.days, annual_files_fetched:files, application_cache_hits:hits,
      requested_bytes:bytes, worker_compute_ms:reusedResult?0:Math.round(result.compute_ms*10)/10, result_reused:reusedResult,
      render_ms:Math.round((performance.now()-renderStart)*10)/10, elapsed_ms:Math.round((performance.now()-started)*10)/10,
      cached_years:cache.size, plotted_intervals:result.bins.values.length};
    $('metrics').textContent=JSON.stringify(report,null,2);
    status(`${format(start)}–${format(end)} · ${result.summary.days.toLocaleString()} days. Data through ${format(snapshot.cutoff)}.`);
    parentMessage({type:'swc-station-history-selection',start,end,cutoff:snapshot.cutoff});
    $('cancel').disabled=true; $('download').disabled=false;
    return report;
  }
  function dates(list) {return list.length ? list.slice(0,3).map(format).join('; ')+(list.length>3?` (+${list.length-3} ties)`:''):'Unavailable';}
  function render(result) {
    const s=result.summary;
    $('results').hidden=false; $('period').textContent=`${format(s.start)}–${format(s.end)}`;
    $('summary').replaceChildren();
    const cards=[
      [s.p.complete?'Precipitation total':'Observed precipitation subtotal',number(s.p.value,2)+(s.p.value==null?'':' in.'),`${s.p.valid}/${s.days} eligible days · ${s.p.missing} missing · ${s.p.flagged} flagged · ${s.p.trace} trace`],
      ['Mean temperature',number(s.t.mean)+(s.t.mean==null?'':' °F'),`${s.t.paired}/${s.days} paired days · ${s.t.missing} missing · ${s.t.flagged} flagged${s.t.complete?'':' · INCOMPLETE'}`],
      ['Period length',s.days.toLocaleString()+' days','Inclusive start and end dates'],
      ['Temperature coverage',number(100*s.t.paired/s.days,1)+'%','Mean uses only eligible high/low pairs']
    ];
    for(const [label,value,note] of cards) {const card=document.createElement('div');card.className='card';
      for(const [tag,text] of [['span',label],['strong',value],['small',note]]) {const el=document.createElement(tag);el.textContent=text;card.append(el);} $('summary').append(card);}
    $('extremes').replaceChildren();
    for(const cells of [['Wettest eligible day',number(s.p.max,2)+(s.p.max==null?'':' in.'),dates(s.p.dates)],
      ['Highest eligible temperature',number(s.t.high)+(s.t.high==null?'':' °F'),dates(s.t.highDates)],
      ['Lowest eligible temperature',number(s.t.low)+(s.t.low==null?'':' °F'),dates(s.t.lowDates)]]) {
      const tr=document.createElement('tr');for(const text of cells){const td=document.createElement('td');td.textContent=text;tr.append(td);} $('extremes').append(tr);}
    plotting=result.bins;
    $('precip-title').textContent=plotting.step===1?'Daily precipitation (inches)':`Observed precipitation totals (~${plotting.step}-day groups, inches)`;
    $('temp-title').textContent=plotting.step===1?'Daily high and low temperature (°F)':`Average high and low (~${plotting.step}-day groups, °F)`;
    $('plot-note').textContent=plotting.step===1?'Daily observations; gaps mean unavailable. Orange outlines mark incomplete precipitation groups.':`${plotting.values.length} displayed intervals; incomplete precipitation groups have orange outlines. All statistics and CSV rows retain daily resolution.`;
    selectedInterval=-1;
    for(const id of ['precip','temp']) {
      $(id+'-previous').textContent=plotting.step===1?'← Previous day':'← Previous interval';
      $(id+'-next').textContent=plotting.step===1?'Next day →':'Next interval →';
    }
    selectInterval(0);
  }
  function draw(id, precipitation) {
    if(!plotting) return;
    const canvas=$(id), ctx=canvas.getContext('2d'), rect=canvas.getBoundingClientRect();
    const width=rect.width||1000,height=rect.height||220,left=42,right=12,top=15,bottom=30;
    const ratio=Math.min(2,window.devicePixelRatio||1);
    canvas.width=Math.round(width*ratio);canvas.height=Math.round(height*ratio);ctx.setTransform(ratio,0,0,ratio,0,0);
    ctx.clearRect(0,0,width,height);
    const data=plotting.values, values=precipitation?data.map(b=>b.p.value):data.flatMap(b=>[b.high,b.low]);
    const finite=values.filter(v=>v!=null);
    let lo=precipitation?0:Math.floor(((finite.length?Math.min(...finite):0)-5)/10)*10, hi=precipitation?Math.max(...finite,0.1)*1.1:Math.ceil(((finite.length?Math.max(...finite):0)+5)/10)*10;
    const x=i=>left+(i+0.5)*(width-left-right)/data.length, y=v=>height-bottom-(v-lo)/(hi-lo)*(height-top-bottom);
    if(selectedInterval>=0) {
      const band=(width-left-right)/data.length;
      ctx.fillStyle='#dcebef';ctx.fillRect(x(selectedInterval)-Math.max(band,4)/2,top,Math.max(band,4),height-top-bottom);
    }
    ctx.font='11px system-ui';ctx.fillStyle='#536d7b';ctx.strokeStyle='#dde5e9';
    for(let i=0;i<4;i++){const v=lo+(hi-lo)*i/3;ctx.beginPath();ctx.moveTo(left,y(v));ctx.lineTo(width-right,y(v));ctx.stroke();ctx.fillText(v.toFixed(precipitation?1:0),3,y(v)+5);}
    if(precipitation) {
      const bar=Math.max(1,(width-left-right)/data.length*.85);
      data.forEach((b,i)=>{if(b.p.value==null)return;ctx.fillStyle='#2d83a2';ctx.fillRect(x(i)-bar/2,y(b.p.value),bar,y(0)-y(b.p.value));
        if(!b.p.complete){ctx.strokeStyle='#bd542c';ctx.strokeRect(x(i)-bar/2,y(b.p.value),bar,Math.max(2,y(0)-y(b.p.value)));}});
    } else for(const [field,color] of [['high','#bd542c'],['low','#2868ad']]) {
      ctx.strokeStyle=color;ctx.lineWidth=2.5;ctx.beginPath();let connected=false;
      data.forEach((b,i)=>{if(b[field]==null){connected=false;return;} if(connected)ctx.lineTo(x(i),y(b[field]));else ctx.moveTo(x(i),y(b[field]));connected=true;});ctx.stroke();}
    ctx.fillStyle='#536d7b';ctx.fillText(format(data[0].start),left,height-7);ctx.textAlign='right';ctx.fillText(format(data[data.length-1].end),width-right,height-7);ctx.textAlign='left';
  }
  function table(target,title,columns,rows,note) {
    const box=$(target);box.replaceChildren();
    const heading=document.createElement('p');heading.className='selection-date';heading.textContent=title;box.append(heading);
    const grid=document.createElement('table'),caption=document.createElement('caption');caption.className='visually-hidden';caption.textContent=target==='precip-selection'?'Selected precipitation values':'Selected temperature values';grid.append(caption);
    const head=document.createElement('thead'),tr=document.createElement('tr');
    for(const value of columns){const th=document.createElement('th');th.scope='col';th.textContent=value;tr.append(th);}head.append(tr);grid.append(head);
    const body=document.createElement('tbody');
    for(const values of rows){const row=document.createElement('tr');values.forEach((value,i)=>{const cell=document.createElement(i===0?'th':'td');if(i===0)cell.scope='row';cell.textContent=value;row.append(cell);});body.append(row);}grid.append(body);box.append(grid);
    const text=document.createElement('p');text.className='selection-note';text.textContent=note;box.append(text);
  }
  function selectInterval(value) {
    if(!plotting?.values.length)return;
    const i=Math.max(0,Math.min(plotting.values.length-1,value));if(i===selectedInterval)return;selectedInterval=i;
    const b=plotting.values[i],daily=b.days===1,title=daily?format(b.start):`${format(b.start)}–${format(b.end)} · ${b.days} days`;
    const amount=b.p.value==null?'Unavailable':`${number(b.p.value,2)} in.${daily&&b.p.trace?' · Trace':''}`;
    table('precip-selection',title,['Precipitation','Amount'],[
      [daily?'Observed':b.p.complete?'Interval total':'Observed subtotal',amount],
      ['Eligible days',`${b.p.valid} / ${b.days}`],
      ['Missing / flagged days',`${b.p.missing} / ${b.p.flagged}`],
      ['Trace days',String(b.p.trace)]
    ],b.p.complete?'Complete precipitation coverage.': 'Incomplete coverage: missing and flagged observations are excluded.');
    table('temp-selection',title,['Temperature','High','Low'],[
      [daily?'Observed':'Interval average',b.high==null?'Unavailable':`${number(b.high)} °F`,b.low==null?'Unavailable':`${number(b.low)} °F`],
      ['Eligible paired days',`${b.t.paired} / ${b.days}`,`${b.t.paired} / ${b.days}`]
    ],`${b.t.missing} missing-pair days · ${b.t.flagged} flagged-pair days. ${daily?'Values require an eligible high/low pair.':'Averages use eligible paired days only; these are not interval extremes.'}`);
    for(const id of ['precip','temp']) {$(id+'-previous').disabled=i===0;$(id+'-next').disabled=i===plotting.values.length-1;}
    draw('precip',true);draw('temp',false);
  }
  for(const id of ['precip','temp']) {
    const selectPointer=event=>{
      if(!plotting)return;const rect=$(id).getBoundingClientRect();
      selectInterval(Math.floor((event.clientX-rect.left-42)/(rect.width-54)*plotting.values.length));
    };
    $(id).addEventListener('pointermove',event=>{if(event.pointerType!=='touch')selectPointer(event);});
    $(id).addEventListener('click',selectPointer);
    $(id).addEventListener('keydown',event=>{
      if(!plotting||!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;event.preventDefault();
      selectInterval(event.key==='Home'?0:event.key==='End'?plotting.values.length-1:selectedInterval+(event.key==='ArrowLeft'?-1:1));
    });
    $(id+'-previous').addEventListener('click',()=>selectInterval(selectedInterval-1));
    $(id+'-next').addEventListener('click',()=>selectInterval(selectedInterval+1));
  }
  window.addEventListener('resize',()=>{draw('precip',true);draw('temp',false);});
  async function apply() {try{await run(bounds());}catch(e){if(e.name!=='AbortError') {if(controller)controller.abort();status(e.message,true);$('cancel').disabled=true;}}}
  $('station').addEventListener('change',stationChanged);$('apply').addEventListener('click',apply);
  for(const id of ['start','end']) $(id).addEventListener('change',()=>{cancel();$('results').hidden=true;status('Dates changed. Select Show period to update the results.');});
  $('cancel').addEventListener('click',()=>{cancel();status('Loading cancelled. Choose a period to continue.');});
  window.addEventListener('message',event=>{
    if(!embedded||event.origin!==location.origin||event.source!==window.parent||String(event.data?.uid)!==String(requestedUid))return;
    if(event.data.type==='swc-station-history-pause'&&!$('cancel').disabled){cancel();status('History loading paused while Current conditions is shown. Select Show period to continue.');}
  });
  window.addEventListener('pagehide',()=>{if(controller)controller.abort();worker?.terminate();if(exportUrl)URL.revokeObjectURL(exportUrl);});
  for(const button of document.querySelectorAll('[data-days]')) button.addEventListener('click',()=>{
    if(!index)return;$('end').value=index.last;$('start').value=M.iso(Math.max(M.day(index.first),M.day(index.last)-Number(button.dataset.days)+1));apply();});
  $('full').addEventListener('click',()=>{if(index){$('start').value=index.first;$('end').value=index.last;apply();}});
  $('download').addEventListener('click',async()=>{
    if(!active)return;
    const mine=revision,key=active.key,uid=index.uid,summary=active.result.summary;
    clearExport();$('download').disabled=true;$('csv-status').textContent='Preparing daily CSV…';
    try {
      const data=await work({type:'csv'});
      if(mine!==revision||active?.key!==key)return;
      exportUrl=URL.createObjectURL(new Blob([data.csv],{type:'text/csv;charset=utf-8'}));
      const a=$('csv-ready');a.href=exportUrl;a.download=`station-${uid}-${summary.start}-to-${summary.end}.csv`;
      a.textContent='Save prepared CSV';a.hidden=false;
      $('csv-status').textContent=`CSV ready: ${summary.days.toLocaleString()} daily rows · ${format(summary.start)}–${format(summary.end)}. If the download did not start, use Save prepared CSV.`;
      a.click();
    }catch(e){if(mine===revision)$('csv-status').textContent='CSV export failed: '+e.message;}
    finally{if(mine===revision)$('download').disabled=!active;}
  });
  $('benchmark').addEventListener('click',async()=>{
    if(!index||benchmarking)return;benchmarking=true;$('bench-results').textContent='Measuring selected-station cases…';
    const results=[];try {
      for(const [label,n] of [['7 days',7],['365 days',365],['10 years',3653],['Full record',Infinity]]) {
        if(!benchmarking)break;const start=M.iso(Math.max(M.day(index.first),M.day(index.last)-n+1)),end=index.last;
        $('start').value=start;$('end').value=end;
        const cold=await run({start,end},true),warm=await run({start,end});results.push({label,application_cold:cold,repeat:warm});
      }
      $('bench-results').textContent='Application cache cleared per case; the browser HTTP cache may still respond.\n'+JSON.stringify(results,null,2);
      window.stationCustomBenchmark=results;
    }catch(e){if(e.name!=='AbortError')status(e.message,true);} finally{benchmarking=false;}
  });
  resetWorker();
  json('catalog.json').then(value=>{
    if(value.schema!==1||!Array.isArray(value.stations))throw Error('Invalid station catalog.');
    stations=value.stations;for(const s of stations){const option=document.createElement('option');option.value=s.uid;option.textContent=`${s.name} · ${s.state} · ${role(s.role)}`;$('station').append(option);}
    if(embedded) {
      if(!requestedUid||!stations.some(s=>String(s.uid)===requestedUid))throw Error('Historical observations are unavailable for the selected station. No other station has been substituted.');
      $('station').value=requestedUid;$('station').disabled=true;
    }
    return stationChanged();
  }).catch(e=>status(e.message,true));
})();
