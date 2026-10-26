"use strict";
// No dependencies, API calls, or server computations: static images + summaries.
const METRICS = {
  tmean: {
    departure: ["Regional mean departure", "°F", false],
    mean: ["Regional mean temperature", "°F", false]
  },
  pcpn: {
    mean: ["Regional mean precipitation", "in.", false],
    rain010: ["Area receiving ≥0.10 inch", "%", false],
    rain050: ["Area receiving ≥0.50 inch", "%", false],
    rain100: ["Area receiving ≥1 inch", "%", false],
    spatial_p99: ["Spatial 99th-percentile precipitation", "in.", false]
  },
  maxt: {
    departure: ["Regional mean departure", "°F", false],
    mean: ["Regional mean maximum temperature", "°F", false],
    warm: ["Area above calendar-day 90th percentile", "%", false],
    cold: ["Area below calendar-day 10th percentile", "%", false]
  },
  mint: {
    departure: ["Regional mean departure", "°F", false],
    mean: ["Regional mean minimum temperature", "°F", false],
    warm: ["Area above calendar-day 90th percentile", "%", false],
    cold: ["Area below calendar-day 10th percentile", "%", false],
    freeze: ["Area at or below freezing", "%", false]
  }
};
const $ = id => document.getElementById(id);
const valid = value => typeof value === "number" && Number.isFinite(value);
const format = (value, unit = "", signed = false) => {
  if (!valid(value)) return "Unavailable";
  if (value > 0 && ((unit === "in." && value < 0.01) || (unit === "%" && value < 0.1))) {
    return unit === "in." ? "<0.01 in." : "<0.1%";
  }
  return `${signed && value > 0 ? "+" : ""}${value.toLocaleString("en-US", {maximumFractionDigits: unit === "in." ? 2 : 1})}${unit === "%" ? "" : " "}${unit}`;
};
const isoDate = value => new Date(`${value}T12:00:00Z`);
const dayLabel = value => isoDate(value).toLocaleDateString("en-US", {month:"short", day:"numeric", year:"numeric", timeZone:"UTC"});
const shortLabel = value => isoDate(value).toLocaleDateString("en-US", {month:"short", day:"numeric", timeZone:"UTC"});
const shift = (date, days) => {const d = isoDate(date); d.setUTCDate(d.getUTCDate() + days); return d.toISOString().slice(0,10);};
// No build-time downloads. The external reader loads only on explicit selection.
const DISCUSSION_SOURCES = {
  local: [
    ["AFDPSR", "Phoenix (PSR)"], ["AFDTWC", "Tucson (TWC)"],
    ["AFDFGZ", "Flagstaff (FGZ)"], ["AFDABQ", "Albuquerque (ABQ)"],
    ["AFDEPZ", "El Paso / Santa Teresa (EPZ)"]
  ],
  adjacent: [
    ["AFDVEF", "Las Vegas (VEF)"], ["AFDSGX", "San Diego (SGX)"],
    ["AFDGJT", "Grand Junction (GJT)"], ["AFDPUB", "Pueblo (PUB)"],
    ["AFDAMA", "Amarillo (AMA)"]
  ],
  national: [
    ["PMDSPD", "Short-range discussion"], ["PMDEPD", "Extended discussion"],
    ["QPFERD", "Excessive rainfall discussion"], ["FFGMPD", "Mesoscale precipitation discussions"],
    ["QPFHSD", "Heavy snow / icing discussion"]
  ]
};
let discussionDate = "", discussionProduct = "";
function resetDiscussionReader() {
  discussionProduct = "";
  $("discussion-reader").hidden = true;
  $("discussion-frame").removeAttribute("src");
  $("discussion-original").removeAttribute("href");
  $("discussion-reader-status").textContent = "";
}
function closeDiscussionReader() {resetDiscussionReader(); renderDiscussions();}
function openDiscussion(product, label) {
  const href = discussionArchiveUrl(selectedDate, product);
  if (!href) return;
  const frame = $("discussion-frame");
  discussionProduct = product;
  $("discussion-reader").hidden = false;
  $("discussion-reader-title").textContent = `${label} · ${dayLabel(selectedDate)} UTC issuances`;
  frame.title = `Archived ${label}, issued ${selectedDate} UTC`;
  $("discussion-original").href = href;
  $("discussion-reader-status").textContent = "External IEM archive view. If it is blank, unavailable, or blocked, use Open in new tab or try again later.";
  if (frame.getAttribute("src") !== href) frame.src = href;
  // Keep the clicked link in place so keyboard focus is not lost.
  for (const group of Object.keys(DISCUSSION_SOURCES)) {
    for (const item of $(`discussion-${group}`).children) {
      const link = item.children[0];
      link.setAttribute("aria-current", String(link.getAttribute("data-product") === product));
    }
  }
}
function discussionArchiveUrl(date, product) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(isoDate(date).getTime()) ||
      isoDate(date).toISOString().slice(0,10) !== date ||
      !Object.values(DISCUSSION_SOURCES).flat().some(([pil]) => pil === product)) return null;
  const query = new URLSearchParams({pil: product, fmt: "html",
    sdate: `${date}T00:00Z`, edate: `${shift(date, 1)}T00:00Z`, limit: "100", order: "asc"});
  return `https://mesonet.agron.iastate.edu/cgi-bin/afos/retrieve.py?${query}`;
}
function renderDiscussions() {
  const date = selectedDate;
  if (date !== discussionDate) {resetDiscussionReader(); discussionDate = date;}
  $("discussion-date").textContent = date ? ` · ${dayLabel(date)}` : "";
  $("discussion-content").hidden = !date;
  $("discussion-no-date").hidden = !!date;
  for (const [group, sources] of Object.entries(DISCUSSION_SOURCES)) {
    const list = $(`discussion-${group}`); list.replaceChildren();
    if (!date) continue;
    for (const [product, label] of sources) {
      const href = discussionArchiveUrl(date, product);
      if (!href) continue;
      const item = document.createElement("li"), link = document.createElement("a");
      link.href = href; link.target = "_blank"; link.rel = "noopener noreferrer";
      link.textContent = label;
      link.setAttribute("data-product", product);
      link.setAttribute("aria-label", `${label}: ${product} archive search for ${date} UTC (opens in embedded reader)`);
      if (discussionProduct === product) link.setAttribute("aria-current", "true");
      link.addEventListener("click", event => {
        if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
        event.preventDefault(); openDiscussion(product, label);
      });
      item.append(link); list.append(item);
    }
  }
  if (date) $("discussion-window").textContent =
    `Issued ${date} 00:00 UTC to ${shift(date, 1)} 00:00 UTC (end exclusive). Links follow this selected day, not the full 7-/30-day grid.`;
}
let days = [], byDate = new Map(), selectedDate = "", visibleDates = [];
function regionValues(date) {return byDate.get(date)?.regions?.[$("region").value]?.[$("variable").value];}
function metricValue(date, metric) {return regionValues(date)?.[metric] ?? null;}
function inCachedDateRange(date) {
  return !!date && days.length > 0 && date >= days[0].date && date <= days.at(-1).date;
}
function imageFor(date) {
  const variable = $("variable").value;
  return byDate.get(date)?.images?.[`${variable}_${variable === "pcpn" ? "observed" : $("view").value}`];
}
function setOptions(element, options, selected) {
  element.replaceChildren();
  for (const [value, text] of options) {const option = document.createElement("option"); option.value = value; option.textContent = text; element.append(option);}
  if (options.some(([key]) => key === selected)) element.value = selected;
}
function refreshMetricOptions(reset = false) {
  const options = Object.entries(METRICS[$("variable").value]).map(([key, info]) => [key, info[0]]);
  setOptions($("metric"), options, reset ? options[0][0] : $("metric").value);
  const ranks = options.map(([key, label]) => [key, `${label} · highest first`]);
  if ($("variable").value !== "pcpn") {
    ranks.push(["departure_low", "Regional mean departure · lowest first"]);
    ranks.push(["mean_low", "Regional mean temperature · lowest first"]);
  }
  setOptions($("ranking"), ranks, reset ? ranks[0][0] : $("ranking").value);
  $("view-label").hidden = $("variable").value === "pcpn";
}
function filterDates() {
  const year = Number($("year").value), season = $("season").value;
  const available = days.filter(day => day.water_year === year);
  if (!available.length) return [];
  const result = [];
  for (let date = available[0].date; date <= available.at(-1).date; date = shift(date, 1)) {
    const month = Number(date.slice(5,7));
    if (season === "cool" && month > 3 && month < 10) continue;
    if (season === "warm" && (month < 4 || month > 9)) continue;
    if (season === "monsoon" && (month < 6 || month > 9)) continue;
    result.push(date);
  }
  return result;
}
function selectDate(date) {
  const day = byDate.get(date);
  if (day) {
    $("year").value = String(day.water_year);
    if (!filterDates().includes(date)) $("season").value = "all";
  }
  selectedDate = date; render();
}
function comparisonDates() {
  if (!selectedDate || $("compare").value === "single") return [];
  const monthly = $("compare").value === "30";
  return Array.from({length: monthly ? 30 : 7}, (_, i) => shift(selectedDate, i - (monthly ? 29 : 3)));
}
function renderTimeline() {
  const timelineDates = $("compare").value === "single" ? visibleDates : comparisonDates();
  const metric = $("metric").value, [label, unit] = METRICS[$("variable").value][metric];
  const maximum = Math.max(...timelineDates.map(date => Math.abs(metricValue(date, metric) || 0)), 0.01);
  $("timeline-caption").textContent = `${label} · ${$("region").selectedOptions[0].textContent} · ${timelineDates.length ? `${shortLabel(timelineDates[0])}–${shortLabel(timelineDates.at(-1))}` : "No cached dates in this season"}${metric === "departure" ? " · Blue: below normal; orange: above normal. Bar height shows magnitude." : ""}`;
  $("timeline").replaceChildren();
  const spacing = Math.max(1, Math.ceil(timelineDates.length / 16));
  timelineDates.forEach((date, index) => {
    const value = metricValue(date, metric), button = document.createElement("button");
    button.type = "button"; button.className = `day${date === selectedDate ? " selected" : ""}${!valid(value) ? " missing" : ""}`;
    button.disabled = !byDate.has(date);
    button.title = `${dayLabel(date)}: ${label} ${format(value, unit, metric === "departure")}`;
    button.setAttribute("aria-label", button.title); button.setAttribute("aria-pressed", String(date === selectedDate));
    const bar = document.createElement("span"); bar.className = "bar";
    bar.style.height = `${valid(value) ? Math.max(2, Math.abs(value) / maximum * 78) : 0}px`;
    bar.style.background = $("variable").value === "pcpn" ? "#2d8b9b" : metric === "departure" ? value < 0 ? "#4286b2" : "#c66a3c" : "#756799";
    bar.hidden = !valid(value);
    const dateLabel = document.createElement("span"); dateLabel.className = "date-label"; dateLabel.textContent = index % spacing === 0 ? shortLabel(date) : "";
    button.append(bar, dateLabel); button.addEventListener("click", () => selectDate(date)); $("timeline").append(button);
  });
}
function addStat(label, value, unit, signed = false) {
  const box = document.createElement("div"); box.className = "stat";
  const number = document.createElement("strong"); number.textContent = format(value, unit, signed);
  const caption = document.createElement("span"); caption.textContent = label;
  box.append(number, caption); $("stats").append(box);
}
function renderMap() {
  const date = selectedDate, variable = $("variable").value, image = imageFor(date);
  $("date").value = date;
  $("map-title").textContent = date ? dayLabel(date) : "No cached dates in this season";
  $("previous").disabled = !date || !inCachedDateRange(shift(date, -1));
  $("next").disabled = !date || !inCachedDateRange(shift(date, 1));
  $("date").disabled = !days.length;
  if (days.length) {$("date").min = days[0].date; $("date").max = days.at(-1).date;}
  $("map").hidden = !image; $("open-map").hidden = !image; $("unavailable").hidden = !!image;
  if (image) {$("map").src = image; $("map").alt = `${$("variable").selectedOptions[0].textContent}, ${variable === "pcpn" ? "observed" : $("view").value}, ${dayLabel(date)}`; $("open-map").href = image;}
  else {$("map").removeAttribute("src"); $("unavailable").textContent = "This map is unavailable in the local cache. Choose another date or display mode.";}
  $("stats").replaceChildren();
  const stats = regionValues(date);
  addStat(variable === "pcpn" ? "Regional mean precipitation" : "Regional mean temperature", stats?.mean, variable === "pcpn" ? "in." : "°F");
  if (variable === "pcpn") {addStat("Area with ≥0.10 inch", stats?.rain010, "%"); addStat("Area with ≥1 inch", stats?.rain100, "%");}
  else {addStat("Departure from normal", stats?.departure, "°F", true); if (variable !== "tmean") addStat(variable === "mint" ? "Area at or below freezing" : "Area above 90th percentile", variable === "mint" ? stats?.freeze : stats?.warm, "%");}
}
function renderComparison() {
  const mode = $("compare").value, show = mode !== "single" && !!selectedDate;
  $("comparison").hidden = !show;
  $("comparison-caption").hidden = !show;
  $("comparison").classList.toggle("month-grid", mode === "30");
  $("comparison").replaceChildren();
  if (!show) return;
  $("comparison-caption").textContent = mode === "30"
    ? `30 days ending ${dayLabel(selectedDate)} · ${shortLabel(shift(selectedDate,-29))}–${shortLabel(selectedDate)}. Uses built dates across season and water-year boundaries.`
    : `7 days centered on ${dayLabel(selectedDate)} · ${shortLabel(shift(selectedDate,-3))}–${shortLabel(shift(selectedDate,3))}. Uses built dates across season and water-year boundaries.`;
  for (const date of comparisonDates()) {
    const image = imageFor(date);
    const button = document.createElement("button"); button.type = "button"; button.className = `mini${date === selectedDate ? " selected" : ""}`;
    const title = document.createElement("strong"); title.textContent = shortLabel(date); button.append(title);
    if (image) {const img = document.createElement("img"); img.src = image; img.loading = "lazy"; img.alt = `Daily map for ${dayLabel(date)}`; button.append(img);}
    else {const missing = document.createElement("p"); missing.className = "empty"; missing.textContent = "Not built or unavailable"; button.append(missing);}
    button.disabled = !byDate.has(date);
    button.addEventListener("click", () => {
      const day = byDate.get(date);
      $("year").value = String(day.water_year);
      if (!filterDates().includes(date)) $("season").value = "all";
      selectDate(date);
    }); $("comparison").append(button);
  }
}
function renderNotable() {
  const ranking = $("ranking").value, ascending = ranking.endsWith("_low"), metric = ranking.replace(/_low$/, "");
  const [label, unit] = METRICS[$("variable").value][metric];
  const candidates = visibleDates.map(date => ({date, value:metricValue(date, metric)})).filter(day => valid(day.value));
  candidates.sort((a,b) => (ascending ? a.value - b.value : b.value - a.value) || a.date.localeCompare(b.date));
  $("ranking-title").textContent = label; $("notable").replaceChildren();
  for (const day of candidates.slice(0,10)) {
    const row = document.createElement("tr"), date = document.createElement("td"), value = document.createElement("td"), action = document.createElement("td");
    date.textContent = dayLabel(day.date); value.textContent = format(day.value, unit, metric === "departure");
    const button = document.createElement("button"); button.type = "button"; button.textContent = "View day";
    button.addEventListener("click", () => {selectDate(day.date); $("map-title").scrollIntoView({behavior:"smooth", block:"start"});});
    action.append(button); row.append(date,value,action); $("notable").append(row);
  }
  if (!candidates.length) {const row = document.createElement("tr"), cell = document.createElement("td"); cell.colSpan = 3; cell.textContent = "No usable values for this metric in the selected period."; row.append(cell); $("notable").append(row);}
}
function render() {
  visibleDates = filterDates();
  if (!visibleDates.includes(selectedDate)) selectedDate = visibleDates.at(-1) || "";
  renderTimeline(); renderMap(); renderComparison(); renderDiscussions(); renderNotable();
}
async function initialize() {
  try {
    const response = await fetch("daily-data.json", {cache:"no-store"});
    if (!response.ok) throw new Error(`Data request failed (${response.status}).`);
    const payload = await response.json();
    if (payload.schema_version !== 1 || !Array.isArray(payload.days) || !payload.days.length) throw new Error("No usable daily data were built.");
    days = payload.days.sort((a,b) => a.date.localeCompare(b.date)); byDate = new Map(days.map(day => [day.date,day]));
    $("mode-badge").textContent = payload.publication_mode ? "Daily PRISM maps" : "Local preview · Unpublished";
    const years = [...new Set(days.map(day => day.water_year))].sort((a,b) => b-a);
    setOptions($("year"), years.map(year => [String(year), `${year} · Oct ${year-1}–Sep ${year}`]), String(years[0]));
    $("coverage").textContent = `${payload.publication_mode ? "Daily maps" : "Cached daily maps"}: ${dayLabel(days[0].date)}–${dayLabel(days.at(-1).date)} · Latest PRISM date: ${dayLabel(payload.latest_cached_date)} · Temperature reference: ${payload.baseline}`;
    refreshMetricOptions(); render();
    for (const id of ["year","season","region","view","metric","ranking","compare"]) $(id).addEventListener("change", render);
    $("variable").addEventListener("change", () => {refreshMetricOptions(true); render();});
    $("date").addEventListener("change", () => {if (inCachedDateRange($("date").value)) selectDate($("date").value); else $("date").value = selectedDate;});
    $("previous").addEventListener("click", () => selectDate(shift(selectedDate,-1)));
    $("next").addEventListener("click", () => selectDate(shift(selectedDate,1)));
    $("discussion-close").addEventListener("click", closeDiscussionReader);
    $("discussion-frame").addEventListener("error", () => {
      if (!$("discussion-reader").hidden) $("discussion-reader-status").textContent =
        "The embedded archive could not be opened. Use Open in new tab or try again later.";
    });
    $("map").addEventListener("error", () => {$("map").hidden = true; $("open-map").hidden = true; $("unavailable").hidden = false; $("unavailable").textContent = "The map image could not be loaded. Rebuild the local explorer to restore missing assets.";});
  } catch (error) {
    $("error").hidden = false; $("error").textContent = `Could not load the local explorer: ${error.message} Open it through scripts/serve-daily-explorer.R, rather than directly from a file.`;
    $("coverage").textContent = "Daily explorer unavailable";
  }
}
initialize();
