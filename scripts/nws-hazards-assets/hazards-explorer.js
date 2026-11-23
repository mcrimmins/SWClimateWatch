/* Shared timeline and same-origin bridge to the isolated hazard map component. */
(() => {
  'use strict';
  const $=id=>document.getElementById(id),frame=$('hazard-frame');
  const node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
  let catalog=null,reportCatalog=null,selection=null,hoveredButton=null;
  const tooltip=node('div');tooltip.id='event-timeline-tooltip';tooltip.className='event-timeline-tooltip';tooltip.hidden=true;tooltip.setAttribute('role','tooltip');document.body.append(tooltip);
  const selectedSummary=node('p');selectedSummary.id='event-day-summary';selectedSummary.className='muted small';$('hazard-timeline-detail').before(selectedSummary);
  const timing=()=>$('storm-timing').value;
  const summaries=()=>new Map((catalog?.timeline?.[timing()]||[]).map(d=>[d.date,d]));
  const dateLabel=d=>new Date(d+'T00:00:00Z').toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric',timeZone:'UTC'});
  const reportNames={'FLASH FLOOD':'Flash flood','FLOOD':'Flood','RAIN':'Rainfall','TSTM WND GST':'Thunderstorm gust',
    'TSTM WND DMG':'Thunderstorm wind damage','NON-TSTM WND GST':'Non-thunderstorm gust','NON-TSTM WND DMG':'Non-thunderstorm wind damage'};
  const reportName=s=>reportNames[s]||s.toLowerCase().replace(/\b\w/g,c=>c.toUpperCase());
  function eventDay(source,date){const day=(source?.timeline?.[timing()]||[]).find(d=>d.date===date);return {day,counts:day?.available===false?null:day?.regions?.[selection?.region||'AZNM']};}
  function countText(info){return info.counts?`${info.day.complete?'':'≥'}${info.counts.total}`:'Unavailable';}
  function weatherText(button){
    const base=button.dataset.reportBaseTitle??button.title;
    button.dataset.reportBaseTitle??=base;
    if(base.includes(': '))button.dataset.timelineWeather=base.slice(base.indexOf(': ')+2);
    return button.dataset.timelineWeather||'Weather value unavailable';
  }
  function hideTooltip(){if(hoveredButton)hoveredButton.removeAttribute('aria-describedby');hoveredButton=null;tooltip.hidden=true;}
  function showTooltip(button){
    if(!catalog||!selection)return;hoveredButton=button;
    const date=button.dataset.reportDate,region={AZNM:'Arizona + New Mexico',AZ:'Arizona',NM:'New Mexico'}[selection.region];
    tooltip.replaceChildren(node('strong',dateLabel(date)),node('div',region));
    const weather=node('div');weather.className='event-tip-weather';
    const value=weatherText(button),label=$('metric').selectedOptions[0]?.textContent||'';
    if(label&&value.startsWith(label+' '))weather.append(node('span',label),node('b',value.slice(label.length+1)));
    else weather.textContent=value;
    tooltip.append(weather);
    for(const [source,title,names,visible]of [[reportCatalog,'Storm reports',reportName,$('show-report-row').checked],[catalog,'NWS hazards',s=>s,$('show-hazard-row').checked]]){
      if(!visible)continue;const info=eventDay(source,date),section=node('section'),heading=node('div');heading.className='event-tip-heading';
      heading.append(node('b',title),node('b',countText(info)));section.append(heading);
      if(info.counts){
        const entries=Object.entries(info.counts.types||{}).sort((a,b)=>b[1]-a[1]||a[0].localeCompare(b[0]));
        const list=node('dl');
        for(const [type,n]of entries.slice(0,3))list.append(node('dt',names(type)),node('dd',String(n)));
        section.append(list);
        if(entries.length>3)section.append(node('small',`+ ${entries.length-3} other types`));
        if(!info.day.complete)section.append(node('small','Partial coverage'));
        if(info.day.stale)section.append(node('small','Cached · refresh pending'));
      }
      tooltip.append(section);
    }
    tooltip.append(node('small',timing()==='prism'?'24 hours ending at 12 UTC':'UTC calendar day'));
    tooltip.hidden=false;button.setAttribute('aria-describedby',tooltip.id);
    const box=button.getBoundingClientRect(),tip=tooltip.getBoundingClientRect();
    tooltip.style.left=`${Math.max(12,Math.min(box.left+box.width/2-tip.width/2,innerWidth-tip.width-12))}px`;
    const below=box.bottom+8;tooltip.style.top=`${Math.max(12,Math.min(below+tip.height<innerHeight-12?below:box.top-tip.height-8,innerHeight-tip.height-12))}px`;
  }
  function selectedLine(){
    if(!selection)return;const reports=eventDay(reportCatalog,selection.date),hazards=eventDay(catalog,selection.date);
    selectedSummary.textContent=`${dateLabel(selection.date)} · Storm reports: ${countText(reports)} · Active hazards: ${countText(hazards)}`;
  }
  function postSelection(){if(selection)frame.contentWindow.postMessage({type:'swc:hazard-selection',...selection,
    days:Number($('storm-window').value),timing:timing(),min:$('date').min,max:$('date').max},location.origin);}
  function describe(date){
    const day=summaries().get(date),counts=day?.regions?.[selection?.region||'AZNM'];
    if(!day?.available)return `${dateLabel(date)}: NWS hazard data unavailable; this is not zero hazards.`;
    const types=Object.entries(counts.types).sort((a,b)=>b[1]-a[1]);
    return `${dateLabel(date)}: ${day.complete?'':'at least '}${counts.total} active NWS hazard events${day.complete?'':' (partial window)'}${types.length?'; '+types.map(([type,n])=>`${type}: ${n}`).join('; '):''}. Counts are unique VTEC events, not reports or polygon pieces.`;
  }
  function renderTimeline(){
    if(!catalog||!selection)return;
    const days=summaries(),types=new Map(catalog.types.map(e=>[e.title,e])),used=new Set();
    for(const button of $('timeline').querySelectorAll('.day[data-report-date]')){
      button.querySelector('.hazard-day-summary')?.remove();
      const date=button.dataset.reportDate,day=days.get(date),counts=day?.available?day.regions[selection.region]:null;
      const strip=node('span');strip.className='hazard-day-summary';strip.setAttribute('aria-hidden','true');
      strip.append(node('strong',counts?`${counts.total}${day.complete?'':'+'}`:'?'));
      const colors=node('span');colors.className='hazard-day-types';
      const ordered=Object.entries(counts?.types||{}).sort((a,b)=>b[1]-a[1]);
      for(const [title]of ordered.slice(0,3)){const dot=node('span');dot.style.background=HazardModel.appearance(types.get(title)).color;colors.append(dot);used.add(title);}
      if(ordered.length>3){const more=node('span','+');more.className='hazard-more';colors.append(more);}
      strip.append(colors);button.append(strip);
      const weather=weatherText(button),reports=eventDay(reportCatalog,date),hazards=eventDay(catalog,date);
      // Suppress the unformatted native title and keep a concise keyboard label.
      button.removeAttribute('title');
      button.setAttribute('aria-label',`${dateLabel(date)}. ${weather}. Storm reports: ${countText(reports)}. Active hazards: ${countText(hazards)}. Select this day.`);
    }
    $('hazard-timeline-detail').textContent=describe(selection.date);
    selectedLine();
    if(hoveredButton){if(hoveredButton.isConnected)showTooltip(hoveredButton);else hideTooltip();}
    $('hazard-timeline-legend').replaceChildren();
    for(const title of [...used].sort()){
      const item=node('span',title);item.style.setProperty('--hazard-color',HazardModel.appearance(types.get(title)).color);
      $('hazard-timeline-legend').append(item);
    }
  }
  function rowVisibility(){
    const root=$('timeline').closest('.event-timeline-layout');
    root.classList.toggle('hide-reports',!$('show-report-row').checked);
    root.classList.toggle('hide-hazards',!$('show-hazard-row').checked);
  }
  function setEventWindow(n){if($('storm-window').value!==String(n)){$('storm-window').value=String(n);$('storm-window').dispatchEvent(new Event('change',{bubbles:true}));}}
  document.addEventListener('swc:daily-selection',e=>{if(!e.detail?.date)return;selection={date:e.detail.date,region:e.detail.region};renderTimeline();postSelection();});
  $('storm-timing').addEventListener('change',()=>{renderTimeline();postSelection();});
  $('storm-window').addEventListener('change',postSelection);
  $('compare').addEventListener('change',()=>{setEventWindow($('compare').value==='single'?1:Number($('compare').value));postSelection();});
  for(const id of ['show-report-row','show-hazard-row'])$(id).addEventListener('change',rowVisibility);
  for(const event of ['mouseover','focusin'])$('timeline').addEventListener(event,e=>{const day=e.target.closest('.day[data-report-date]');if(day&&catalog&&hoveredButton!==day)showTooltip(day);});
  $('timeline').addEventListener('mouseout',e=>{if(!e.relatedTarget?.closest?.('.day[data-report-date]'))hideTooltip();});
  $('timeline').addEventListener('focusout',hideTooltip);
  $('timeline').addEventListener('keydown',e=>{if(e.key==='Escape')hideTooltip();});
  window.addEventListener('resize',hideTooltip);document.addEventListener('scroll',hideTooltip,true);
  // Reports may finish loading after the hazard summaries. Keep the hazard row
  // last without reacting to our own additions or accumulating event handlers.
  new MutationObserver(records=>{
    if(records.some(r=>[...r.addedNodes].some(n=>n.nodeType===1&&(n.classList.contains('storm-day-summary')||n.classList.contains('day')))))renderTimeline();
  }).observe($('timeline'),{childList:true,subtree:true});
  window.addEventListener('message',e=>{
    if(e.origin!==location.origin||e.source!==frame.contentWindow)return;
    const s=e.data;
    if(s?.type==='swc:hazard-ready'){postSelection();return;}
    if(s?.type==='swc:hazard-height'){if(Number.isFinite(s.height))frame.style.height=`${Math.max(600,Math.min(6000,s.height))}px`;return;}
    if(s?.type!=='swc:hazard-control'||!/^\d{4}-\d{2}-\d{2}$/.test(s.date)||!['AZNM','AZ','NM'].includes(s.region)||![1,7,30].includes(s.days)||!['prism','utc'].includes(s.timing))return;
    if(s.date<$('date').min||s.date>$('date').max)return;
    if($('region').value!==s.region){$('region').value=s.region;$('region').dispatchEvent(new Event('change',{bubbles:true}));}
    if($('storm-timing').value!==s.timing){$('storm-timing').value=s.timing;$('storm-timing').dispatchEvent(new Event('change',{bubbles:true}));}
    setEventWindow(s.days);
    if(selection?.date!==s.date)document.dispatchEvent(new CustomEvent('swc:request-date',{detail:{date:s.date}}));
  });
  fetch('hazard-timeline.json',{cache:'no-store'}).then(async r=>{if(!r.ok)throw Error(`Hazard summary HTTP ${r.status}`);catalog=await r.json();if(catalog.schema_version!==1||!Array.isArray(catalog.types))throw Error('Invalid hazard summary');renderTimeline();postSelection();}).catch(e=>{$('hazard-timeline-detail').textContent=`Hazard timeline unavailable: ${e.message}.`;});
  fetch('storm-reports-manifest.json',{cache:'no-store'}).then(async r=>{if(!r.ok)throw Error(`Report summary HTTP ${r.status}`);reportCatalog=await r.json();renderTimeline();}).catch(()=>{reportCatalog=null;selectedLine();});
  document.dispatchEvent(new CustomEvent('swc:request-selection'));
})();
