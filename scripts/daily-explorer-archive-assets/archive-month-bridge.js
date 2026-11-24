// Same-origin month isolation: controls and cached modules belong to this frame.
(() => {
  "use strict";
  if(parent===window)return;
  const $=id=>document.getElementById(id),query=new URL(location.href).searchParams;
  let applied=false,applying=false,last="",queued=false;
  const state=()=>({region:$("region")?.value,variable:$("variable")?.value,view:$("view")?.value,compare:$("compare")?.value,
    weatherPeriod:$("circulation-period")?.value,timing:$("storm-timing")?.value,eventWindow:$("storm-window")?.value});
  const set=(id,value)=>{const el=$(id);if(value&&el&&[...el.options].some(o=>o.value===value)){el.value=value;el.dispatchEvent(new Event("change",{bubbles:true}));}};
  function post() {
    queued=false;if(applying||!$("date")?.value||typeof byDate==="undefined"||!byDate.has($("date").value))return;
    if(!applied) {
      applying=true;
      set("region",query.get("region"));set("variable",query.get("variable"));set("view",query.get("view"));set("compare",query.get("compare"));
      set("circulation-period",query.get("weatherPeriod"));set("storm-timing",query.get("timing"));set("storm-window",query.get("eventWindow"));
      const requested=query.get("date");if(requested&&byDate.has(requested))selectDate(requested);
      applied=true;applying=false;
    }
    const message={type:"swc:archive-month",token:query.get("archiveToken"),date:$("date").value,selection:state(),
      capabilities:{weather:typeof circulationEnabled!=="undefined"&&circulationEnabled===true,reports:!!$("storm-panel"),hazards:!!$("hazard-frame")},
      height:Math.ceil(document.querySelector("main").getBoundingClientRect().height+16)};
    const encoded=JSON.stringify(message);if(encoded!==last){last=encoded;parent.postMessage(message,location.origin);}
  }
  const queue=()=>{if(!queued){queued=true;requestAnimationFrame(post);}};
  document.addEventListener("swc:daily-selection",queue);document.addEventListener("change",queue);
  new MutationObserver(queue).observe(document.querySelector("main"),{childList:true,subtree:true,attributes:true});
  new ResizeObserver(queue).observe(document.querySelector("main"));queue();
})();
