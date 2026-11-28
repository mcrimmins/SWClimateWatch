(function(root){'use strict';
const M=root.StreamflowModel||(typeof require==='function'?require('./streamflow-model.js'):null);
const shift=(date,n)=>{const d=new Date(date+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
function windowRows(rows,end,days){return rows.filter(r=>r.date>=shift(end,1-days)&&r.date<=end);}
function summary(g,rows,end){
  const available=rows.filter(r=>r.date<=end),reported=available.filter(r=>r.reported),last=reported.at(-1);
  const lag=last?Math.round((Date.parse(end)-Date.parse(last.date))/86400000):null;
  const seven=windowRows(rows,end,7),complete=seven.length===7&&seven.every(r=>M.valid(r.cfs));
  return {...g,latest_date:last?.date||'',latest_cfs:last?.cfs??null,
    lag_days:lag,freshness:lag===null?'Unavailable':lag<=3?'Recent':lag<=7?'Delayed':'Stale',
    approval:last?.approval||'',latest_quality:last?.quality||'No observations through selected date',
    historical_category:last?M.categoryFor(last):'Unavailable',historical_samples:last?.sample_count??null,
    mean_7day_cfs:complete?seven.reduce((s,r)=>s+r.cfs,0)/7:null};
}
function selection(s,start,end){return !!s&&/^\d{4}-\d{2}-\d{2}$/.test(s.date||'')&&
  Number.isFinite(Date.parse(s.date))&&new Date(s.date+'T12:00:00Z').toISOString().slice(0,10)===s.date&&[1,7,30,90].includes(s.days)&&['AZNM','AZ','NM'].includes(s.region)&&s.date>=start&&s.date<=end;}
function csv(rows){if(!rows.length)return '';const keys=Object.keys(rows[0]),quote=v=>'"'+String(v??'').replace(/"/g,'""')+'"';return [keys.map(quote).join(','),...rows.map(r=>keys.map(k=>quote(r[k])).join(','))].join('\r\n');}
const api={shift,windowRows,summary,selection,csv};root.StreamflowExplorerModel=api;if(typeof module==='object'&&module.exports)module.exports=api;
})(typeof window==='object'?window:globalThis);
