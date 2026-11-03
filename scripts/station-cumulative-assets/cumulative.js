"use strict";
const $ = id => document.getElementById(id), finite = value => typeof value === "number" && Number.isFinite(value);
const inches = value => finite(value) ? `${value.toFixed(2)} in.` : "Unavailable";
const labelDate = value => new Date(`${value}T00:00:00Z`).toLocaleDateString("en-US", {month:"short",day:"numeric",timeZone:"UTC"});
let catalog, data, selectedIndex = 0, lastIndex = 0, plotGeometry, selectionEpoch = 0;
let comparisonYear = null, comparisonValues = null, comparisonEpoch = 0;
const comparisonCache = new Map();
const cache = new Map(), colors = {current:"#167b80",previous:"#b86432",normal:"#647181"};
const recordLabels = {NEW_HIGH:"Above historical high",NEW_LOW:"Below historical low",TIED_HIGH:"Tied historical high",
  TIED_LOW:"Tied historical low",TIED_BOTH:"All historical years tied",WITHIN_RANGE:"Within historical range",UNAVAILABLE:"Historical comparison unavailable"};
function matchNote() {
  const match = data?.closest_match;
  if (!match?.available) return match?.note || "Closest match unavailable.";
  const tied = Array.isArray(match.tied_years) ? match.tied_years.length : 1;
  return `Closest progression through ${labelDate(match.cutoff_date || data.as_of)}: WY${match.water_year} · ${match.days_compared} days${tied>1 ? ` · ${tied} tied (latest shown)` : ""}. ${match.early_season ? "Early-season match; " : ""}Not a forecast.`;
}
function recordYears(text) {
  const years = String(text || "").split(",").filter(Boolean).map(year=>`WY${year}`);
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
  $("previous-label").textContent = comparisonYear ? `WY${comparisonYear}${closest ? " (closest)" : ""}` : "Comparison year";
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
      $("comparison-status").textContent = `Loading WY${year}…`;
      if (!comparisonCache.has(expected)) comparisonCache.set(expected,fetch(expected,{cache:"no-store"}).then(response=>{
        if (!response.ok) throw Error(`Comparison request failed (${response.status}).`); return response.json();
      }));
      const payload = await comparisonCache.get(expected);
      if (epoch !== comparisonEpoch || uid !== data?.uid) return;
      if (payload.schema_version !== 1 || payload.uid !== uid || payload.water_year !== year ||
          payload.calendar !== "month-day-365") throw Error("Comparison data do not match the selected station/year.");
      values = payload.values;
    }
    if (!Array.isArray(values) || values.length !== 365 || values.some((v,i)=>
      !finite(v) || v < 0 || (i>0 && v < values[i-1])) || Math.abs(values.at(-1)-entry.annual_total)>0.0001) {
      throw Error("Comparison curve is incomplete or invalid.");
    }
    if (epoch !== comparisonEpoch || uid !== data?.uid) return;
    comparisonValues = values; $("comparison-status").textContent = closest ? matchNote() : ""; render();
  } catch(error) {
    comparisonCache.delete(`history/${uid}/${year}.json`);
    if (epoch !== comparisonEpoch || uid !== data?.uid) return;
    $("comparison-status").textContent = `WY${year} could not be loaded. Current and climatological curves remain available. ${error.message}`;
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
  for (const [key,title] of [["current",`WY${data.water_year}`],["previous",`WY${comparisonYear}`],["normal","Average"]]) {
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
    records.title = `High years: ${point.high_years}. Low years: ${point.low_years}. Complete historical water years only.`;
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
function showStation() {
  $("station-title").textContent = `${data.name} · ${data.state}`;
  $("station-note").textContent = `${data.sid} · ${data.role === "fixed" ? "Fixed station" : "ThreadEx area"} · Water year ${data.water_year}: October 1–September 30 · Data through ${data.as_of}` +
    (data.cache_as_of && data.cache_as_of < data.as_of ? ` · Cache only through ${data.cache_as_of}; later reports are missing` : "");
  $("current-label").textContent = `WY${data.water_year}`;
  const years = data.baseline.water_years;
  $("normal-label").textContent = `WY${years[0]}–${years.at(-1)} average (${data.baseline.sample_years} complete years)`;
  $("normal-label").hidden = $("band-label").hidden = !data.baseline.available;
  const history = data.historical_context;
  $("records-label").hidden = !history?.available;
  $("history-status").textContent = history?.available ?
    `Through ${labelDate(history.cutoff_date)}: ${recordLabels[history.current_status] || recordLabels.UNAVAILABLE} · WY${history.first_year}–${history.last_year}, ${history.sample_years} complete historical years` : "Historical extremes require at least 20 complete historical water years.";
  $("history-status").className = `history-status${history?.current_status === "NEW_HIGH" ? " high" : history?.current_status === "NEW_LOW" ? " low" : ""}`;
  $("stats").replaceChildren();
  for (const [value,title] of [[inches(data.current.total),`WY${data.water_year} through ${labelDate(data.as_of)}`],
    [String(data.current.missing_days+data.current.flagged_days),"Missing or flagged days to date"],
    [String(data.baseline.sample_years),"Complete baseline water years"]]) {
    const box = document.createElement("div"); box.className = "stat";
    const number = document.createElement("strong"), caption = document.createElement("span");
    number.textContent = value; caption.textContent = title; box.append(number,caption); $("stats").append(box);
  }
  const incomplete = data.current.missing_days+data.current.flagged_days > 0;
  $("quality").className = `quality${incomplete || !data.baseline.available ? " caution" : ""}`;
  $("quality").textContent = incomplete ? "Current accumulation is incomplete. The line ends before the first missing or flagged report; later recorded amounts are lower bounds." :
    "Current accumulation is complete through the displayed cache date. Later comparison values are historical context, not a forecast.";
  if (!data.baseline.available) $("quality").textContent += " The climatological curve and band are withheld: too few complete reference years.";
  const selector = $("comparison-year"); selector.replaceChildren();
  const none = document.createElement("option"); none.value = "none"; none.textContent = "None"; selector.append(none);
  if (data.closest_match?.available) {
    const closest = document.createElement("option"); closest.value = "closest";
    closest.textContent = `Closest match · WY${data.closest_match.water_year}`; selector.append(closest);
  }
  const yearsAvailable = Array.isArray(data.comparison_years) ? data.comparison_years : [];
  for (const item of yearsAvailable) {
    const option = document.createElement("option"); option.value = String(item.water_year);
    option.textContent = `WY${item.water_year}${item.water_year===data.previous_water_year ? " (previous)" : ""}`; selector.append(option);
  }
  const initial = yearsAvailable.find(item=>item.water_year===data.previous_water_year) || yearsAvailable[0];
  selector.value = initial ? String(initial.water_year) : "none"; selector.disabled = false;
  selectedIndex = Math.max(0,data.points.findLastIndex(point=>point.date<=data.as_of)); selectComparison();
}
async function selectStation() {
  const epoch = ++selectionEpoch, uid = Number($("station").value);
  comparisonEpoch++; comparisonValues = null; comparisonYear = null;
  $("comparison-year").disabled = true;
  $("error").hidden = true;
  $("station-card").hidden = true;
  $("station-card").setAttribute("aria-busy","true");
  try {
    const entry = catalog.stations.find(station=>station.uid===uid);
    if (!entry || entry.file !== `${uid}.json`) throw Error("Invalid station selection.");
    if (!cache.has(uid)) cache.set(uid,fetch(entry.file,{cache:"no-store"}).then(response=>{
      if (!response.ok) throw Error(`Station request failed (${response.status}).`); return response.json();
    }));
    const payload = await cache.get(uid);
    if (epoch !== selectionEpoch) return;
    if (payload.available === false) throw Error(payload.note || "Cumulative precipitation unavailable.");
    if (payload.schema_version !== 1 || payload.uid !== uid || payload.as_of !== catalog.as_of ||
        !Array.isArray(payload.points) || payload.points.length !== 365) throw Error("Invalid cumulative station data.");
    data = payload; showStation();
    $("station-card").hidden = false; $("station-card").setAttribute("aria-busy","false");
  } catch(error) {
    cache.delete(uid);
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
    $("snapshot").textContent = `Daily accumulation since October 1 · Cached observations through ${catalog.as_of}`;
    for (const station of catalog.stations) {
      const option = document.createElement("option"); option.value = String(station.uid); option.textContent = `${station.name} · ${station.state}`; $("station").append(option);
    }
    if (query.has("uid")) {
      if (!catalog.stations.some(station=>String(station.uid)===query.get("uid"))) throw Error("Cumulative data are unavailable for this station.");
      $("station").value = query.get("uid");
    }
    $("station").addEventListener("change",selectStation); $("period").addEventListener("change",render);
    $("comparison-year").addEventListener("change",selectComparison);
    $("inspect").addEventListener("input",()=>inspect(Number($("inspect").value)));
    const hover = event => {
      if (!plotGeometry) return;
      const rect = $("plot").getBoundingClientRect(), svgX = (event.clientX-rect.left)*960/rect.width;
      inspect((svgX-plotGeometry.left)/(plotGeometry.right-plotGeometry.left)*lastIndex);
    };
    $("plot").addEventListener("pointermove",hover); $("plot").addEventListener("pointerdown",hover);
    await selectStation();
  } catch(error) {$("error").hidden = false; $("error").textContent = `${error.message} Open this plot through the site or a local preview server.`;}
}
initialize();
