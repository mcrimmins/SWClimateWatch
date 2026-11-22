/* Isolated pilot: cached reports only. Source text always enters as textContent. */
(() => {
  "use strict";
  const $ = id => document.getElementById(id);
  const groups = {
    rain:{label:"Rainfall",color:"#287b40",symbol:"R"},
    flash:{label:"Flash flood",color:"#b34c16",symbol:"FF"},
    flood:{label:"Flood",color:"#176aa0",symbol:"F"},
    snow:{label:"Snow / ice",color:"#6651a6",symbol:"S"},
    wind:{label:"Wind / dust",color:"#9a6518",symbol:"W"},
    hail:{label:"Hail",color:"#398047",symbol:"H"},
    tornado:{label:"Tornado",color:"#af2635",symbol:"T"},
    other:{label:"Other reports",color:"#596975",symbol:"•"}
  };
  function category(type) {
    if (/FLASH FLOOD/.test(type)) return "flash";
    if (/FLOOD/.test(type)) return "flood";
    if (/RAIN/.test(type)&&!/FREEZ/.test(type)) return "rain";
    if (/SNOW|ICE|SLEET|BLIZZARD|FREEZ/.test(type)) return "snow";
    if (/TORNADO|FUNNEL/.test(type)) return "tornado";
    if (/HAIL/.test(type)) return "hail";
    if (/WND|WIND|DUST|DOWNBURST/.test(type)) return "wind";
    return "other";
  }
  const node = (tag,text) => {const e=document.createElement(tag); if(text!=null)e.textContent=text; return e;};
  const shift = (date,n) => {const d=new Date(`${date}T00:00:00Z`);d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
  const dateLabel = date => new Date(`${date}T00:00:00Z`).toLocaleDateString("en-US",{month:"short",day:"numeric",year:"numeric",timeZone:"UTC"});
  const eventLabel = r => `${dateLabel(r.date)} · ${r.valid.slice(11,16)} UTC`;
  const magnitude = r => r.magnitude === "" ? "Not specified" : `${r.magnitude}${r.unit ? ` ${r.unit}` : " (unit not supplied)"}`;
  const timeLabel=ms=>{const s=new Date(ms).toISOString();return `${dateLabel(s.slice(0,10))}, ${s.slice(11,16)} UTC`;};
  function reportWindow(date,n,timing) {
    const prism=timing==="prism";
    const start=Date.parse(`${shift(date,prism?-n:1-n)}T${prism?"12":"00"}:00:00Z`);
    const end=Date.parse(`${prism?date:shift(date,1)}T${prism?"12":"00"}:00:00Z`);
    const dates=[];
    for(let d=new Date(start).toISOString().slice(0,10);Date.parse(`${d}T00:00:00Z`)<end;d=shift(d,1))dates.push(d);
    return {start,end,dates};
  }
  // Compact lower-bound labels only; exact source precision stays in details.
  const rainAmount=r=>{
    if(category(r.type)!=="rain"||!/^\d+(\.\d+)?$/.test(r.magnitude)||
      !/^(inch(es)?|in\.?)$/i.test(r.unit))return "";
    const value=Number(r.magnitude);
    if(!Number.isFinite(value))return "";
    return value===0?"0":value<1?"<1":`${Math.floor(value)}+`;
  };
  let catalog, selection={date:"",region:"AZNM"}, map, layer, hoverCard, selected="", epoch=0, all=[], filtered=[], page=0;
  const markers=new Map(), cache=new Map(), pageSize=40;
  let catalogError="";
  let timelineEpoch=0;
  async function renderReportTimeline() {
    const timeline=$("timeline");if(!timeline?.querySelectorAll)return;
    const token=++timelineEpoch,region=$("region").value,timing=$("storm-timing").value;
    const manifest=await catalogPromise;if(token!==timelineEpoch)return;
    const summaries=new Map((manifest?.timeline?.[timing]||[]).map(d=>[d.date,d]));
    timeline.classList.add("storm-timeline");
    const used=new Set();
    $("storm-timeline-note").textContent=`Storm reports per day · ${timing==="prism"?"matches precipitation maps":"UTC calendar days"} · all report types. + indicates partial coverage; ? means unavailable.`;
    $("storm-timeline-detail").textContent="Hover or focus a day for report counts by type. Select a bar to explore that day.";
    for(const button of timeline.querySelectorAll(".day[data-report-date]")) {
      button.querySelector(".storm-day-summary")?.remove();
      const date=button.dataset.reportDate,day=summaries.get(date),summary=day?.regions?.[region];
      const strip=node("span");strip.className="storm-day-summary";strip.setAttribute("aria-hidden","true");
      strip.append(node("strong",summary?`${summary.total}${day.complete?"":"+"}`:"?"));
      const dots=node("span");dots.className="storm-day-types";
      const types=Object.entries(summary?.types||{});
      const dayGroups=new Set(types.filter(([,count])=>count>0).map(([type])=>category(type)));
      for(const key of Object.keys(groups).filter(key=>dayGroups.has(key))) {
        const dot=node("span");dot.style.background=groups[key].color;dots.append(dot);used.add(key);
      }
      strip.append(dots);button.append(strip);
      const range=reportWindow(date,1,timing);
      const text=`${dateLabel(date)} · ${timeLabel(range.start)} – ${timeLabel(range.end)}: ${summary?`${day.complete?"":"at least "}${summary.total} storm reports${day.complete?"":" (partial coverage)"}${types.length?`; ${types.map(([type,count])=>`${type}: ${count}`).join("; ")}`:""}`:"storm reports unavailable"}. Counts are reports, not unique storms.`;
      button.dataset.reportBaseTitle??=button.title;
      button.title=`${button.dataset.reportBaseTitle}\n${text}`;
      button.setAttribute("aria-label",button.title);
      // Assign properties so timing changes don't accumulate event handlers.
      button.onmouseenter=button.onfocus=()=>{$("storm-timeline-detail").textContent=text;};
    }
    $("storm-timeline-legend").replaceChildren();
    for(const key of Object.keys(groups).filter(key=>used.has(key))) {
      const span=node("span",`${groups[key].symbol} ${key==="rain"?"Rainfall":groups[key].label}`);
      span.style.setProperty("--report-color",groups[key].color);$("storm-timeline-legend").append(span);
    }
  }
  const catalogPromise=fetch("storm-reports-manifest.json",{cache:"no-store"}).then(r=>{
    if(!r.ok)throw new Error(`Catalog HTTP ${r.status}`);return r.json();
  }).then(x=>{
    if(x.schema_version!==1||!Array.isArray(x.days))throw new Error("Invalid report catalog");
    catalog=x;
    $("storm-provenance").textContent=`Oldest source snapshot retrieved ${x.fetched_utc}. Coverage ${dateLabel(x.start)}–${dateLabel(shift(x.end_exclusive,-1))} UTC.`;
    return x;
  }).catch(e=>{catalogError=e.message;return null;});

  function initializeMap() {
    if(map)return;
    if(typeof L==="undefined") {$("storm-map").textContent="Map library unavailable. Reports are available in the table.";return;}
    map=L.map("storm-map",{scrollWheelZoom:false}).setView([34.5,-109],5);
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",{maxZoom:18,
      attribution:'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'}).addTo(map);
    layer=L.layerGroup().addTo(map);
    // Keep hover text inside the map instead of letting Leaflet size a tooltip
    // relative to an 18px marker or place it beyond the map's edge.
    hoverCard=node("div");hoverCard.className="storm-hover-card";hoverCard.hidden=true;
    hoverCard.setAttribute("aria-hidden","true");$("storm-map").append(hoverCard);
  }
  const reportTitle=r=>`${r.type}${r.magnitude!==""?` · ${magnitude(r)}`:""}`;
  const bulletinLabel=r=>{
    if(!/^\d{12}-/.test(r.product_id))return "Bulletin time unavailable";
    const s=r.product_id.slice(0,12);
    return `Bulletin issued ${dateLabel(`${s.slice(0,4)}-${s.slice(4,6)}-${s.slice(6,8)}`)} ${s.slice(8,10)}:${s.slice(10,12)} UTC`;
  };
  function details(r) {
    const box=node("div");box.append(node("h3",reportTitle(r)));
    box.append(node("p",`${eventLabel(r)} · ${r.city}, ${r.state}`));
    const remark=r.remark||"No additional report text supplied.";
    box.append(node("p",remark));
      box.append(node("p",`${r.county || "County unspecified"} · Reported by ${r.source||"unspecified source"} · NWS ${r.wfo} · Magnitude: ${r.qualifier.toLowerCase()}.`));
      if(!r.mapped)box.append(node("p","This report has no usable coordinates and is listed in the table only."));
      if(/^\d{12}-[A-Z0-9]{4}-[A-Z0-9]{6}-[A-Z0-9]+$/.test(r.product_id)) {
        const [stamp,center,header,pil]=r.product_id.split("-");
        const issued=`${stamp.slice(0,4)}-${stamp.slice(4,6)}-${stamp.slice(6,8)}T${stamp.slice(8,10)}:${stamp.slice(10,12)}:00Z`;
        const params=new URLSearchParams({pil,center,ttaaii:header,sdate:issued,
          edate:new Date(Date.parse(issued)+60000).toISOString(),fmt:"html",limit:"1"});
        const a=node("a","Read issuing NWS bulletin ↗");a.href=`https://mesonet.agron.iastate.edu/cgi-bin/afos/retrieve.py?${params}`;
        a.target="_blank";a.rel="noopener";box.append(a);
      }
    return box;
  }
  function hidePreview(){if(hoverCard)hoverCard.hidden=true;}
  function updateSelectionStyles() {
    const active=markers.get(selected);
    for(const m of new Set(markers.values())) {
      m.getElement()?.classList.toggle("active",m===active);
      m.getElement()?.setAttribute("aria-pressed",String(m===active));
    }
    for(const row of $("storm-rows").children) {
      row.classList.toggle("selected",row.dataset.id===selected);
      row.querySelector?.("button")?.setAttribute("aria-pressed",String(row.dataset.id===selected));
    }
  }
  function clearSelection() {
    selected="";hidePreview();$("storm-location-choice").hidden=true;
    $("storm-detail").replaceChildren(node("p","Click or tap a marker or table row to select a report."));
    $("storm-clear").disabled=true;updateSelectionStyles();
  }
  function select(r,{pan=false,scroll=false}={}) {
    hidePreview();$("storm-location-choice").hidden=true;
    selected=r.id;$("storm-detail").replaceChildren(details(r));
    $("storm-clear").disabled=false;updateSelectionStyles();
    if(pan&&markers.has(r.id))map.panTo([r.lat,r.lon]);
    if(scroll) {
      const index=filtered.findIndex(x=>x.id===r.id);
      if(index>=0&&Math.floor(index/pageSize)!==page){page=Math.floor(index/pageSize);renderTable();}
      const row=Array.from($("storm-rows").children).find(x=>x.dataset.id===selected);
      if(row){const container=$("storm-rows").closest(".storm-table-scroll");container.scrollTop=row.offsetTop-container.offsetTop-45;}
    }
  }
  function preview(reports) {
    if(!hoverCard)return;
    const r=reports[0],box=node("div");
    box.append(node("h3",reports.length===1?reportTitle(r):`${reports.length} reports at this location`));
    box.append(node("p",`${r.city}, ${r.state}`));
    box.append(node("p",reports.length===1?eventLabel(r):[...new Set(reports.map(x=>x.type))].join(" · ")));
    box.append(node("small",reports.length===1?"Click to select. Full text below the map.":"Click to choose a report below the map."));
    hoverCard.replaceChildren(box);hoverCard.hidden=false;
  }
  function chooseLocation(reports) {
    hidePreview();
    if(reports.length===1){select(reports[0],{scroll:true});return;}
    const choices=$("storm-location-choice"),list=node("ul");
    choices.replaceChildren(node("h4",`${reports.length} reports at ${reports[0].city}, ${reports[0].state}`),
      node("p","Choose a report. Your selected report stays below until you choose another."),list);
    for(const r of reports) {
      const item=node("li"),button=node("button",`${reportTitle(r)} · ${eventLabel(r)} · ${r.remark.slice(0,100)}${r.remark.length>100?"…":""} · ${bulletinLabel(r)}`);
      button.type="button";button.addEventListener("click",()=>select(r,{scroll:true}));
      item.append(button);list.append(item);
    }
    choices.hidden=false;
  }
  function renderTable() {
    const body=$("storm-rows");body.replaceChildren();
    for(const r of filtered.slice(page*pageSize,(page+1)*pageSize)) {
      const row=node("tr");row.dataset.id=r.id;row.classList.toggle("selected",r.id===selected);
      row.append(node("td",eventLabel(r)));
      const type=node("td"),button=node("button",r.type);button.type="button";
      button.setAttribute("aria-label",`Show ${r.type}, ${r.city}, ${eventLabel(r)}`);
      button.setAttribute("aria-pressed",String(r.id===selected));
      type.append(button);row.append(type,node("td",magnitude(r)),node("td",`${r.city}, ${r.state}`));
      const text=node("td"),snippet=node("span",r.remark||"No additional text");snippet.className="report-snippet";text.append(snippet);row.append(text);
      row.addEventListener("click",()=>select(r,{pan:true}));
      // Keyboard activation of the native button bubbles through the same row.
      body.append(row);
    }
    if(!filtered.length){const row=node("tr"),cell=node("td","No matching reports in the available data. See coverage status above.");cell.colSpan=5;row.append(cell);body.append(row);}
    $("storm-page-status").textContent=filtered.length ? `${page*pageSize+1}–${Math.min((page+1)*pageSize,filtered.length)} of ${filtered.length} reports · earliest first` : "0 matching reports";
    $("storm-page-previous").disabled=page===0;$("storm-page-next").disabled=(page+1)*pageSize>=filtered.length;
  }
  function renderReports() {
    const type=$("storm-type").value,query=$("storm-search").value.toLocaleLowerCase();
    filtered=all.filter(r=>(type==="all"||r.type===type)&&[r.city,r.county,r.type,r.remark,r.source,r.wfo].join(" ").toLocaleLowerCase().includes(query));
    if(selected&&!filtered.some(r=>r.id===selected))clearSelection();
    $("storm-location-choice").hidden=true;
    initializeMap();layer?.clearLayers();markers.clear();if(hoverCard)hoverCard.hidden=true;
    const locations=new Map();
    for(const r of filtered.filter(x=>x.mapped)) {
      const key=`${r.lat},${r.lon}`;if(!locations.has(key))locations.set(key,[]);locations.get(key).push(r);
    }
    if(layer) for(const reports of locations.values()) {
      const r=reports[0];
      const mixed=new Set(reports.map(x=>category(x.type))).size>1;
      const group=groups[mixed?"other":category(r.type)],icon=document.createElement("span");icon.style.setProperty("--report-color",group.color);icon.textContent=group.symbol;
      const amount=reports.length===1?rainAmount(r):"";
      if(amount)icon.textContent=amount;
      if(reports.length>1)icon.textContent=String(reports.length);
      const marker=L.marker([r.lat,r.lon],{keyboard:true,
        icon:L.divIcon({className:`storm-marker${amount?" rain-amount":""}`,html:icon.outerHTML,
          iconSize:amount?[26,18]:[18,18],iconAnchor:amount?[13,9]:[9,9]})});
      const showHover=()=>preview(reports);
      marker.on("mouseover",showHover);marker.on("mouseout",hidePreview);
      marker.on("click",()=>chooseLocation(reports));
      marker.addTo(layer);for(const report of reports)markers.set(report.id,marker);
      marker.getElement()?.setAttribute("role","button");
      marker.getElement()?.setAttribute("aria-label",reports.length===1?`${r.type}${r.magnitude!==""?`, ${magnitude(r)}`:""}, ${r.city}, ${eventLabel(r)}. Select report.`:`${reports.length} reports at ${r.city}, ${r.state}. Choose a report.`);
      marker.getElement()?.addEventListener("focus",showHover);
      marker.getElement()?.addEventListener("blur",hidePreview);
    }
    $("storm-legend").replaceChildren();
    for(const key of [...new Set(filtered.map(r=>category(r.type)))]) {
      const g=groups[key],span=node("span",`${g.symbol} ${g.label}`);span.style.setProperty("--report-color",g.color);$("storm-legend").append(span);
    }
    if([...locations.values()].some(rows=>rows.length>1))$("storm-legend").append(node("small","Numbered circles = reports sharing a location; click to choose. Rain amounts are individual reports, not window totals."));
    page=0;renderTable();updateSelectionStyles();
  }
  async function loadDay(entry) {
    if(!entry||!['READY','EMPTY'].includes(entry.status))throw new Error("Date not cached");
    if(!/^reports\/\d{4}-\d{2}-\d{2}\.json$/.test(entry.path))throw new Error("Invalid report path");
    if(!cache.has(entry.path))cache.set(entry.path,fetch(entry.path).then(async r=>{
      if(!r.ok)throw new Error(`Reports HTTP ${r.status}`);const x=await r.json();
      if(x.date!==entry.date||x.schema_version!==1||!Array.isArray(x.reports)||x.reports.length!==entry.reports)throw new Error("Report data mismatch");return x.reports;
    }).catch(e=>{cache.delete(entry.path);throw e;}));
    return cache.get(entry.path);
  }
  async function refresh() {
    const token=++epoch,date=selection.date,region=selection.region;
    if(!date)return;
    $("storm-date").value=date;$("storm-date").min=$("date").min;$("storm-date").max=$("date").max;
    $("storm-date-label").textContent=`· Map date ${dateLabel(date)} · ${region==="AZNM"?"Arizona & New Mexico":region}`;
    const n=Number($("storm-window").value),timing=$("storm-timing").value;
    const window=reportWindow(date,n,timing),dates=window.dates;
    $("storm-window-caption").textContent=`${timing==="prism"?"Matching precipitation map":"UTC calendar day"} · ${timeLabel(window.start)} – ${timeLabel(window.end)}${timing==="prism"?" (5 a.m. MST / 6 a.m. MDT endpoints)":""}. Event times; starting time included, ending time excluded.`;
    $("storm-previous").disabled=!$("date").min||date<=$("date").min;
    $("storm-next").disabled=!$("date").max||date>=$("date").max;
    if(!$("storm-panel").open)return;
    $("storm-status").textContent="Loading cached reports…";
    all=[];renderReports();
    const manifest=await catalogPromise;if(token!==epoch)return;
    if(!manifest){$("storm-status").textContent=`Reports unavailable: ${catalogError}. This does not mean no reports occurred.`;return;}
    const entries=new Map(manifest.days.map(x=>[x.date,x]));
    const results=await Promise.allSettled(dates.map(d=>loadDay(entries.get(d))));
    if(token!==epoch)return;
    const missing=dates.filter((_,i)=>results[i].status==="rejected");
    all=results.filter(x=>x.status==="fulfilled").flatMap(x=>x.value).filter(r=>{
      const time=Date.parse(r.valid);
      return time>=window.start&&time<window.end&&(region==="AZNM"||r.state===region);
    });
    const ids=new Set();all=all.filter(r=>!ids.has(r.id)&&ids.add(r.id)).sort((a,b)=>a.valid.localeCompare(b.valid)||a.id.localeCompare(b.id));
    const typeValue=$("storm-type").value,types=[...new Set(all.map(r=>r.type))].sort();
    $("storm-type").replaceChildren(new Option("All report types","all"),...types.map(x=>new Option(x,x)));
    // A selected type remains selected when the date/region has no such reports.
    if(typeValue!=="all"&&!types.includes(typeValue))$("storm-type").append(new Option(`${typeValue} (none in this window)`,typeValue));
    $("storm-type").value=typeValue;
    const missingRanges=[];
    for(const d of missing) {
      const start=Math.max(window.start,Date.parse(`${d}T00:00:00Z`));
      const end=Math.min(window.end,Date.parse(`${shift(d,1)}T00:00:00Z`));
      if(missingRanges.at(-1)?.end===start)missingRanges.at(-1).end=end;
      else missingRanges.push({start,end});
    }
    const gaps=missingRanges.map(g=>`${timeLabel(g.start)} – ${timeLabel(g.end)}`);
    const coverage=missing.length ? `PARTIAL / UNAVAILABLE: report data missing for ${gaps.join("; ")}.` : "Complete report coverage for this window.";
    $("storm-status").textContent=`${all.length} reports before type/search filters. ${coverage}${all.length===0&&!missing.length?" No reports were returned; this does not imply no significant weather.":""}${all.some(r=>!r.mapped)?" Some reports have no coordinates; see the table.":""}`;
    renderReports();map?.invalidateSize();
  }
  document.addEventListener("swc:daily-selection",e=>{
    renderReportTimeline();
    const next=e.detail;if(!next?.date)return;
    if(selection.date===next.date&&selection.region===next.region){$("storm-date").value=next.date;return;}
    selection={...next};refresh();
  });
  $("storm-panel").addEventListener("toggle",()=>{if($("storm-panel").open)refresh();});
  $("storm-window").addEventListener("change",refresh);
  $("storm-timing").addEventListener("change",()=>{renderReportTimeline();return refresh();});
  $("storm-type").addEventListener("change",renderReports);
  $("storm-clear").addEventListener("click",clearSelection);
  $("storm-search").addEventListener("input",renderReports);
  $("storm-page-previous").addEventListener("click",()=>{page=Math.max(0,page-1);renderTable();});
  $("storm-page-next").addEventListener("click",()=>{page=Math.min(Math.ceil(filtered.length/pageSize)-1,page+1);renderTable();});
  const requestDate=date=>document.dispatchEvent(new CustomEvent("swc:request-date",{detail:{date}}));
  $("storm-date").addEventListener("change",()=>requestDate($("storm-date").value));
  $("storm-previous").addEventListener("click",()=>requestDate(shift(selection.date,-1)));
  $("storm-next").addEventListener("click",()=>requestDate(shift(selection.date,1)));
  $("storm-reset").addEventListener("click",()=>{
    const bounds=selection.region==="AZ"?[[31.2,-115],[37.1,-108.8]]:selection.region==="NM"?[[31.2,-109.2],[37.1,-102.8]]:[[31.2,-115],[37.1,-102.8]];
    map?.fitBounds(bounds,{padding:[15,15]});
  });
  // Recover the initial selection even if Explorer's fast local fetch finished
  // before this deferred module loaded. Later changes use the same event.
  document.dispatchEvent(new CustomEvent("swc:request-selection"));
})();
