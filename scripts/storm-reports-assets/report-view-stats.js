/* Pure report summaries. Retain reports, not inferred unique storms. */
(function(root,factory){
  const api=factory();
  if(typeof module==="object"&&module.exports)module.exports=api;
  else root.StormReportStats=api;
})(typeof globalThis!=="undefined"?globalThis:this,function(){
  "use strict";
  const mapped=r=>r.mapped===true&&Number.isFinite(r.lat)&&Number.isFinite(r.lon)&&Math.abs(r.lat)<=90&&Math.abs(r.lon)<=180;
  function comparable(r,metric) {
    const type=String(r.type||"").toUpperCase();
    if(metric==="rain"&&type!=="RAIN")return null;
    if(metric==="hail"&&type!=="HAIL")return null;
    if(metric==="wind"&&!/\b(?:WND|WIND)\s+(?:GST|GUST)\b/.test(type))return null;
    const raw=String(r.magnitude??"").trim();
    if(!/^\d+(\.\d+)?$/.test(raw))return null;
    const value=Number(raw);if(!Number.isFinite(value))return null;
    const unit=String(r.unit||"").trim().toLowerCase();
    const factors=metric==="wind"?
      {mph:1,kt:1.1507794480235,kts:1.1507794480235,knot:1.1507794480235,knots:1.1507794480235,
        "m/s":2.2369362920544,mps:2.2369362920544,"km/h":0.62137119223733,kph:0.62137119223733}:
      {inch:1,inches:1,in:1,"in.":1,mm:1/25.4,millimeter:1/25.4,millimeters:1/25.4};
    return Object.hasOwn(factors,unit)?value*factors[unit]:null;
  }
  function extreme(rows,metric) {
    const eligible=rows.map(report=>({report,value:comparable(report,metric)})).filter(x=>x.value!==null);
    if(!eligible.length)return {value:null,reports:[],eligible:0,unit:metric==="wind"?"mph":"in."};
    const value=Math.max(...eligible.map(x=>x.value));
    return {value,reports:eligible.filter(x=>Math.abs(x.value-value)<=Math.max(1,value)*1e-10).map(x=>x.report),
      eligible:eligible.length,unit:metric==="wind"?"mph":"in."};
  }
  function summarize(rows,contains=()=>true) {
    const located=rows.filter(mapped),visible=located.filter(r=>contains(r));
    const counts=new Map();for(const r of visible)counts.set(r.type,(counts.get(r.type)||0)+1);
    return {total:rows.length,inView:visible.length,outside:located.length-visible.length,unmapped:rows.length-located.length,
      types:[...counts].sort((a,b)=>b[1]-a[1]||a[0].localeCompare(b[0])),
      extremes:Object.fromEntries(["rain","hail","wind"].map(metric=>[metric,extreme(visible,metric)]))};
  }
  return {mapped,comparable,summarize};
});
