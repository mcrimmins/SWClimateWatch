/* Local preview adapter: no requests, no changes to observed temperatures. */
"use strict";
window.SWCStationTemperatureNormals = (() => {
  const finite=v=>typeof v==="number"&&Number.isFinite(v);
  const temp=v=>finite(v)?`${v.toFixed(1)}°F`:"unavailable";
  const escape=value=>String(value??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const dateLabel=value=>new Date(`${value}T00:00:00Z`).toLocaleDateString("en-US",{month:"short",day:"numeric",year:"numeric",timeZone:"UTC"});
  let activeDays=new Map(), activeStation={};
  function bind(days,station={}) {activeDays=new Map(days.map(day=>[day.date,day]));activeStation=station;}
  function eventLabels(day) {
    return ["high","low"].flatMap(kind=>{
      const status=day[`record_${kind}_status`];
      return status===`NEW_${kind.toUpperCase()}`?[`New record ${kind}`]:
        status===`TIED_${kind.toUpperCase()}`?[`Tied record ${kind}`]:[];
    });
  }
  function observed(day,field) {
    return day[`${field}_status`]==="FLAGGED"?"Flagged":finite(day[field])?temp(day[field]):"Missing";
  }
  function tooltip(day) {
    const events=eventLabels(day);
    return `${dateLabel(day.date)}\nHigh ${observed(day,"maxt")} · Low ${observed(day,"mint")}`+
      (events.length?`\n${events.join(" · ")}`:"");
  }
  function hit(day,x,width,first) {
    const text=escape(tooltip(day));
    return `<rect class="chart-day" x="${x}" y="14" width="${width}" height="131" fill="transparent" `+
      `tabindex="${first?0:-1}" role="button" aria-label="${text}" data-chart-readout="${text}" data-temperature-date="${escape(day.date)}">`+
      `<title>${text}</title></rect>`;
  }
  function readoutHtml(day,station={}) {
    const value=v=>finite(v)?escape(temp(v)):"—";
    const normal=field=>value(day[`normal_${field}`]);
    const delta=field=>{
      if(!finite(day[field])||!finite(day[`normal_${field}`]))return "—";
      const raw=day[field]-day[`normal_${field}`],n=Math.abs(raw)<.05?0:raw;
      return `<span class="temperature-delta ${n>0?"warm":n<0?"cool":"neutral"}">${n>0?"+":""}${n.toFixed(1)}°F</span>`;
    };
    const record=kind=>!finite(day[`record_${kind}`])?"—":
      `<strong>${value(day[`record_${kind}`])}</strong><small>${escape(String(day[`record_${kind}_years`]||"").split(",").filter(Boolean).join(", "))}</small>`;
    const row=(label,high,low)=>`<tr><th scope="row">${label}</th><td>${high}</td><td>${low}</td></tr>`;
    const coverage=kind=>finite(day[`record_${kind}`])?
      `${kind==="high"?"High":"Low"} record: ${day[`record_${kind}_n`]} earlier valid years (${day[`record_${kind}_first_year`]}–${day[`record_${kind}_last_year`]}).`:
      `${kind==="high"?"High":"Low"} record withheld: insufficient eligible history.`;
    const period=[day.date===station.hottest_day_date?"Highest high in the selected period.":"",
      day.date===station.coldest_night_date?"Lowest low in the selected period.":""].filter(Boolean).join(" ");
    return `<div class="temperature-readout-heading"><strong>${escape(dateLabel(day.date))}</strong>`+
      eventLabels(day).map(label=>`<span class="temperature-record-badge">${escape(label)}</span>`).join("")+`</div>`+
      `<table class="temperature-day-table" aria-label="Daily temperature comparison"><thead><tr><th scope="col">Temperature</th><th scope="col">High</th><th scope="col">Low</th></tr></thead><tbody>`+
      row("Observed",`<strong class="normal-high">${escape(observed(day,"maxt"))}</strong>`,`<strong class="normal-low">${escape(observed(day,"mint"))}</strong>`)+
      row("Normal <small>1991–2020</small>",normal("maxt"),normal("mint"))+
      row("Departure",delta("maxt"),delta("mint"))+
      row("Earlier record",record("high"),record("low"))+`</tbody></table>`+
      `<details class="temperature-coverage"><summary>Reference coverage</summary>`+
      `<p>${finite(day.normal_maxt)&&finite(day.normal_mint)?`Normals: at least ${escape(day.normal_years)} paired years per calendar day.`:"Normals withheld: insufficient reference support."}</p>`+
      `<p>${escape(coverage("high"))}</p><p>${escape(coverage("low"))}</p>`+
      (period?`<p>${escape(period)}</p>`:"")+`</details>`;
  }
  function renderReadout(hit,container) {
    const precipitation=Boolean(hit.dataset.precipitationDate);
    const day=activeDays.get(precipitation?hit.dataset.precipitationDate:hit.dataset.temperatureDate);
    if(!day)return false;
    const open=container.querySelector?.("details")?.open;
    container.innerHTML=precipitation?precipitationReadoutHtml(day,activeStation):readoutHtml(day,activeStation);
    if(open)container.querySelector("details").open=true;
    return true;
  }
  function precipitationObserved(day) {
    const status=day.pcpn_record_observation_status||day.pcpn_status;
    if(status==="ACCUMULATED")return "Accumulated report — not a daily total";
    if(status==="FLAGGED")return "Flagged — daily total withheld";
    if(status==="MISSING")return "Missing";
    if(status==="TRACE")return "Trace (<0.01 in.)";
    if(!finite(day.pcpn))return "Missing";
    return `${day.pcpn.toFixed(2)} in.`;
  }
  function precipitationEvents(day) {
    const status=day.pcpn_record_observation_status||day.pcpn_status;
    if(status!=="AVAILABLE"||!finite(day.pcpn)||day.pcpn<=0||!finite(day.record_pcpn))return [];
    if(day.record_pcpn_status==="TIED_RECORD" && day.record_pcpn<=0)return [];
    return day.record_pcpn_status==="NEW_RECORD"?["New daily record"]:
      day.record_pcpn_status==="TIED_RECORD"?["Tied daily record"]:[];
  }
  function precipitationTooltip(day) {
    const events=precipitationEvents(day);
    return `${dateLabel(day.date)}\nPrecipitation: ${precipitationObserved(day)}`+
      (events.length?`\n${events.join(" · ")}`:"");
  }
  function precipitationBarStyle(day) {
    if(!precipitationEvents(day).length)return 'fill="#327eaa"';
    return day.record_pcpn_status==="TIED_RECORD"?
      'fill="url(#precipitation-record-tie)" stroke="#703b86" stroke-width="1"':
      'fill="#703b86"';
  }
  function precipitationLegend() {
    return `<p class="precipitation-chart-key"><span><i class="precip-key ordinary"></i>Observed</span> <span><i class="precip-key record"></i>New daily record</span> <span><i class="precip-key tied"></i>Tied daily record</span><br><span class="precip-period-key">▼ Wettest day · Shading: wettest 3-day span in selected period</span></p>`;
  }
  function precipitationDefinitions() {
    return `<defs><pattern id="precipitation-record-tie" patternUnits="userSpaceOnUse" width="6" height="6"><rect width="6" height="6" fill="#703b86"/><path d="M-1,1 l2,-2 M0,6 l6,-6 M5,7 l2,-2" stroke="#eee3f3" stroke-width="2"/></pattern></defs>`;
  }
  function precipitationHit(day,x,width,first) {
    const text=escape(precipitationTooltip(day));
    return `<rect class="chart-day" x="${x}" y="14" width="${width}" height="131" fill="transparent" `+
      `tabindex="${first?0:-1}" role="button" aria-label="${text}" data-chart-readout="${text}" data-precipitation-date="${escape(day.date)}">`+
      `<title>${text}</title></rect>`;
  }
  function precipitationReadoutHtml(day,station={}) {
    const hasRecord=finite(day.record_pcpn);
    const years=String(day.record_pcpn_years||"").split(",").filter(Boolean).join(", ");
    const record=hasRecord?`<strong>${day.record_pcpn.toFixed(2)} in.</strong>`+
      `<small>${day.record_pcpn>0?escape(years):"No measurable rain in eligible history"}</small>`:"—";
    const coverage=hasRecord?`${day.record_pcpn_n} earlier valid years (${day.record_pcpn_first_year}–${day.record_pcpn_last_year}).`:
      `Record withheld: insufficient eligible history${finite(day.record_pcpn_n)?` (${day.record_pcpn_n} earlier valid years)`:""}.`;
    const period=[day.date===station.max_daily_pcpn_date?"Wettest day in the selected period.":"",
      day.date===station.max_3day_pcpn_start_date?"Wettest three-day span starts on this date.":"",
      day.date===station.max_3day_pcpn_end_date?"Wettest three-day span ends on this date.":""].filter(Boolean).join(" ");
    return `<div class="temperature-readout-heading"><strong>${escape(dateLabel(day.date))}</strong>`+
      precipitationEvents(day).map(label=>`<span class="temperature-record-badge">${escape(label)}</span>`).join("")+`</div>`+
      `<table class="temperature-day-table precipitation-day-table" aria-label="Daily precipitation comparison"><thead><tr><th scope="col">Precipitation</th><th scope="col">Amount</th></tr></thead><tbody>`+
      `<tr><th scope="row">Observed</th><td><strong class="precipitation-observed">${escape(precipitationObserved(day))}</strong></td></tr>`+
      `<tr><th scope="row">Earlier daily record</th><td>${record}</td></tr></tbody></table>`+
      `<details class="temperature-coverage"><summary>Reference coverage</summary><p>${escape(coverage)}</p>`+
      `<p>Earlier reports on this exact calendar date; flagged and accumulated reports excluded.</p>`+
      (period?`<p>${escape(period)}</p>`:"")+`</details>`;
  }
  function paths(days,x,y) {
    const series=[
      ["record_high","#bd9586","chart-record","2 4",1.2,.8],
      ["record_low","#91a8be","chart-record","2 4",1.2,.8],
      ["normal_maxt","#b35b37","chart-normal","6 4",1.5,.7],
      ["normal_mint","#326a9e","chart-normal","6 4",1.5,.7]];
    const curves=series.map(([field,color,cls,dash,width,opacity])=>{
      let drawing=false;
      const path=days.map((day,i)=>{
        if(!finite(day[field])){drawing=false;return "";}
        const command=drawing?"L":"M";drawing=true;
        return `${command}${x(i).toFixed(1)},${y(day[field]).toFixed(1)}`;
      }).join(" ");
      return `<path class="${cls}" data-normal="${field}" d="${path}" fill="none" stroke="${color}" stroke-width="${width}" stroke-dasharray="${dash}" opacity="${opacity}"/>`;
    }).join("");
    return curves;
  }
  function markers(days,x,y) {
    return days.flatMap((day,i)=>[["high","maxt","#b35b37"],["low","mint","#326a9e"]].map(([kind,field,color])=>{
      const status=day[`record_${kind}_status`];
      if(!finite(day[field]))return "";
      const px=x(i),py=y(day[field]);
      if(status===`NEW_${kind.toUpperCase()}`)return `<path class="chart-new-record" data-record="${kind}" d="M${px},${py-4} l4,4 l-4,4 l-4,-4 Z" fill="${color}" stroke="white" stroke-width=".7"/>`;
      if(status===`TIED_${kind.toUpperCase()}`)return `<rect class="chart-tied-record" data-record="${kind}" x="${px-3}" y="${py-3}" width="6" height="6" fill="${color}" stroke="white" stroke-width=".7"/>`;
      return "";
    })).join("");
  }
  function recordReadout(day) {
    return [["high","High"],["low","Low"]].map(([kind,label])=>{
      const value=day[`record_${kind}`];
      if(!finite(value))return ` ${label} record unavailable: insufficient eligible earlier years.`;
      const years=String(day[`record_${kind}_years`]||"").split(",").filter(Boolean).join(", ");
      const status=day[`record_${kind}_status`];
      const highlight=status===`NEW_${kind.toUpperCase()}`?` NEW ${label.toUpperCase()} within the eligible record.`:
        status===`TIED_${kind.toUpperCase()}`?` TIED ${label.toUpperCase()} within the eligible record.`:"";
      return ` Earlier record ${kind}: ${temp(value)} (${years}); ${day[`record_${kind}_n`]} valid years, `+
        `${day[`record_${kind}_first_year`]}–${day[`record_${kind}_last_year`]}.${highlight}`;
    }).join("");
  }
  function readout(day) {
    const delta=(observed,normal)=>finite(observed)&&finite(normal)?
      ` (${observed-normal>=0?"+":""}${(observed-normal).toFixed(1)}°F departure)`:"";
    const normal=!finite(day.normal_maxt)||!finite(day.normal_mint)?
      " Daily normal unavailable: insufficient reference support.":
      ` Normal high ${temp(day.normal_maxt)}${delta(day.maxt,day.normal_maxt)}; `+
      `normal low ${temp(day.normal_mint)}${delta(day.mint,day.normal_mint)}. `+
      `Reference support: at least ${day.normal_years} years per calendar day.`;
    return normal+recordReadout(day);
  }
  function legend(days,reference,records={}) {
    const available=days.some(d=>finite(d.normal_maxt)&&finite(d.normal_mint));
    const normal=available?
      '<p class="temperature-normal-legend"><span class="normal-high">High</span> · <span class="normal-low">Low</span> · Solid: observed · Dashed: 1991–2020 normal</p>':
      '<p class="temperature-normal-note">Normal lines unavailable for this period: insufficient 1991–2020 reference support.</p>';
    const hasRecords=days.some(d=>finite(d.record_high)||finite(d.record_low));
    const counts=[["high","High"],["low","Low"]].map(([kind,label])=>{
      const n=days.filter(d=>d[`record_${kind}_status`]===`NEW_${kind.toUpperCase()}`).length;
      const t=days.filter(d=>d[`record_${kind}_status`]===`TIED_${kind.toUpperCase()}`).length;
      return `${label}: ${n} new, ${t} tied`;
    }).join(" · ");
    return normal+(hasRecords?
      '<p class="temperature-record-legend">Dotted: earlier record · ◆ New record · ■ Tied record'+
        (days.length>90?`<br>${counts}`:'')+'</p>':
      `<p class="temperature-normal-note">Record lines unavailable: require ${records.minimum_years||30} earlier observations and ${records.minimum_calendar_span||30} years of history; leap days use actual earlier February 29 reports.</p>`);
  }
  return {paths,markers,readout,legend,recordReadout,bind,tooltip,hit,readoutHtml,renderReadout,
    precipitationObserved,precipitationTooltip,precipitationHit,precipitationReadoutHtml,
    precipitationBarStyle,precipitationLegend,precipitationDefinitions};
})();
