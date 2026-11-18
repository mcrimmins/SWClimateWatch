"use strict";
const $ = id => document.getElementById(id), finite = value => typeof value === "number" && Number.isFinite(value);
const inches = value => finite(value) ? `${value.toFixed(2)} in.` : "Unavailable";
const labelDate = value => new Date(`${value}T00:00:00Z`).toLocaleDateString("en-US", {month:"short",day:"numeric",timeZone:"UTC"});
let activeSeason = "water";
let catalog, data, selectedIndex = 0, lastIndex = 0, plotGeometry, selectionEpoch = 0;
let comparisonYear = null, comparisonValues = null, comparisonEpoch = 0;
const comparisonCache = new Map();
const cache = new Map(), colors = {current:"#167b80",previous:"#b86432",normal:"#647181"};
let annualYears = [], annualGeometry = null;
const recordLabels = {NEW_HIGH:"Above historical high",NEW_LOW:"Below historical low",TIED_HIGH:"Tied historical high",
  TIED_LOW:"Tied historical low",TIED_BOTH:"All historical years tied",WITHIN_RANGE:"Within historical range",UNAVAILABLE:"Historical comparison unavailable"};
function matchNote() {
  const match = data?.closest_match;
  if (!match?.available) return match?.note || "Closest match unavailable.";
  const tied = Array.isArray(match.tied_years) ? match.tied_years.length : 1;
  return `Closest progression through ${labelDate(match.cutoff_date || data.as_of)}: Season ${match.water_year} · ${match.days_compared} days${tied>1 ? ` · ${tied} tied (latest shown)` : ""}. ${match.early_season ? "Early-season match; " : ""}Not a forecast.`;
}
function recordYears(text) {
  const years = String(text || "").split(",").filter(Boolean).map(year=>`Season ${year}`);
  return years.length > 2 ? `${years.slice(0,2).join(", ")} + ${years.length-2} more` : years.join(", ");
}
function linePaths(points, key, x, y) {
  const segments = []; let path = "";
  points.forEach((point, index) => {
    if (!finite(point[key])) {if (path) segments.push(path); path = ""; return;}
    path += `${path ? "L" : "M"}${x(index).toFixed(2)},${y(point[key]).toFixed(2)} `;
  });
  if (path) segments.push(path);
  return segments;
}
function bandPaths(points, x, y) {
  const paths = []; let indices = [];
  const flush = () => {
    if (indices.length) paths.push(indices.map((i,j)=>`${j ? "L" : "M"}${x(i)},${y(points[i].upper)}`).join(" ") + " " +
      [...indices].reverse().map(i=>`L${x(i)},${y(points[i].lower)}`).join(" ") + " Z");
    indices = [];
  };
  points.forEach((point,i)=>{
    if (finite(point.lower) && finite(point.upper) && point.lower <= point.upper) indices.push(i);
    else flush();
  });
  flush(); return paths;
}
function plotPoints() {
  return data.points.map((point,i)=>({...point, previous:comparisonValues?.[i] ?? null}));
}
async function selectComparison() {
  if (!data) return;
  const epoch = ++comparisonEpoch, uid = data.uid, value = $("comparison-year").value;
  const closest = value === "closest";
  comparisonYear = value === "none" ? null : closest ? data.closest_match?.water_year : Number(value); comparisonValues = null;
  $("previous-label").hidden = !comparisonYear;
  $("previous-label").textContent = comparisonYear ? `Season ${comparisonYear}${closest ? " (closest)" : ""}` : "Comparison year";
  $("comparison-status").textContent = "";
  render();
  if (!comparisonYear) {if (closest) $("comparison-status").textContent = matchNote(); return;}
  const year = comparisonYear;
  try {
    const entry = data.comparison_years?.find(item=>item.water_year===year);
    const expected = `history/${uid}/${year}.json`;
    if (!entry || entry.file !== expected || year >= data.water_year) throw Error("Invalid comparison year.");
    let values;
    if (year === data.previous_water_year) values = data.points.map(point=>point.previous);
    else {
      $("comparison-status").textContent = `Loading Season ${year}…`;
      if (!comparisonCache.has(expected)) comparisonCache.set(expected,fetch(`${activeSeason}/${expected}`,{cache:"no-store"}).then(response=>{
        if (!response.ok) throw Error(`Comparison request failed (${response.status}).`); return response.json();
      }));
      const payload = await comparisonCache.get(expected);
      if (epoch !== comparisonEpoch || uid !== data?.uid) return;
      if (payload.schema_version !== 1 || payload.uid !== uid || payload.water_year !== year ||
          payload.calendar !== "season-month-day") throw Error("Comparison data do not match the selected station/year.");
      values = payload.values;
    }
    if (!Array.isArray(values) || values.length !== data.points.length || values.some((v,i)=>
      !finite(v) || v < 0 || (i>0 && v < values[i-1])) || Math.abs(values.at(-1)-entry.annual_total)>0.0001) {
      throw Error("Comparison curve is incomplete or invalid.");
    }
    if (epoch !== comparisonEpoch || uid !== data?.uid) return;
    comparisonValues = values; $("comparison-status").textContent = closest ? matchNote() : ""; render();
  } catch(error) {
    comparisonCache.delete(`history/${uid}/${year}.json`);
    if (epoch !== comparisonEpoch || uid !== data?.uid) return;
    $("comparison-status").textContent = `Season ${year} could not be loaded. Current and climatological curves remain available. ${error.message}`;
  }
}
function inspect(index) {
  if (!data || !plotGeometry) return;
  selectedIndex = Math.max(0,Math.min(lastIndex,Math.round(index)));
  $("inspect").value = String(selectedIndex);
  const point = {...data.points[selectedIndex], previous:comparisonValues?.[selectedIndex] ?? null}, {x,y} = plotGeometry;
  $("inspect").setAttribute("aria-valuetext", `${labelDate(point.date)}: current ${inches(point.current)}, comparison ${comparisonYear || "not selected"} ${inches(point.previous)}, average ${inches(point.normal)}`);
  $("cursor").setAttribute("x1",x(selectedIndex)); $("cursor").setAttribute("x2",x(selectedIndex));
  for (const key of Object.keys(colors)) {
    const marker = $(`marker-${key}`); marker.hidden = !finite(point[key]);
    marker.style.display = finite(point[key]) ? "" : "none";
    if (finite(point[key])) {marker.setAttribute("cx",x(selectedIndex)); marker.setAttribute("cy",y(point[key]));}
  }
  $("readout").replaceChildren();
  const date = document.createElement("strong"); date.textContent = labelDate(point.date); $("readout").append(date);
  for (const [key,title] of [["current",`Season ${data.water_year}`],["previous",`Season ${comparisonYear}`],["normal","Average"]]) {
    if (key === "previous" && !comparisonYear) continue;
    const span = document.createElement("span");
    let text = inches(point[key]);
    if (key === "current" && point.status === "FUTURE") text = "Not yet observed";
    else if (key === "current" && !finite(point.current) && finite(point.subtotal)) {
      text = `≥${point.subtotal.toFixed(2)} in. recorded; ${point.missing_days} missing, ${point.flagged_days} flagged`;
    } else if (key === "previous" && !finite(point.previous)) {
      text = "Unavailable";
    }
    span.textContent = `${title}: ${text}`; span.style.color = colors[key]; $("readout").append(span);
  }
  if (finite(point.lower) && finite(point.upper)) {
    const band = document.createElement("span");
    band.textContent = `Typical range: ${point.lower.toFixed(2)}–${point.upper.toFixed(2)} in.`;
    $("readout").append(band);
  }
  if (finite(point.record_high) && finite(point.record_low)) {
    const records = document.createElement("span"); records.className = "record-readout";
    records.textContent = `Historical high: ${inches(point.record_high)} (${recordYears(point.high_years)}) · Low: ${inches(point.record_low)} (${recordYears(point.low_years)})`;
    records.title = `High years: ${point.high_years}. Low years: ${point.low_years}. Complete historical seasons only.`;
    $("readout").append(records);
  }
}
function render() {
  if (!data) return;
  const observedIndex = data.points.findLastIndex(point => point.date <= data.as_of);
  lastIndex = $("period").value === "full" ? data.points.length-1 : Math.max(0,observedIndex);
  const points = plotPoints().slice(0,lastIndex+1), left = 62, right = 938, top = 24, bottom = 302;
  const max = Math.max(0.1,...points.flatMap(point => [...Object.keys(colors),"upper","record_high"].map(key => finite(point[key]) ? point[key] : 0)));
  const step = max <= 1 ? 0.2 : max <= 5 ? 1 : max <= 15 ? 3 : max <= 30 ? 5 : 10;
  const upper = Math.ceil(max/step)*step;
  const x = i => left + i/Math.max(1,lastIndex)*(right-left), y = value => bottom-value/upper*(bottom-top);
  plotGeometry = {x,y,left,right};
  let svg = `<text x="${left}" y="15" fill="#647882" font-size="12">Cumulative precipitation (inches)</text>`;
  for (let tick = 0; tick <= upper+step/2; tick += step) {
    svg += `<line x1="${left}" x2="${right}" y1="${y(tick)}" y2="${y(tick)}" stroke="#e2eaed"/>` +
      `<text x="${left-12}" y="${y(tick)+4}" text-anchor="end" fill="#647882" font-size="12">${Number(tick.toFixed(1))}</text>`;
  }
  const ticks = $("period").value === "full" ? points.map((p,i)=>p.month_day.endsWith("-01") ? i : -1).filter(i=>i>=0) :
    [...new Set(Array.from({length:Math.min(6,lastIndex+1)},(_,i)=>Math.round(i*lastIndex/Math.max(1,Math.min(5,lastIndex)))))];
  for (const i of ticks) svg += `<text x="${x(i)}" y="326" text-anchor="middle" fill="#647882" font-size="12">${labelDate(points[i].date)}</text>`;
  for (const path of bandPaths(points,x,y)) svg += `<path d="${path}" fill="#d5e8e3" fill-opacity="0.65" stroke="none"/>`;
  for (const key of ["record_low","record_high"]) for (const path of linePaths(points,key,x,y)) {
    svg += `<path d="${path}" fill="none" stroke="#89939c" stroke-width="1.2" stroke-dasharray="2 4"/>`;
  }
  for (const key of ["normal","previous","current"]) {
    for (const path of linePaths(points,key,x,y)) svg += `<path d="${path}" fill="none" stroke="${colors[key]}" stroke-width="${key === "current" ? 3 : 2}"${key === "previous" ? ' stroke-dasharray="7 4"' : ""}/>`;
  }
  svg += `<line id="cursor" y1="${top}" y2="${bottom}" stroke="#9aafb8" stroke-dasharray="3 4"/>`;
  for (const key of Object.keys(colors)) svg += `<circle id="marker-${key}" r="4" fill="${colors[key]}" stroke="white" stroke-width="1.5"/>`;
  $("plot").innerHTML = svg;
  $("inspect").max = String(lastIndex);
  inspect(Math.min(selectedIndex,lastIndex));
}
function inspectAnnual(index) {
  if (!annualGeometry || !annualYears.length) return;
  index = Math.max(0,Math.min(annualYears.length-1,Math.round(index)));
  const year = annualYears[index], entry = data.comparison_years.find(item=>item.water_year===year);
  const isCurrent = year === data.water_year;
  const normal = data.annual_history?.normal_inches;
  const percent = entry && finite(normal) && normal > 0 ? 100*entry.annual_total/normal : null;
  $("annual-inspect").value = String(index);
  $("annual-readout").textContent = isCurrent ? currentAnnualReadout() : `Season ${year}: ${entry ? inches(entry.annual_total) : "Incomplete / unavailable — no total shown"}` +
    (entry ? finite(percent) ? ` · ${percent.toFixed(0)}% of 1991–2020 average` : " · Percent of average unavailable" : "");
  $("annual-inspect").setAttribute("aria-valuetext",$("annual-readout").textContent);
  $("annual-cursor").setAttribute("x1",annualGeometry.x(index));
  $("annual-cursor").setAttribute("x2",annualGeometry.x(index));
}
function currentAnnualReadout() {
  const amount = finite(data.current.total) ? inches(data.current.total) :
    finite(data.current.observed_subtotal) ? `≥${data.current.observed_subtotal.toFixed(2)} in. recorded; ${data.current.missing_days} missing, ${data.current.flagged_days} flagged` : 'Unavailable';
  const complete = data.season_complete && finite(data.current.total);
  return `Latest Season ${data.water_year} through ${labelDate(data.as_of)}: ${amount} · ${complete ? 'Complete latest season' : 'Season to date — incomplete season'}`;
}
function renderAnnual() {
  const entries = Array.isArray(data.comparison_years) ? data.comparison_years : [];
  const summary = data.annual_history;
  if (!summary || !Number.isInteger(summary.first_year) ||
      summary.first_year > data.water_year-1 || data.water_year-summary.first_year > 500) {
    $("annual-history").hidden = true; annualGeometry = null; annualYears = []; return;
  }
  const valid = entries.every(item=>Number.isInteger(item.water_year) && item.water_year >= summary.first_year &&
    item.water_year < data.water_year && finite(item.annual_total) && item.annual_total >= 0);
  if (!valid || new Set(entries.map(item=>item.water_year)).size !== entries.length) {
    $("annual-history").hidden = true; annualGeometry = null; annualYears = []; return;
  }
  const first = summary.first_year, last = data.water_year-1;
  annualYears = Array.from({length:data.water_year-first+1},(_,i)=>first+i);
  const normal = summary.normal_inches, supported = finite(normal) && normal >= 0;
  const left=62,right=938,top=24,bottom=248;
  const currentAmount = finite(data.current.total) ? data.current.total : data.current.observed_subtotal;
  const maximum=Math.max(1,...entries.map(item=>item.annual_total),supported?normal:0,finite(currentAmount)?currentAmount:0);
  const step=maximum<=5?1:maximum<=15?3:maximum<=30?5:maximum<=60?10:20;
  const upper=Math.ceil(maximum/step)*step;
  const width=(right-left)/annualYears.length;
  const x=i=>left+(i+0.5)*width, y=value=>bottom-value/upper*(bottom-top);
  annualGeometry={x,left,right,width};
  let svg=`<defs><pattern id="current-year-hatch" patternUnits="userSpaceOnUse" width="6" height="6"><rect width="6" height="6" fill="white"/><path d="M-1,1 L1,-1 M0,6 L6,0 M5,7 L7,5" stroke="#516b76" stroke-width="1.5"/></pattern></defs>`+
    `<text x="${left}" y="15" fill="#647882" font-size="12">Seasonal precipitation (inches); current year is season to date</text>`;
  for(let tick=0;tick<=upper;tick+=step) svg+=
    `<line x1="${left}" x2="${right}" y1="${y(tick)}" y2="${y(tick)}" stroke="#e2eaed"/>`+
    `<text x="${left-12}" y="${y(tick)+4}" text-anchor="end" fill="#647882" font-size="12">${tick}</text>`;
  const byYear=new Map(entries.map(item=>[item.water_year,item]));
  annualYears.forEach((year,i)=>{
    const entry=byYear.get(year);
    if(year === data.water_year && finite(currentAmount)) {
      const height=Math.max(2,bottom-y(currentAmount));
      svg+=`<rect data-current-year="${year}" x="${x(i)-width*0.4}" y="${bottom-height}" width="${Math.max(1,width*0.8)}" height="${height}" fill="url(#current-year-hatch)" stroke="#334e59" stroke-width="1.2"/>`;
    } else if(entry) {
      const fill=!supported || Math.abs(entry.annual_total-normal)<0.0001 ? '#7c909b' : entry.annual_total>normal?'#25878c':'#bd874f';
      const height=Math.max(1,bottom-y(entry.annual_total));
      svg+=`<rect x="${x(i)-width*0.4}" y="${bottom-height}" width="${Math.max(1,width*0.8)}" height="${height}" fill="${fill}"/>`;
    } else svg+=`<path d="M${x(i)-2},${bottom-3} L${x(i)+2},${bottom+1} M${x(i)+2},${bottom-3} L${x(i)-2},${bottom+1}" stroke="#bcc8ce"/>`;
  });
  if(supported) svg+=`<line x1="${left}" x2="${right}" y1="${y(normal)}" y2="${y(normal)}" stroke="#647181" stroke-width="2" stroke-dasharray="5 4"/>`;
  const interval=annualYears.length>100?20:annualYears.length>45?10:5;
  const ticks=[0,...annualYears.map((year,i)=>year%interval===0?i:-1).filter(i=>i>0 && i<annualYears.length-1),annualYears.length-1];
  [...new Set(ticks)].forEach(i=>{if(i!==0 && i!==annualYears.length-1 && (i<3 || i>annualYears.length-4))return;
    svg+=`<text x="${x(i)}" y="273" text-anchor="middle" fill="#647882" font-size="12">${annualYears[i]}${annualYears[i]===data.water_year?'*':''}</text>`;});
  svg+=`<line id="annual-cursor" y1="${top}" y2="${bottom}" stroke="#273a42" stroke-dasharray="3 4"/>`;
  $("annual-plot").innerHTML=svg;
  $("annual-note").textContent=`Season ${first}–${last} · ${entries.length} complete earlier seasons · ${last-first+1-entries.length} incomplete or unavailable. ${data.role==='fixed'?'Fixed station':'ThreadEx area series'}.`;
  $("annual-normal-label").hidden=!supported;
  $("annual-normal-label").textContent=`1991–2020 average: ${inches(normal)} (${data.baseline.sample_years} complete years)`;
  $("annual-wet-label").textContent=supported?'Above average':'Complete total';
  $("annual-wet-label").className=supported?'annual-wet':'annual-total';
  $("annual-dry-label").hidden=$("annual-neutral-label").hidden=!supported;
  $("annual-current").textContent=currentAnnualReadout()+'. The hatched bar is excluded from completed-year comparisons; no end-of-year projection is shown.';
  $("annual-current").className=`quality annual-current${finite(data.current.total)?'':' caution'}`;
  $("annual-inspect").max=String(annualYears.length-1);
  $("annual-history").hidden=false;
  inspectAnnual(annualYears.length-1);
}
function showStation() {
  $("station-title").textContent = `${data.name} · ${data.state}`;
  $("annual-title").textContent = `Historical ${data.season_label.toLowerCase()} precipitation`;
  $("station-note").textContent = `${data.sid} · ${data.role === "fixed" ? "Fixed station" : "ThreadEx area"} · ${data.season_label} ${data.water_year}: ${data.season_start}–${data.season_end} · Data through ${data.as_of}` +
    (data.cache_as_of && data.cache_as_of < data.as_of ? ` · Cache only through ${data.cache_as_of}; later reports are missing` : "");
  $("current-label").textContent = `Season ${data.water_year}`;
  const years = data.baseline.water_years;
  $("normal-label").textContent = `Season ${years[0]}–${years.at(-1)} average (${data.baseline.sample_years} complete years)`;
  $("normal-label").hidden = $("band-label").hidden = !data.baseline.available;
  const history = data.historical_context;
  $("records-label").hidden = !history?.available;
  $("history-status").textContent = history?.available ?
    `Through ${labelDate(history.cutoff_date)}: ${recordLabels[history.current_status] || recordLabels.UNAVAILABLE} · Season ${history.first_year}–${history.last_year}, ${history.sample_years} complete historical years` : "Historical extremes require at least 30 complete historical seasons.";
  $("history-status").className = `history-status${history?.current_status === "NEW_HIGH" ? " high" : history?.current_status === "NEW_LOW" ? " low" : ""}`;
  $("stats").replaceChildren();
  for (const [value,title] of [[inches(data.current.total),`Season ${data.water_year} through ${labelDate(data.as_of)}`],
    [String(data.current.missing_days+data.current.flagged_days),"Missing or flagged days to date"],
    [String(data.baseline.sample_years),"Complete baseline seasons"]]) {
    const box = document.createElement("div"); box.className = "stat";
    const number = document.createElement("strong"), caption = document.createElement("span");
    number.textContent = value; caption.textContent = title; box.append(number,caption); $("stats").append(box);
  }
  const c = data.comparison;
  const signed = v => finite(v) ? `${v>=0?"+":""}${v.toFixed(2)} in.` : "unavailable";
  $("matched").textContent = `Matching period through ${labelDate(c.cutoff)}: ` +
    (c.available ? `wet rank #${c.wet_rank} of ${c.rank_sample} · ${c.percentile.toFixed(0)}th percentile · ` : "Rank/percentile unavailable · ") +
    `departure ${signed(c.departure_inches)} · ${finite(c.percent_average)?c.percent_average.toFixed(0)+"% of average":"percent of average unavailable"}. ` +
    `${c.historical_years} complete earlier matching periods; ${c.baseline_years} baseline periods. ${c.note}`;
  const incomplete = data.current.missing_days+data.current.flagged_days > 0;
  $("quality").className = `quality${incomplete || !data.baseline.available ? " caution" : ""}`;
  $("quality").textContent = incomplete ? "Current accumulation is incomplete. The line ends before the first missing or flagged report; later recorded amounts are lower bounds." :
    "Current accumulation is complete through the displayed cache date. Later comparison values are historical context, not a forecast.";
  if (!data.baseline.available) $("quality").textContent += " The climatological curve and band are withheld: too few complete reference years.";
  const selector = $("comparison-year"); selector.replaceChildren();
  const none = document.createElement("option"); none.value = "none"; none.textContent = "None"; selector.append(none);
  if (data.closest_match?.available) {
    const closest = document.createElement("option"); closest.value = "closest";
    closest.textContent = `Closest match · Season ${data.closest_match.water_year}`; selector.append(closest);
  }
  const yearsAvailable = Array.isArray(data.comparison_years) ? data.comparison_years : [];
  for (const item of yearsAvailable) {
    const option = document.createElement("option"); option.value = String(item.water_year);
    option.textContent = `Season ${item.water_year}${item.water_year===data.previous_water_year ? " (previous)" : ""}`; selector.append(option);
  }
  const initial = yearsAvailable.find(item=>item.water_year===data.previous_water_year) || yearsAvailable[0];
  selector.value = initial ? String(initial.water_year) : "none"; selector.disabled = false;
  selectedIndex = Math.max(0,data.points.findLastIndex(point=>point.date<=data.as_of)); selectComparison();
  renderAnnual();
}
async function selectStation() {
  const epoch = ++selectionEpoch, uid = Number($("station").value);
  activeSeason = $("season").value; const stationKey = `${activeSeason}/${uid}`;
  comparisonCache.clear();
  comparisonEpoch++; comparisonValues = null; comparisonYear = null;
  $("comparison-year").disabled = true;
  $("error").hidden = true;
  $("station-card").hidden = true;
  $("annual-history").hidden = true; annualGeometry = null; annualYears = [];
  $("station-card").setAttribute("aria-busy","true");
  try {
    const entry = catalog.stations.find(station=>station.uid===uid);
    if (!entry || entry.file !== `${uid}.json`) throw Error("Invalid station selection.");
    if (!cache.has(stationKey)) cache.set(stationKey,fetch(`${activeSeason}/${entry.file}`,{cache:"no-store"}).then(response=>{
      if (!response.ok) throw Error(`Station request failed (${response.status}).`); return response.json();
    }));
    const payload = await cache.get(stationKey);
    if (epoch !== selectionEpoch) return;
    if (payload.available === false) throw Error(payload.note || "Cumulative precipitation unavailable.");
    if (payload.schema_version !== 1 || payload.uid !== uid || payload.snapshot_date !== catalog.as_of ||
        !Array.isArray(payload.points) || payload.season !== activeSeason || payload.points.length < 1) throw Error("Invalid cumulative station data.");
    data = payload; showStation();
    $("station-card").hidden = false; $("station-card").setAttribute("aria-busy","false");
  } catch(error) {
    cache.delete(stationKey);
    if (epoch === selectionEpoch) {
      $("station-card").setAttribute("aria-busy","false");
      $("error").hidden = false; $("error").textContent = error.message;
    }
  }
}
async function initialize() {
  try {
    const query = new URLSearchParams(typeof window === "undefined" ? "" : window.location.search);
    const embedded = query.get("embedded") === "1";
    if (embedded) {
      document.body.classList.add("embedded");
      if (typeof ResizeObserver !== "undefined") {
        const main = document.querySelector("main");
        new ResizeObserver(()=>window.parent.postMessage({type:"swc-cumulative-height",
          height:Math.ceil(main.getBoundingClientRect().height)+40},window.location.origin)).observe(main);
      }
    }
    const response = await fetch("stations.json",{cache:"no-store"});
    if (!response.ok) throw Error(`Cumulative station request failed (${response.status}).`);
    catalog = await response.json();
    if (catalog.schema_version !== 1 || !Array.isArray(catalog.stations) || !catalog.stations.length) throw Error("No cumulative station records available.");
    if (query.has("as_of") && query.get("as_of") !== catalog.as_of) throw Error("Cumulative data do not match this station page date. Refresh the page.");
    $("snapshot").textContent = `Select a season to compare matching periods · Cached observations through ${catalog.as_of}`;
    for (const station of catalog.stations) {
      const option = document.createElement("option"); option.value = String(station.uid); option.textContent = `${station.name} · ${station.state}`; $("station").append(option);
    }
    if (query.has("uid")) {
      if (!catalog.stations.some(station=>String(station.uid)===query.get("uid"))) throw Error("Cumulative data are unavailable for this station.");
      $("station").value = query.get("uid");
    }
    $("station").addEventListener("change",selectStation); $("season").addEventListener("change",selectStation); $("period").addEventListener("change",render);
    $("comparison-year").addEventListener("change",selectComparison);
    $("inspect").addEventListener("input",()=>inspect(Number($("inspect").value)));
    const hover = event => {
      if (!plotGeometry) return;
      const rect = $("plot").getBoundingClientRect(), svgX = (event.clientX-rect.left)*960/rect.width;
      inspect((svgX-plotGeometry.left)/(plotGeometry.right-plotGeometry.left)*lastIndex);
    };
    $("plot").addEventListener("pointermove",hover); $("plot").addEventListener("pointerdown",hover);
    $("annual-inspect").addEventListener("input",()=>inspectAnnual(Number($("annual-inspect").value)));
    const annualHover=event=>{
      if(!annualGeometry)return;
      const rect=$("annual-plot").getBoundingClientRect(), sx=(event.clientX-rect.left)*960/rect.width;
      inspectAnnual((sx-annualGeometry.left)/annualGeometry.width-0.5);
    };
    $("annual-plot").addEventListener("pointermove",annualHover);
    $("annual-plot").addEventListener("pointerdown",annualHover);
    await selectStation();
  } catch(error) {$("error").hidden = false; $("error").textContent = `${error.message} Open this plot through the site or a local preview server.`;}
}
initialize();
