// Private preview adapter. Source month viewers and maps remain immutable.
(()=>{
  'use strict';if(parent===window)return;
  const $=id=>document.getElementById(id),q=new URL(location.href).searchParams;
  document.documentElement.classList.toggle('connected-month-scope',!!q.get('connectedMonth'));
  // In the connected viewer the explicit date stays authoritative. The
  // standalone viewer's 30-day shortcut jumps to the latest context day,
  // which can belong to the next partition and trigger cascading navigation.
  if(typeof changeMapView==='function')changeMapView=function(source='compare'){
    $('compare').value=$(source).value;
    $('circulation-compare').value=$('compare').value;
    render();
  };
  let applied=false,applying=false,queued=false,last='',dirty=false,viewport=null;
  const baseRender=typeof render==='function'?render:null;
  if(baseRender)render=function(){if(!applied||applying){dirty=true;queue();return;}baseRender();};
  const values=()=>({region:$('region')?.value,variable:$('variable')?.value,view:$('view')?.value,compare:$('compare')?.value,
    weatherPeriod:$('circulation-period')?.value,timing:$('storm-timing')?.value,eventWindow:$('storm-window')?.value,metric:$('metric')?.value,
    openWeather:String(!!$('circulation-panel')?.open),openReports:String(!!$('storm-panel')?.open),openHazards:String(!!$('hazard-panel')?.open)});
  const set=(id,value,notify=false)=>{const el=$(id);if(value&&el&&el.value!==value&&[...el.options].some(o=>o.value===value)){el.value=value;if(notify)el.dispatchEvent(new Event('change',{bubbles:true}));return true;}return false;};
  function loadVisibleThumbnails(){
    if(!viewport)return;
    for(const img of document.querySelectorAll('img[data-connected-src]')){
      const box=img.getBoundingClientRect();
      if(!box.width||!box.height||img.closest('[hidden]')||box.bottom<viewport.top||box.top>viewport.bottom)continue;
      img.loading='eager';img.src=img.dataset.connectedSrc;delete img.dataset.connectedSrc;
    }
  }
  window.addEventListener('message',e=>{
    const m=e.data;
    if(e.origin!==location.origin||e.source!==parent||m?.type!=='swc:connected-viewport'||m.token!==q.get('archiveToken')||
      !Number.isFinite(m.top)||!Number.isFinite(m.bottom)||m.bottom<m.top)return;
    viewport={top:m.top,bottom:m.bottom};loadVisibleThumbnails();
  });
  let mapLoading=null;
  if(document.createElement&&$('map')?.before){mapLoading=document.createElement('p');mapLoading.id='connected-map-loading';mapLoading.textContent='Loading selected map…';$('map').before(mapLoading);}
  function post(){
    queued=false;if(applying)return;
    const error=$('error');if(error&&!error.hidden&&error.textContent){parent.postMessage({type:'swc:connected-month',token:q.get('archiveToken'),error:error.textContent},location.origin);return;}
    if(typeof byDate==='undefined'||!byDate.size||!$('year')?.options.length||!$('metric')?.options.length)return;
    if(!applied){
      applying=true;const requested=q.get('date');
      if(requested&&!byDate.has(requested)){applying=false;parent.postMessage({type:'swc:connected-month',token:q.get('archiveToken'),error:'Requested date is missing from this month. No date was substituted.'},location.origin);return;}
      let changed=false;
      for(const [id,key]of [['region','region'],['variable','variable'],['view','view'],['metric','metric'],['compare','compare'],['circulation-compare','compare'],['circulation-period','weatherPeriod'],['storm-timing','timing'],['storm-window','eventWindow']])
        changed=set(id,q.get(key),id==='variable')||changed;
      for(const [key,id]of [['openWeather','circulation-panel'],['openReports','storm-panel'],['openHazards','hazard-panel']])if(q.has(key)&&$(id))$(id).open=q.get(key)==='true';
      // Apply the requested day after controls that may themselves render.
      if(requested&&$('date')?.value!==requested){selectDate(requested);dirty=true;}
      applied=true;applying=false;
      if(baseRender&&(dirty||changed)){dirty=false;baseRender();}
    }
    const primary=$('map');
    if(mapLoading){const visible=primary&&!primary.hidden&&!primary.complete?'visible':'hidden';if(mapLoading.style.visibility!==visible)mapLoading.style.visibility=visible;}
    // Optional images may be lazy and off screen; waiting for them deadlocks
    // a hidden frame. Reveal the correctly initialized selected-day view.
    const ready=applied&&byDate.has($('date')?.value);
    loadVisibleThumbnails();
    const message={type:'swc:connected-month',token:q.get('archiveToken'),date:$('date').value,selection:values(),ready,
      capabilities:{weather:typeof circulationEnabled!=='undefined'&&circulationEnabled===true,reports:!!$('storm-panel'),hazards:!!$('hazard-frame')},
      height:Math.ceil(document.querySelector('main').getBoundingClientRect().height+16)};
    const encoded=JSON.stringify(message);if(encoded!==last){last=encoded;parent.postMessage(message,location.origin);}
  }
  const queue=()=>{if(!queued){queued=true;requestAnimationFrame(post);}};
  document.addEventListener('swc:daily-selection',queue);document.addEventListener('change',queue);document.addEventListener('toggle',queue,true);
  document.addEventListener('load',queue,true);document.addEventListener('error',queue,true);
  new MutationObserver(queue).observe(document.querySelector('main'),{childList:true,subtree:true,attributes:true});
  new ResizeObserver(queue).observe(document.querySelector('main'));queue();
})();
