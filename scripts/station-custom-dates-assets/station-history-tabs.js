/* Local integration opt-in. Current station charts remain the default. */
window.SWCStationHistoryTabs = (() => {
  const states=new WeakMap(); let preferred='current';
  const readable=value=>new Intl.DateTimeFormat('en-US',{month:'short',day:'numeric',year:'numeric',timeZone:'UTC'}).format(new Date(value+'T00:00:00Z'));
  function header(state) {
    const el=document.getElementById('detail-subtitle');
    if(state.active==='current') el.textContent=state.subtitle;
    else if(state.selection) el.textContent=`${state.station.sid} · Historical observations · ${readable(state.selection.start)}–${readable(state.selection.end)} · Cache through ${readable(state.selection.cutoff)}`;
    else el.textContent=`${state.station.sid} · Explore station history · Choose dates below`;
  }
  function activate(state, name) {
    state.active=name; preferred=name;
    for(const key of ['current','history']) {
      const active=key===name;state.buttons[key].setAttribute('aria-selected',String(active));
      state.buttons[key].tabIndex=active?0:-1;state.panels[key].hidden=!active;
    }
    if(name==='history'&&!state.frame) {
      const frame=document.createElement('iframe');state.frame=frame;
      frame.className='station-history-frame';frame.title=`Historical observations for ${state.station.name}`;
      frame.dataset.stationUid=String(state.station.uid);
      frame.src=`custom-history/index.html?embedded=1&uid=${encodeURIComponent(state.station.uid)}`;
      frame.height='640';frame.setAttribute('loading','eager');
      state.panels.history.append(frame);
    }
    if(name==='current'&&state.frame)state.frame.contentWindow?.postMessage({type:'swc-station-history-pause',uid:String(state.station.uid)},location.origin);
    header(state);
  }
  function destroy(root) {
    const state=states.get(root);
    if(state){window.removeEventListener('message',state.listener);state.frame?.remove();states.delete(root);}
  }
  function prepare(root,uid) {
    const state=states.get(root);
    if(state&&String(state.station.uid)===String(uid)&&root.contains(state.panels.current)) {
      state.panels.current.textContent='Updating current conditions…';return true;
    }
    destroy(root);return false;
  }
  function render(root,html,station) {
    const subtitle=document.getElementById('detail-subtitle').textContent;
    let state=states.get(root);
    if(!state||String(state.station.uid)!==String(station.uid)||!root.contains(state.panels.current)) {
      destroy(root);root.replaceChildren();
      const tabs=document.createElement('div');tabs.className='station-detail-tabs';tabs.setAttribute('role','tablist');tabs.setAttribute('aria-label','Selected station views');
      state={station,subtitle,active:preferred,buttons:{},panels:{},frame:null,selection:null};
      for(const [name,label] of [['current','Current conditions'],['history','Explore station history']]) {
        const button=document.createElement('button');button.type='button';button.textContent=label;button.id=`station-view-${name}`;
        button.setAttribute('role','tab');button.setAttribute('aria-controls',`station-panel-${name}`);
        const panel=document.createElement('section');panel.id=`station-panel-${name}`;panel.className='station-detail-panel';panel.setAttribute('role','tabpanel');panel.setAttribute('aria-labelledby',button.id);
        button.addEventListener('click',()=>activate(state,name));
        button.addEventListener('keydown',event=>{
          if(!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;
          event.preventDefault();const target=event.key==='Home'?'current':event.key==='End'?'history':name==='current'?'history':'current';
          activate(state,target);state.buttons[target].focus();
        });
        state.buttons[name]=button;state.panels[name]=panel;tabs.append(button);
      }
      root.append(tabs,state.panels.current,state.panels.history);
      const note=document.createElement('p');note.className='detail-chart-note';
      note.textContent='Explore this station’s cached daily record. These dates are independent of the map’s summary period. Historical comparisons shown under Current conditions do not apply to a custom period.';
      state.panels.history.append(note);
      state.listener=event=>{
        if(!state.frame||event.origin!==location.origin||event.source!==state.frame.contentWindow||String(event.data?.uid)!==String(state.station.uid))return;
        if(event.data.type==='swc-station-history-height'&&Number.isFinite(event.data.height)) state.frame.height=String(Math.max(480,Math.min(10000,event.data.height)));
        if(event.data.type==='swc-station-history-selection'&&/^\d{4}-\d{2}-\d{2}$/.test(event.data.start)&&/^\d{4}-\d{2}-\d{2}$/.test(event.data.end)&&/^\d{4}-\d{2}-\d{2}$/.test(event.data.cutoff)) {
          state.selection=event.data;header(state);
        }
      };
      window.addEventListener('message',state.listener);states.set(root,state);
    }
    state.station=station;state.subtitle=subtitle;state.panels.current.innerHTML=html;
    activate(state,state.active);
  }
  function close(root){destroy(root);preferred='current';root.replaceChildren();}
  return {prepare,render,close};
})();
