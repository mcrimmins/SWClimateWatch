/* Local overlay: inline flow section, shared Explorer controls, lazy gauge data. */
(()=>{'use strict';
const $=id=>document.getElementById(id),origin=location.origin;
const adapter=document.querySelector('script[src*="explorer-streamflow"]');
const assetRoot=new URL('.',adapter?adapter.src:location.href);
const mainFrame=$('connected-viewer');
if(mainFrame){
  const targets=[['Daily summary','#timeline-title'],['Main map','#map-title'],['Streamflow','#streamflow-panel'],
    ['Storm reports','#storm-panel'],['NWS hazards','#hazard-panel'],['Weather maps','#circulation-panel'],
    ['Discussions','.discussions'],['Notable days','#notable-title']];
  const nav=document.createElement('nav');nav.className='explorer-jump-nav';nav.setAttribute('aria-label','Jump to product section');
  const label=document.createElement('span');label.textContent='Jump to';nav.append(label);
  const buttons=targets.map(([name,selector])=>{
    const button=document.createElement('button');button.type='button';button.textContent=name;button.disabled=true;
    button.addEventListener('click',()=>{
      const target=mainFrame.contentDocument?.querySelector(selector);if(!target||target.hidden)return;
      for(let el=target;el;el=el.parentElement)if(el.tagName==='DETAILS')el.open=true;
      requestAnimationFrame(()=>{
        const heading=target.matches('details')?target.querySelector('summary'):target;
        heading.setAttribute('tabindex','-1');heading.focus({preventScroll:true});
        const top=window.scrollY+mainFrame.getBoundingClientRect().top+heading.getBoundingClientRect().top-nav.getBoundingClientRect().height-16;
        window.scrollTo({top:Math.max(0,top),behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'});
      });
    });nav.append(button);return {button,selector,name};
  });
  document.querySelector('.archive-controls').after(nav);
  function refreshJumps(){for(const {button,selector,name}of buttons){const target=mainFrame.contentDocument?.querySelector(selector);button.disabled=!target||target.hidden;button.title=button.disabled?name+' unavailable for this selection':'';}}
  mainFrame.addEventListener('load',refreshJumps);
  new MutationObserver(()=>{for(const {button}of buttons)button.disabled=true;}).observe(mainFrame,{attributes:true,attributeFilter:['src']});
  // The outer shell remembers the flow selection when a date changes month.
  let saved={open:false,days:null,region:null,gauge:null};
  window.addEventListener('message',e=>{
    if(e.origin!==origin||e.source!==mainFrame.contentWindow)return;
    const m=e.data,token=new URL(mainFrame.src,location.href).searchParams.get('archiveToken');
    if(m?.token!==token)return;
    if(m.type==='swc:connected-month'&&m.ready)refreshJumps();
    if(m.type==='swc:streamflow-host-state'&&typeof m.open==='boolean'&&[1,7,30,90].includes(m.days)&&['AZNM','AZ','NM'].includes(m.region)&&(!m.gauge||/^USGS-\d+$/.test(m.gauge)))saved={open:m.open,days:m.days,region:m.region,gauge:m.gauge};
    if(m.type==='swc:streamflow-host-ready')mainFrame.contentWindow.postMessage({type:'swc:streamflow-restore',...saved},origin);
  });
  return;
}
const panel=$('streamflow-panel'),flow=$('streamflow-frame');if(!panel||!flow)return;
const select=$('streamflow-view-window'),region=$('streamflow-view-region');
const token=new URL(location.href).searchParams.get('archiveToken');
let ready=false,lastSent='',context=null,lastCompare=null,gauge=null,restored=false;
function remember(){if(parent!==window)parent.postMessage({type:'swc:streamflow-host-state',token,open:panel.open,days:Number(select.value),region:region.value,gauge},origin);}
function send(force=false){
  if(!panel.open||!ready||!context)return;
  const m={type:'swc:streamflow-selection',date:context.date,days:Number(select.value),region:region.value},encoded=JSON.stringify(m);
  if(force||encoded!==lastSent){lastSent=encoded;flow.contentWindow.postMessage(m,origin);}
}
function activate(){
  if(!panel.open)return;
  if(!flow.getAttribute('src')){const url=new URL('streamflow/index.html',assetRoot);url.searchParams.set('embedded','1');if(gauge)url.searchParams.set('gauge',gauge);flow.src=url.href;}
  send(true);
}
function sync(detail){
  const date=detail?.date||$('date')?.value;if(!/^\d{4}-\d{2}-\d{2}$/.test(date||''))return;
  context={date};const compare=$('compare')?.value;
  if(compare&&compare!==lastCompare){select.value=compare==='single'?'1':compare;lastCompare=compare;}
  const r=detail?.region||$('region')?.value;if(['AZNM','AZ','NM'].includes(r))region.value=r;
  send();if(restored)remember();
}
function applyToMaps(){
  for(const [id,value]of [['region',region.value],['compare',select.value==='1'?'single':select.value]]){
    const el=$(id);if(el&&[...el.options].some(o=>o.value===value)&&el.value!==value){el.value=value;el.dispatchEvent(new Event('change',{bubbles:true}));}
  }
}
panel.addEventListener('toggle',()=>{activate();remember();});
for(const el of [select,region])el.addEventListener('change',()=>{send();applyToMaps();remember();});
document.addEventListener('swc:daily-selection',e=>sync(e.detail));
for(const id of ['compare','region'])$(id)?.addEventListener('change',()=>sync());
const shortcut=document.createElement('button');shortcut.type='button';shortcut.id='view-streamflow';shortcut.textContent='View streamflow';
shortcut.addEventListener('click',()=>{panel.open=true;activate();panel.scrollIntoView({behavior:'smooth',block:'start'});});
const actions=$('open-map')?.parentElement;if(actions)actions.append(shortcut);
window.addEventListener('message',e=>{
  if(e.origin!==origin)return;const m=e.data;
  if(e.source===parent&&m?.type==='swc:streamflow-restore'&&!restored){
    restored=true;sync();
    if([1,7,30,90].includes(m.days))select.value=String(m.days);
    if(['AZNM','AZ','NM'].includes(m.region))region.value=m.region;
    if(/^USGS-\d+$/.test(m.gauge||''))gauge=m.gauge;
    panel.open=m.open===true;activate();remember();
  }
  if(e.source!==flow.contentWindow)return;
  if(m?.type==='swc:streamflow-ready'){ready=true;send(true);}
  if(m?.type==='swc:streamflow-gauge'&&/^USGS-\d+$/.test(m.gauge)){gauge=m.gauge;remember();}
  if(m?.type==='swc:streamflow-control'&&[1,7,30,90].includes(m.days)&&['AZNM','AZ','NM'].includes(m.region)){select.value=String(m.days);region.value=m.region;applyToMaps();send();remember();}
  if(m?.type==='swc:streamflow-height'&&Number.isFinite(m.height)){const h=Math.max(220,Math.min(12000,m.height));if(Math.abs(parseFloat(flow.style.height||'0')-h)>=4)flow.style.height=h+'px';}
});
if(parent!==window)parent.postMessage({type:'swc:streamflow-host-ready',token},origin);else restored=true;
document.dispatchEvent(new CustomEvent('swc:request-selection'));sync();
})();
