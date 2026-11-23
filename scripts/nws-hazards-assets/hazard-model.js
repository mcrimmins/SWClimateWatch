/* Pure interval and event-selection rules shared by the viewer and tests. */
(() => {
  const instant=s=>Date.parse(s);
  // Stable by hazard code + level across review periods, dates and filters.
  const colors={
    'SV.W':'#b08000','TO.W':'#982979','FF.W':'#ce333b','FA.Y':'#188783',
    'FA.A':'#258b39','FA.W':'#236638','FL.W':'#176199','FL.Y':'#4389a0','FL.A':'#417d51',
    'DS.W':'#975424','DS.Y':'#b78334','DU.Y':'#72682b',
    'EH.W':'#b34372','XH.W':'#a52b60','HT.Y':'#d46d2d',
    'HW.W':'#b44f94','HW.A':'#985d7b','WI.Y':'#7763b7','LW.Y':'#a46aa1',
    'WS.W':'#6546a3','WS.A':'#8267b5','WW.Y':'#3185b1','BZ.W':'#263c8d',
    'SQ.W':'#337e88','WC.Y':'#46779d','EC.W':'#293e6d','CW.Y':'#5377a0',
    'FZ.W':'#304f9b','FZ.A':'#536eb3','HZ.W':'#404477','FR.Y':'#54814c',
    'FG.Y':'#7c8b35','ZF.Y':'#497d73','FW.W':'#c55124','FW.A':'#dc8c2d',
    'IS.W':'#436eb2','SN.Y':'#447fb9','AF.Y':'#665c52','SM.Y':'#6f6c75'
  };
  function appearance(event) {
    const key=`${event.phenomenon}.${event.significance}`;
    let hash=2166136261;for(const c of key)hash=Math.imul(hash^c.charCodeAt(0),16777619)>>>0;
    return {color:colors[key]||`hsl(${hash%360}, 62%, 37%)`,
      dashArray:event.significance==='A'?'7 4':event.significance==='Y'?'2 4':null};
  }
  function structuredDetails(segments){
    const causes={ER:'Excessive rainfall',SM:'Snowmelt',RS:'Rain and snowmelt',DM:'Dam or levee failure',IJ:'Ice jam',GO:'Glacier-dammed lake outburst',IC:'Rain, snowmelt and/or ice jam',MC:'Multiple causes',UU:'Unknown'};
    const severity={'1':'Minor','2':'Moderate','3':'Major',N:'Flood stage not expected (advisory)',U:'Unknown'};
    const records={NO:'Record flooding not expected',NR:'Near-record or record flooding expected',UU:'No comparison record available'};
    const title=s=>String(s).toLowerCase().replace(/\b\w/g,c=>c.toUpperCase());
    const values=key=>[...new Set(segments.map(s=>s.tags?.[key]).filter(v=>v!==undefined&&v!==null&&v!==''))];
    const rows=[];
    for(const [key,label,unit]of [['wind_mph','Wind gust tag','mph'],['hail_inches','Hail size tag','in.']]){
      const numbers=values(key).filter(v=>typeof v==='number'&&Number.isFinite(v)&&v>0).sort((a,b)=>a-b);
      if(numbers.length)rows.push([label,numbers.map(v=>`${Number(v.toFixed(2))} ${unit}`).join(', ')]);
    }
    for(const [key,label]of [['tornado','Tornado tag'],['damage_threat','Damage threat tag']]){
      const text=values(key).filter(v=>!['NONE','NULL','NA'].includes(String(v).toUpperCase())).map(title);
      if(text.length)rows.push([label,text.join('; ')]);
    }
    for(const [key,label,lookup,sentinels]of [['flood_cause','Flood cause',causes,[]],['flood_severity','Flood severity',severity,['0']],['flood_record','Flood record outlook',records,['OO']]]){
      const text=values(key).filter(v=>!sentinels.includes(String(v))).map(v=>lookup[v]||`Code ${v} (see bulletin)`);
      if(text.length)rows.push([label,text.join('; ')]);
    }
    const gauges=values('gauge_id').filter(v=>v!=='00000');if(gauges.length)rows.push(['NWS gauge ID',gauges.join(', ')]);
    if(values('emergency_lifecycle').includes(true))rows.push(['Archive emergency flag','Recorded during this event; see bulletin for timing']);
    return rows;
  }
  function bulletinChoice(segments,end){
    const stamp=p=>Date.parse(`${p.slice(0,4)}-${p.slice(4,6)}-${p.slice(6,8)}T${p.slice(8,10)}:${p.slice(10,12)}:00Z`);
    const eligible=segments.filter(s=>/^\d{12}-[A-Z0-9-]+$/.test(s.product)&&stamp(s.product)<end);
    const active=eligible.filter(s=>!['EXP','CAN','UPG'].includes(s.status));
    return (active.length?active:eligible).map(s=>s.product).sort().at(-1)||null;
  }
  function windowFor(date,n,timing,startLimit) {
    if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||![1,7,30].includes(Number(n)))throw Error('Invalid window');
    const end=instant(`${date}T${timing==='prism'?'12':'00'}:00:00Z`)+(timing==='prism'?0:86400000);
    return {start:end-Number(n)*86400000,end,truncated:end-Number(n)*86400000<instant(`${startLimit}T00:00:00Z`)};
  }
  function select(events,window,{region='AZNM',kind='all',type='all',search='',mode='overlap'}={}) {
    const result=[];search=search.toLowerCase();
    for(const event of events) {
      if(kind!=='all'&&event.significance!==kind||type!=='all'&&event.title!==type)continue;
      if(search&&!`${event.title} ${event.wfo} ${event.id} ${event.segments.map(s=>s.zone).join(' ')}`.toLowerCase().includes(search))continue;
      const segments=event.segments.filter(s=>instant(s.start)<window.end&&instant(s.end)>window.start&&
        (region==='AZNM'||s.states.includes(region)));
      // 'Starts in window' uses the archived effective start, not bulletin issue time.
      const first=Math.min(...event.segments.map(s=>instant(s.start)));
      if(!segments.length||mode==='starts'&&!(first>=window.start&&first<window.end))continue;
      result.push({...event,segments});
    }
    return result.sort((a,b)=>Math.min(...a.segments.map(s=>instant(s.start)))-Math.min(...b.segments.map(s=>instant(s.start)))||a.id.localeCompare(b.id));
  }
  const model={windowFor,select,appearance,structuredDetails,bulletinChoice};
  if(typeof module!=='undefined')module.exports=model;else globalThis.HazardModel=model;
})();
