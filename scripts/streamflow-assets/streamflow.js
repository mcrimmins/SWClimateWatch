(async function(){'use strict';
const M=window.StreamflowModel,$=id=>document.getElementById(id),NS='http://www.w3.org/2000/svg';
const state={payload:null,selected:null,rows:[],shown:[],day:0,cache:new Map(),markers:new Map(),token:0};
const text=(tag,value,cls)=>{const e=document.createElement(tag);e.textContent=value;if(cls)e.className=cls;return e;};
const svg=(tag,attrs={})=>{const e=document.createElementNS(NS,tag);for(const[k,v]of Object.entries(attrs))e.setAttribute(k,v);return e;};
const flow=x=>M.valid(x)?M.format(x)+' cfs':'Unavailable';
const fail=e=>{$('error').hidden=false;$('error').textContent=e.message||String(e);};
async function json(path){const r=await fetch(path,{cache:'no-cache'});if(!r.ok)throw Error('Could not load '+path+' ('+r.status+').');return r.json();}
try{
state.payload=await json('streamflow-data.json');const p=state.payload;
const embedded=parent!==window&&new URL(location.href).searchParams.get('embedded')==='1';
const range={start:p.start,end:p.cutoff},originalGauges=p.gauges.slice();
let selectionSequence=0;
if(p.pilot!=='swc-streamflow'||p.parameter!=='00060'||p.statistic!=='00003')throw Error('Unexpected streamflow release.');
$('asof').textContent='Daily observations through '+M.day(p.cutoff)+' · '+M.day(p.start)+'–'+M.day(p.cutoff)+'. Each gauge’s actual observation date is shown.';
const map=L.map('map',{scrollWheelZoom:false}).setView([34.5,-109],6);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:18,attribution:'© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap contributors</a>'}).addTo(map);
for(const [label,color]of Object.entries(M.categoryColors)){const row=text('div','', 'legend-row'),dot=text('span','','dot');dot.style.background=color;row.append(dot,text('span',label));$('legend').append(row);}
const coverage=$('coverage');for(const c of p.coverage){coverage.append(text('p',c.state+': '+c.gauges_with_any_latest_daily+' gauges have an accessible latest daily-flow record; '+c.gauges_reported_in_last_7days+' reported within seven days of the cutoff ('+c.gauges_with_numeric_flow_in_last_7days+' with numeric flow).'));}
coverage.append(text('p','Source-cache download timestamps (UTC): '+p.source_fetched_from+' to '+p.source_fetched_through+'. Rebuilding from cache does not refresh observations.'));
  $('unavailable').textContent=p.unavailable.length?p.unavailable.length+' configured gauge(s) could not be built; see the unavailable-gauges CSV.':'All '+(p.configured_gauges||p.gauges.length)+' configured gauges built successfully.';
  if(p.network_assessment){const a=text('a','Download network eligibility assessment (CSV)');a.href='eligibility.csv';$('unavailable').append(document.createElement('br'),a);}
function fit(){const points=state.shown.map(g=>[g.lat,g.lon]);if(points.length)map.fitBounds(points,{padding:[25,25],maxZoom:9});}
function selectDay(i){if(!state.rows.length)return;state.day=Math.min(state.rows.length-1,Math.max(0,i));const r=state.rows[state.day];
$('day-title').textContent=M.day(r.date);$('day-detail').replaceChildren();
const range=(a,b)=>M.valid(a)&&M.valid(b)?M.format(a)+'–'+M.format(b)+' cfs':'Unavailable';
for(const[label,value]of [['Observed daily mean',flow(r.cfs)],['Historical median',flow(r.p50)],['25th–75th percentile band',range(r.p25,r.p75)],['10th–90th percentile band',range(r.p10,r.p90)],['Historical category',M.categoryFor(r)],['Historical sample',M.valid(r.sample_count)?r.sample_count+' approved values for this calendar day':'Unavailable'],['Observation status',r.reported?(r.approval||'Approval status not supplied'):'No observation returned'],['Qualifier',r.qualifier||'None reported']]){const tr=document.createElement('tr');tr.append(text('td',label),text('td',value));$('day-detail').append(tr);}
if(!r.history_supported){const tr=document.createElement('tr');tr.append(text('td','Historical support'),text('td',r.history_note||'No supported historical statistics'));$('day-detail').append(tr);}
$('previous').disabled=state.day===0;$('next').disabled=state.day===state.rows.length-1;
const old=$('chart').querySelector('[data-cursor]');if(old)old.remove();const x=70+state.day/Math.max(1,state.rows.length-1)*825;
$('chart').append(svg('line',{x1:x,x2:x,y1:20,y2:235,stroke:'#b64822','stroke-width':1,'stroke-dasharray':'4 3','data-cursor':'true'}));}
function draw(){const previousDate=state.rows[state.day]?.date;const all=state.cache.get(state.selected.id)||[];state.rows=embedded?StreamflowExplorerModel.windowRows(all,p.cutoff,Number($('window').value)):all.slice(-Number($('window').value));const rows=state.rows,chart=$('chart');chart.replaceChildren();
const values=rows.filter(r=>M.valid(r.cfs)).map(r=>r.cfs),bands=$('bands').value;
const historical=bands==='none'?[]:rows.filter(r=>r.history_supported).map(r=>bands==='both'?r.p90:r.p75).filter(M.valid);
const plotted=[...values,...historical],max=plotted.length?Math.max(...plotted)*1.08||1:1;const x=i=>70+i/Math.max(1,rows.length-1)*825,y=v=>235-v/max*210;
for(let i=0;i<=4;i++){const v=max*i/4,yy=y(v);chart.append(svg('line',{x1:70,x2:895,y1:yy,y2:yy,stroke:'#dbe5e9'}));const label=svg('text',{x:62,y:yy+4,'text-anchor':'end','font-size':12,fill:'#536c79'});label.textContent=M.format(v);chart.append(label);}
if(bands!=='none'){
const shade=(lo,hi,color)=>{for(const s of M.historySegments(rows,lo,hi)){if(s.length<2)continue;const points=[...s.map(r=>x(r.i)+','+y(r.high)),...s.slice().reverse().map(r=>x(r.i)+','+y(r.low))];chart.append(svg('polygon',{points:points.join(' '),fill:color,stroke:'none'}));}};
if(bands==='both')shade('p10','p90','#e7ebf5');shade('p25','p75','#bec9e2');
for(const s of M.historySegments(rows,'p50')){if(s.length>1)chart.append(svg('polyline',{points:s.map(r=>x(r.i)+','+y(r.low)).join(' '),fill:'none',stroke:'#786132','stroke-width':2,'stroke-dasharray':'5 3'}));}}
for(const segment of M.segments(rows)){if(segment.length>1)chart.append(svg('polyline',{points:segment.map(r=>x(r.i)+','+y(r.value)).join(' '),fill:'none',stroke:'#197d88','stroke-width':2.5}));for(const point of segment)chart.append(svg('circle',{cx:x(point.i),cy:y(point.value),r:rows.length>40?2:3,fill:'#197d88'}));}
const unit=svg('text',{x:70,y:13,'font-size':12,fill:'#536c79'});unit.textContent='Daily mean discharge (cfs)';chart.append(unit);
if(rows.length){for(const[i,anchor]of [[0,'start'],[rows.length-1,'end']]){const d=svg('text',{x:x(i),y:263,'text-anchor':anchor,'font-size':12,fill:'#536c79'});d.textContent=M.day(rows[i].date);chart.append(d);}}
$('chart-status').textContent=(values.length?'Daily mean discharge · '+values.length+'/'+rows.length+' days have numeric observations.':'No numeric observations in this window. Missing or qualified values have not been replaced with zero.')+(embedded&&rows.length<Number($('window').value)?' Partial cached window: '+rows.length+' of '+$('window').value+' requested days are available.':'');
let index=rows.map(r=>r.date).indexOf(previousDate);if(index<0)index=rows.map(r=>r.date).indexOf(embedded?p.cutoff:state.selected.latest_date);if(index<0)index=rows.length-1;selectDay(index);
if(embedded){if(state.downloadURL)URL.revokeObjectURL(state.downloadURL);state.downloadURL=URL.createObjectURL(new Blob([StreamflowExplorerModel.csv(rows)],{type:'text/csv;charset=utf-8'}));$('csv').href=state.downloadURL;$('csv').download=state.selected.id+'-'+p.cutoff+'-'+$('window').value+'days.csv';$('csv').textContent='Download displayed daily data (CSV)';}}
async function choose(g,scroll=false){const token=++state.token;state.selected=g;$('selected').hidden=false;
  $('gauge-title').textContent=g.name;$('gauge-meta').textContent=g.id+' · '+g.river+' · '+g.state+' · reporting zone '+(g.time_zone||'not supplied')+(g.eligibility?' · '+g.eligibility:'')+(g.management_note?' · '+g.management_note:'');
$('usgs').href=g.usgs_url;$('csv').href=g.csv;$('gauge-stats').replaceChildren();
for(const[value,label]of [[flow(g.latest_cfs),'Latest reported daily mean · '+M.day(g.latest_date)],[g.historical_category||'History unavailable','Historical daily category · n = '+(g.historical_samples??'unavailable')],[flow(g.mean_7day_cfs),'Complete 7-day mean ending '+M.day(p.cutoff)],[g.approval||'Unavailable','Source approval status']]){const card=text('div','','stat');card.append(text('strong',value),text('span',label));$('gauge-stats').append(card);}
$('history-status').textContent='Historical context: available USGS-approved record; exact reference years are not supplied. At least 30 approved values are required for each calendar day. '+(g.statistics_fetched_utc?'Statistics downloaded '+g.statistics_fetched_utc+'.':'Historical statistics unavailable.');
$('record').textContent='Observation metadata bounds: '+String(g.record_begin||'unknown').slice(0,10)+' to '+String(g.record_end||'unknown').slice(0,10)+'. These are not the reference-year bounds for the approved statistics.';
for(const[id,m]of state.markers)m.setStyle({radius:id===g.id?10:7,weight:id===g.id?3:1.5,color:id===g.id?'#b64822':'#304b57'});
for(const row of $('gauges').children){const selected=row.dataset.id===g.id;row.classList.toggle('is-selected',selected);row.querySelector('button').setAttribute('aria-pressed',String(selected));}
const url=new URL(location.href);url.searchParams.set('gauge',g.id);history.replaceState(null,'',url);
if(embedded)parent.postMessage({type:'swc:streamflow-gauge',gauge:g.id},location.origin);
$('chart-status').textContent='Loading selected gauge hydrograph…';$('chart').replaceChildren();$('day-detail').replaceChildren();state.rows=[];$('previous').disabled=true;$('next').disabled=true;
try{if(!state.cache.has(g.id)){const data=await json(g.hydrograph);if(data.id!==g.id||!Array.isArray(data.rows))throw Error('Gauge hydrograph does not match the selection.');state.cache.set(g.id,data.rows);}if(token!==state.token)return;draw();if(scroll)$('selected').scrollIntoView({behavior:'smooth',block:'start'});}catch(e){if(token===state.token)$('chart-status').textContent=e.message;}}
function render(){state.shown=M.filtered(p.gauges,$('state').value,$('search').value,$('sort').value);$('gauges').replaceChildren();for(const m of state.markers.values())map.removeLayer(m);state.markers.clear();
const count={};for(const g of state.shown){count[g.freshness]=(count[g.freshness]||0)+1;const marker=L.circleMarker([g.lat,g.lon],{radius:7,weight:1.5,color:'#304b57',fillColor:M.categoryColors[g.historical_category]||M.categoryColors['History unavailable'],fillOpacity:g.freshness==='Stale'?.45:.9,dashArray:g.freshness==='Recent'?null:'4 3'}).addTo(map);
const tip=text('div','','flow-tooltip-content');tip.append(text('strong',g.name,'flow-tooltip-title'),text('div',M.day(g.latest_date)+' · '+g.state,'flow-tooltip-date'));
for(const[label,value]of [['Daily mean',flow(g.latest_cfs)],['Historical',g.historical_category||'History unavailable']]){const row=text('div','','flow-tooltip-row');row.append(text('span',label),text('strong',value));tip.append(row);}
  tip.append(text('div',(g.source_refresh_status==='STALE_RETAINED'?'Refresh failed; retained data · ':'')+g.freshness+' · '+(g.approval||g.latest_quality),'flow-tooltip-status'));
marker.bindTooltip(tip,{className:'streamflow-tooltip',direction:'auto',opacity:1,offset:[10,0]});marker.on('click',()=>choose(g));state.markers.set(g.id,marker);
const tr=document.createElement('tr');tr.dataset.id=g.id;const cell=document.createElement('td'),button=text('button',g.name);button.type='button';button.addEventListener('click',()=>choose(g));cell.append(button);tr.append(cell,text('td',g.state),text('td',M.day(g.latest_date)),text('td',flow(g.latest_cfs)),text('td',g.historical_category||'History unavailable'),text('td',flow(g.mean_7day_cfs)));
  const status=text('td',(g.source_refresh_status==='STALE_RETAINED'?'Refresh failed; retained · ':'')+g.freshness);status.append(document.createElement('br'),text('span',g.approval||g.latest_quality,'badge'));tr.append(status);$('gauges').append(tr);}
$('counts').textContent=state.shown.length+' gauges · '+Object.entries(count).map(([k,v])=>v+' '+k.toLowerCase()).join(' · ');
if(!state.shown.length){++state.token;state.selected=null;state.rows=[];$('selected').hidden=true;return;}
const selected=state.shown.find(g=>g.id===state.selected?.id)||state.shown.find(g=>g.id===new URL(location.href).searchParams.get('gauge'))||state.shown[0];choose(selected);}
for(const id of ['state','sort'])$(id).addEventListener('change',render);$('search').addEventListener('input',render);
$('fit').addEventListener('click',fit);$('reset').addEventListener('click',()=>{if(!embedded)$('state').value='all';$('search').value='';$('sort').value='name';render();fit();});
$('window').addEventListener('change',()=>{if(state.selected&&state.cache.has(state.selected.id))draw();});
$('bands').addEventListener('change',()=>{if(state.selected&&state.cache.has(state.selected.id))draw();});
$('previous').addEventListener('click',()=>selectDay(state.day-1));$('next').addEventListener('click',()=>selectDay(state.day+1));
$('chart').addEventListener('keydown',e=>{if(e.key==='ArrowLeft'||e.key==='ArrowRight'){e.preventDefault();selectDay(state.day+(e.key==='ArrowRight'?1:-1));}});
function inspect(e){if(!state.rows.length)return;const point=$('chart').createSVGPoint();point.x=e.clientX;point.y=e.clientY;const local=point.matrixTransform($('chart').getScreenCTM().inverse());selectDay(Math.round((local.x-70)/825*(state.rows.length-1)));}
$('chart').addEventListener('pointermove',inspect);$('chart').addEventListener('pointerdown',inspect);
if(embedded){
  document.body.classList.add('streamflow-embedded');
  $('asof').hidden=true;
  $('window').prepend(new Option('Selected day','1'));
  const mapCard=$('map').closest('section');let tableCard=$('gauge-table').closest('section');
  const collapsedTable=document.createElement('details');collapsedTable.id='gauge-table-panel';collapsedTable.className=tableCard.className;
  collapsedTable.append(text('summary','Gauge observations'));
  for(const child of [...tableCard.childNodes])if(child.nodeType!==1||child.tagName!=='H2')collapsedTable.append(child);
  tableCard.replaceWith(collapsedTable);tableCard=collapsedTable;
  const notice=text('p','','streamflow-coverage-note');notice.id='streamflow-coverage-note';$('asof').after(notice);
  let fitted=false;
  async function applySelection(s){
    if(!s||s.type!=='swc:streamflow-selection')return;
    const seq=++selectionSequence;++state.token;
    const valid=StreamflowExplorerModel.selection(s,range.start,range.end);
    mapCard.hidden=tableCard.hidden=!valid;$('selected').hidden=true;
    if(!valid){$('asof').hidden=true;notice.textContent='Streamflow unavailable for '+M.day(s.date)+'. Cached coverage: '+M.day(range.start)+'–'+M.day(range.end)+'. No other date has been substituted.';return;}
    notice.textContent='Loading cached gauge observations…';
    try{
      // All gauge values are needed to recolor a historical-date map. These
      // small, local 90-day payloads are fetched once and reused across dates.
      for(let i=0;i<originalGauges.length;i+=4)await Promise.all(originalGauges.slice(i,i+4).map(async g=>{
        if(!state.cache.has(g.id)){const d=await json(g.hydrograph);if(d.id!==g.id||!Array.isArray(d.rows))throw Error('Gauge payload mismatch');state.cache.set(g.id,d.rows);}
      }));
      if(seq!==selectionSequence)return;
      p.cutoff=s.date;$('window').value=String(s.days);$('state').value=s.region==='AZNM'?'all':s.region;
      p.gauges=originalGauges.map(g=>StreamflowExplorerModel.summary(g,state.cache.get(g.id),s.date));
      $('asof').textContent='Daily observations through '+M.day(s.date)+'. Each gauge shows its actual observation date.';
      $('asof').hidden=false;
      notice.textContent='USGS daily dates; these are not shifted to the PRISM precipitation window. Cached coverage: '+M.day(range.start)+'–'+M.day(range.end)+'.';
      state.rows=[];render();map.invalidateSize();if(!fitted){fit();fitted=true;}
    }catch(e){if(seq===selectionSequence){mapCard.hidden=tableCard.hidden=true;$('selected').hidden=true;notice.textContent='Streamflow unavailable: '+e.message;}}
  }
  window.addEventListener('message',e=>{if(e.origin===location.origin&&e.source===parent)applySelection(e.data);});
  for(const id of ['window','state'])$(id).addEventListener('change',()=>parent.postMessage({type:'swc:streamflow-control',days:Number($('window').value),region:$('state').value==='all'?'AZNM':$('state').value},location.origin));
  parent.postMessage({type:'swc:streamflow-ready'},location.origin);
  let heightQueued=false;const reportHeight=()=>{if(heightQueued)return;heightQueued=true;requestAnimationFrame(()=>{heightQueued=false;parent.postMessage({type:'swc:streamflow-height',height:Math.ceil(document.querySelector('main').getBoundingClientRect().height+20)},location.origin);});};
  new ResizeObserver(reportHeight).observe(document.querySelector('main'));reportHeight();
  notice.textContent='Waiting for the Explorer selected date…';mapCard.hidden=tableCard.hidden=true;
}else{render();fit();}
}catch(e){fail(e);}
})();
