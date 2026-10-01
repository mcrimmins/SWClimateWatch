/* Browser-only behavior for the unpublished station explorer prototype. */
(() => {
  "use strict";
  if (new URLSearchParams(window.location.search).has("embedded"))
    document.body.classList.add("embedded");
  const payload = JSON.parse(document.getElementById("explorer-data").textContent);
  const allStations = payload.stations;
  const periodEl = document.getElementById("summary-period");
  let stations = allStations.filter(station => station.period === periodEl.value);
  let byId = new Map(stations.map(station => [String(station.uid), station]));
  const mapEl = document.getElementById("map");
  const metricEl = document.getElementById("map-metric");
  const basemapEl = document.getElementById("basemap-toggle");
  const basemapStatusEl = document.getElementById("basemap-status");
  const labelUnavailableEl = document.getElementById("label-unavailable");
  const coverageTitleEl = document.getElementById("coverage-title");
  const coverageBreakdownEl = document.getElementById("coverage-breakdown");
  const searchEl = document.getElementById("search");
  const stateEl = document.getElementById("state-filter");
  const availableEl = document.getElementById("available-only");
  const countEl = document.getElementById("map-count");
  const legendEl = document.getElementById("legend");
  const selectedEl = document.getElementById("selected");
  const detailEl = document.getElementById("station-detail");
  const detailTitleEl = document.getElementById("detail-title");
  const detailSubtitleEl = document.getElementById("detail-subtitle");
  const detailContentEl = document.getElementById("detail-content");
  const detailCache = new Map();
  const markers = new Map();
  let selectedUid = null;
  let activeTab = "current";
  const sort = { current: { key: "name", asc: true },
                 ranks: { key: "name", asc: true },
                 extremes: { key: "name", asc: true } };

  const periodLabels = { "7day": "7-day", "30day": "30-day", "90day": "90-day",
                         "6month": "6-month", "12month": "12-month" };
  const definitions = {
    pcpn_value: {
      title: "Precipitation total (in.)", unit: "in.", digits: 2,
      bounds: [0.5, 1, 2, 4, 8],
      labels: ["<0.5", "0.5–1", "1–2", "2–4", "4–8", "≥8"],
      colors: ["#d8ebf3", "#8dc9db", "#3f9fc5", "#397eac", "#23588d", "#183f68"]
    },
    tmean_value: {
      title: "Mean temperature (°F)", unit: "°F", digits: 1,
      bounds: [35, 50, 65, 80, 95],
      labels: ["<35", "35–50", "50–65", "65–80", "80–95", "≥95"],
      colors: ["#3a679f", "#90bdd2", "#d8e0ce", "#edc488", "#db8556", "#ae4634"]
    },
    pcpn_anomaly: {
      title: "Precipitation departure (in.)", unit: "in.", digits: 2,
      bounds: [-4, -2, -0.5, 0.5, 2, 4],
      labels: ["<−4", "−4 to −2", "−2 to −0.5", "near 0", "+0.5 to +2", "+2 to +4", "≥+4"],
      colors: ["#ad6b27", "#cf9b50", "#e7d3a6", "#f4f2eb", "#b7d9cb", "#5ba98e", "#176d70"]
    },
    tmean_anomaly: {
      title: "Temperature departure (°F)", unit: "°F", digits: 1,
      bounds: [-10, -5, -2, 2, 5, 10],
      labels: ["<−10", "−10 to −5", "−5 to −2", "near 0", "+2 to +5", "+5 to +10", "≥+10"],
      colors: ["#2b4f9e", "#648abf", "#b7cede", "#f3f1ea", "#f0b592", "#df7750", "#ac3e32"]
    },
    pcpn_percentile: {
      title: "Precipitation percentile", unit: "th", digits: 0,
      bounds: [2, 10, 33, 67, 90, 98],
      labels: ["≤2", "2–10", "10–33", "33–67", "67–90", "90–98", ">98"],
      colors: ["#9c5a26", "#cb8d3b", "#e8c877", "#eeece7", "#a6d2bf", "#52a38c", "#176d6f"]
    },
    tmean_percentile: {
      title: "Mean-temperature percentile", unit: "th", digits: 0,
      bounds: [2, 10, 33, 67, 90, 98],
      labels: ["≤2", "2–10", "10–33", "33–67", "67–90", "90–98", ">98"],
      colors: ["#39469b", "#577aba", "#a5c6dc", "#eeece7", "#f39b63", "#be2f29", "#7d0509"]
    }
  };
  const precipitationBounds = {
    "7day": [0.05, 0.25, 0.5, 1, 2],
    "30day": [0.5, 1, 2, 4, 8],
    "90day": [1, 2, 4, 8, 16],
    "6month": [2, 4, 8, 16, 32],
    "12month": [4, 8, 16, 32, 64]
  };
  const precipitationDepartureBounds = {
    "7day": [-1, -0.5, -0.1, 0.1, 0.5, 1],
    "30day": [-4, -2, -0.5, 0.5, 2, 4],
    "90day": [-6, -3, -1, 1, 3, 6],
    "6month": [-10, -5, -2, 2, 5, 10],
    "12month": [-15, -8, -3, 3, 8, 15]
  };
  const temperatureDepartureBounds = {
    "7day": [-12, -6, -2, 2, 6, 12],
    "30day": [-10, -5, -2, 2, 5, 10],
    "90day": [-8, -4, -1.5, 1.5, 4, 8],
    "6month": [-6, -3, -1, 1, 3, 6],
    "12month": [-4, -2, -1, 1, 2, 4]
  };
  const thresholdLabels = bounds => [
    `<${bounds[0]}`,
    ...bounds.slice(0, -1).map((value, index) => `${value}–${bounds[index + 1]}`),
    `≥${bounds[bounds.length - 1]}`
  ];
  function definitionFor(metric) {
    const definition = { ...definitions[metric] };
    if (metric === "pcpn_value") definition.bounds = precipitationBounds[periodEl.value];
    if (metric === "pcpn_anomaly") definition.bounds = precipitationDepartureBounds[periodEl.value];
    if (metric === "tmean_anomaly") definition.bounds = temperatureDepartureBounds[periodEl.value];
    if (["pcpn_value", "pcpn_anomaly", "tmean_anomaly"].includes(metric)) {
      definition.labels = thresholdLabels(definition.bounds);
    }
    definition.title = `${periodLabels[periodEl.value]} ${definition.title}`;
    return definition;
  }

  const finite = value => value !== null && value !== undefined &&
    value !== "" && Number.isFinite(Number(value));
  const escapeHtml = text => String(text ?? "").replace(/[&<>"']/g, character =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]);
  const format = (value, digits = 1) => finite(value) ? Number(value).toFixed(digits) : "—";
  const statusLabel = status => ({ AVAILABLE: "Complete", PROVISIONAL: "Reporting pending",
    NEAR_COMPLETE: "Near-complete temperature", PARTIAL: "Partial temperature",
    INCOMPLETE: "Incomplete", FLAGGED: "Quality flagged",
    STALE: "Station cache stale" })[status] || "Unavailable";
  const date = text => text ? new Date(`${text}T12:00:00`).toLocaleDateString(
    undefined, { year: "numeric", month: "short", day: "numeric" }) : "—";
  function updatePeriodHeading() {
    const period = payload.periods.find(item => item.id === periodEl.value);
    document.getElementById("period").textContent =
      `${periodLabels[periodEl.value]} summary · ${date(period.start)}–${date(payload.as_of)} ` +
      `(${period.days} days) · RCC-ACIS observations`;
  }

  const map = L.map(mapEl, { scrollWheelZoom: false, zoomSnap: 0.25, preferCanvas: true });
  const [west, south, east, north] = payload.bbox;
  map.fitBounds([[south, west], [north, east]], { padding: [12, 12] });
  // Allow edge stations enough room for their full popup without changing zoom.
  map.setMaxBounds([[south - 5, west - 5], [north + 5, east + 5]]);
  map.on("popupopen", ({ popup }) => {
    requestAnimationFrame(() => {
      if (!popup.isOpen()) return;
      const box = popup.getElement().getBoundingClientRect();
      const frame = mapEl.getBoundingClientRect();
      const padding = 24;
      const dx = box.left < frame.left + padding ?
        box.left - frame.left - padding :
        box.right > frame.right - padding ? box.right - frame.right + padding : 0;
      const dy = box.top < frame.top + padding ?
        box.top - frame.top - padding :
        box.bottom > frame.bottom - padding ? box.bottom - frame.bottom + padding : 0;
      if (dx || dy) map.panBy([dx, dy], { animate: false });
    });
  });
  const basemap = L.tileLayer(payload.basemap.url, {
    attribution: payload.basemap.attribution,
    minZoom: 4, maxZoom: 12
  });
  if (/^https?:$/.test(window.location.protocol)) {
    basemap.addTo(map);
    basemapStatusEl.textContent = "Basemap: OpenStreetMap; an internet connection is required.";
    basemap.on("tileerror", () => {
      basemapStatusEl.textContent = "Basemap tiles are unavailable; station data and boundaries remain visible.";
    });
  } else {
    basemapEl.checked = false;
    basemapEl.disabled = true;
    basemapStatusEl.textContent = "To see the basemap, open this preview through the local server described in the guide.";
  }
  basemapEl.addEventListener("change", () => {
    if (basemapEl.checked) basemap.addTo(map);
    else map.removeLayer(basemap);
  });
  L.geoJSON(payload.counties, { interactive: false,
    style: { fill: false, color: "#677b85", weight: 0.65, opacity: 0.56 } }).addTo(map);
  L.geoJSON(payload.states, { interactive: false,
    style: feature => {
      const focus = ["arizona", "new mexico"].includes(
        String(feature.properties?.ID ?? "").toLowerCase());
      return { fill: false, color: focus ? "#25333c" : "#65747d",
        weight: focus ? 1.8 : 1, opacity: focus ? 0.95 : 0.7 };
    } }).addTo(map);
  const markerLayer = L.layerGroup().addTo(map);

  const metricColor = (value, definition) => {
    if (!finite(value)) return null;
    let bin = 0;
    while (bin < definition.bounds.length && Number(value) >= definition.bounds[bin]) bin++;
    return definition.colors[bin];
  };
  const tooltip = station => {
    const precip = finite(station.pcpn_value) ?
      `${station.pcpn_status === "PROVISIONAL" ? "≥" : ""}${format(station.pcpn_value, 2)} in.` : statusLabel(station.pcpn_status);
    const temp = finite(station.tmean_value) ?
      `${format(station.tmean_value, 1)} °F${station.tmean_status === "PARTIAL" ? "*" : ""}` : statusLabel(station.tmean_status);
    const precipAnomaly = finite(station.pcpn_anomaly) ?
      `${Number(station.pcpn_anomaly) >= 0 ? "+" : ""}${format(station.pcpn_anomaly, 2)} in. departure` :
      "departure unavailable";
    const tempAnomaly = finite(station.tmean_anomaly) ?
      `${Number(station.tmean_anomaly) >= 0 ? "+" : ""}${format(station.tmean_anomaly, 1)} °F departure${station.tmean_status === "PARTIAL" ? "*" : ""}` :
      "departure unavailable";
    const selectedReason = finite(station[metricEl.value]) ? "" :
      `<br><strong>Map value unavailable:</strong> ${escapeHtml(
        station[`${metricEl.value}_reason`] || "Needs review")}`;
    const selectedCaution = finite(station[metricEl.value]) && cautionText(station) ?
      `<br><strong>Use with caution:</strong> ${escapeHtml(cautionText(station))}` : "";
    const pending = station.pcpn_status === "PROVISIONAL" ?
      `<br><strong>Reporting pending:</strong> ${station.pcpn_pending_days} recent ${Number(station.pcpn_pending_days) === 1 ? "day" : "days"}; precipitation comparisons withheld` : "";
    return `<div class="tooltip-name">${escapeHtml(station.name)} · ${escapeHtml(station.state)}</div>` +
      `${escapeHtml(periodLabels[periodEl.value])} summary<br>` +
      `Precipitation: ${escapeHtml(precip)} (${escapeHtml(precipAnomaly)})<br>` +
      `Mean temperature: ${escapeHtml(temp)} (${escapeHtml(tempAnomaly)})` +
      selectedReason + selectedCaution + pending;
  };
  const compactNumber = (value, digits) => finite(value) ?
    String(Number(Number(value).toFixed(digits))) : "—";
  const signed = (value, digits, unit) => finite(value) ?
    `${Number(value) > 0 ? "+" : ""}${compactNumber(value, digits)} ${unit}` : "—";
  const textContrast = hex => {
    if (!hex) return "#52616b";
    const rgb = [1, 3, 5].map(index => parseInt(hex.slice(index, index + 2), 16));
    return (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) > 155 ?
      "#1d2b31" : "#fff";
  };
  const cautionLabels = {
    PROVISIONAL_PRECIP: "Precipitation total is a lower bound; recent reporting pending",
    PARTIAL_TEMPERATURE: "Mean temperature uses 95–<98% valid paired days",
    LIMITED_NORMAL_SAMPLE: "Limited 1991–2020 comparison (15–19 years)",
    LIMITED_RANK_SAMPLE: "Limited rank comparison (25–29 years)",
    LOW_BASELINE_COVERAGE: "Historical record has low overall coverage",
    LONG_BASELINE_GAP: "Historical record has a gap over one year",
    LOW_RECENT_COVERAGE: "Recent record has low overall coverage",
    LONG_RECENT_GAP: "Recent record has a gap over 30 days",
    CONSISTENCY_ISSUE: "Daily consistency issue was detected",
    QUALITY_AUDIT_INCOMPLETE: "Detailed quality audit is incomplete",
    MANUAL_CAVEAT: "Station has a documented caveat"
  };
  const cautionText = station => String(
    station[`${metricEl.value}_caution_codes`] || ""
  ).split(";").filter(Boolean).map(code => cautionLabels[code] || code).join("; ");
  function markerIcon(station, definition, color, selected, showLabel) {
    const caution = station[`${metricEl.value}_publication_status`] === "DISPLAY_CAUTION" ||
      (metricEl.value.startsWith("pcpn") && station.pcpn_status === "PROVISIONAL");
    if (!showLabel) {
      const classes = `station-point${color ? "" : " unavailable"}${caution ? " caution" : ""}${selected ? " selected" : ""}`;
      const style = color ? ` style="background-color:${color}"` : "";
      return L.divIcon({
        className: "station-point-icon",
        html: `<span class="${classes}"${style}></span>`,
        iconSize: [12, 12], iconAnchor: [6, 6], popupAnchor: [0, -7]
      });
    }
    const value = station[metricEl.value];
    const label = `${metricEl.value === "pcpn_value" && station.pcpn_status === "PROVISIONAL" ? "≥" : ""}` +
      compactNumber(value, definition.digits) +
      `${metricEl.value.startsWith("tmean") && station.tmean_status === "PARTIAL" ? "*" : ""}`;
    const width = Math.max(27, 12 + label.length * 8);
    const classes = `station-value-label${selected ? " selected" : ""}${color ? "" : " unavailable"}${caution ? " caution" : ""}`;
    const style = color ? ` style="background-color:${color};color:${textContrast(color)}"` : "";
    return L.divIcon({
      className: "station-value-icon",
      html: `<span class="${classes}"${style}>${escapeHtml(label)}</span>`,
      iconSize: [width, 23], iconAnchor: [width / 2, 12], popupAnchor: [0, -12]
    });
  }
  function popup(station) {
    const variable = metricEl.value.startsWith("pcpn") ? "pcpn" : "tmean";
    const status = station[`${variable}_status`];
    const value = station[metricEl.value];
    const definition = definitionFor(metricEl.value);
    let selectedValue = "Unavailable";
    if (finite(value)) {
      if (metricEl.value.endsWith("percentile"))
        selectedValue = `${compactNumber(value, 0)}%`;
      else if (metricEl.value.endsWith("anomaly"))
        selectedValue = signed(value, definition.digits, definition.unit);
      else selectedValue = `${metricEl.value === "pcpn_value" && status === "PROVISIONAL" ? "≥" : ""}` +
        `${compactNumber(value, definition.digits)} ${definition.unit}` +
        `${variable === "tmean" && status === "PARTIAL" ? " *" : ""}`;
      if (variable === "tmean" && status === "PARTIAL" &&
          !selectedValue.endsWith("*")) selectedValue += " *";
    }
    const missing = station[`${variable}_missing_days`];
    const flagged = station[`${variable}_flagged_days`];
    const usable = finite(missing) && finite(flagged) ?
      Math.max(0, station.period_days - Number(missing) - Number(flagged)) : null;
    const coverage = usable === null ? "Unavailable" :
      `${usable} of ${station.period_days} usable days (${Math.round(100 * usable / station.period_days)}%)`;
    const rank = finite(station[`${variable}_rank`]) ?
      `#${station[`${variable}_rank`]} of ${station[`${variable}_reference_years`]} ` +
      `(${compactNumber(station[`${variable}_percentile`], 0)}%)` +
      (variable === "tmean" && status === "PARTIAL" ? " *" : "") :
      `Unavailable (${station[`${variable}_reference_years`]} comparison years)`;
    const recordValue = station[`${variable}_record_high`];
    const recordEnd = station[`${variable}_record_high_end`];
    const recordTies = station[`${variable}_record_high_ties`];
    const record = finite(recordValue) && recordEnd ?
      `${format(recordValue, variable === "pcpn" ? 2 : 1)} ` +
      `${variable === "pcpn" ? "in." : "°F"} · period ending ${date(recordEnd)}` +
      (Number(recordTies) > 1 ? ` (tied ${recordTies} times)` : "") : "Unavailable";
    const years = finite(station[`${variable}_reference_start`]) ?
      `${station[`${variable}_reference_start`]}–${station[`${variable}_reference_end`]}` : "—";
    const departure = signed(station[`${variable}_anomaly`],
      variable === "pcpn" ? 2 : 1, variable === "pcpn" ? "in." : "°F") +
      (variable === "tmean" && status === "PARTIAL" &&
       finite(station.tmean_anomaly) ? " *" : "");
    const rows = [
      ["Period", `${date(station.period_start)}–${date(station.as_of)}`],
      ["Departure", departure],
      ["Rank", rank],
      ["Highest comparable period", record],
      ["Comparison years", years],
      ["Data coverage", coverage],
      ["Data status", statusLabel(status)]
    ];
    if (status === "PROVISIONAL") rows.push(["Reporting pending",
      `${station.pcpn_pending_days} most recent ${Number(station.pcpn_pending_days) === 1 ? "day" : "days"}; observed total is a lower bound`]);
    if (variable === "tmean" && finite(station.tmean_reference_partial_years))
      rows.push(["Partial comparison periods",
        `${station.tmean_reference_partial_years} of ${station.tmean_reference_years} earlier years`]);
    if (finite(value) && cautionText(station))
      rows.push(["Display caution", cautionText(station)]);
    if (status === "STALE") rows.push(["Cache through",
      station.cache_as_of ? date(station.cache_as_of) : "No cache available"]);
    if (!finite(value)) {
      rows.push(["Why unavailable", station[`${metricEl.value}_reason`]]);
      if (finite(missing)) rows.push(["Missing days", String(missing)]);
      if (finite(flagged)) rows.push(["Flagged days", String(flagged)]);
      if (metricEl.value.endsWith("anomaly")) rows.push([
        "1991–2020 valid years", `${station[`${variable}_normal_years`]} of 30`]);
    }
    return `<div class="station-popup">` +
      `<h3>${escapeHtml(station.name)} · ${escapeHtml(station.state)}</h3>` +
      `<div class="identity">RCC-ACIS ID: ${escapeHtml(station.sid)}</div>` +
      `<div class="featured">${escapeHtml(definition.title)}<br><strong>${escapeHtml(selectedValue)}</strong></div>` +
      `<dl>${rows.map(([key, entry]) => `<dt>${escapeHtml(key)}</dt><dd>${escapeHtml(entry)}</dd>`).join("")}</dl>` +
      `<p class="popup-note">Precipitation comparisons require a complete period; a provisional total (≥) excludes pending days. ` +
      `Temperature comparisons accept at least 95% valid paired days with no gap over two days; 95–<98% is cautioned. ` +
      `Departures use 1991–2020 (at least 15 years); ranks use at least 25 earlier years. ` +
      `The current period is included in the high only when complete or eligible.</p>` +
      `</div>`;
  }

  function visible(station) {
    const query = searchEl.value.trim().toLocaleLowerCase();
    if (query && !`${station.name} ${station.state}`.toLocaleLowerCase().includes(query)) return false;
    if (stateEl.value && station.state !== stateEl.value) return false;
    if (availableEl.checked && !finite(station[metricEl.value])) return false;
    return true;
  }

  function renderLegend() {
    const definition = definitionFor(metricEl.value);
    legendEl.replaceChildren();
    const title = document.createElement("span");
    title.className = "legend-title";
    title.textContent = definition.title;
    legendEl.append(title);
    definition.labels.forEach((label, index) => {
      const item = document.createElement("span");
      item.className = "legend-item";
      const swatch = document.createElement("span");
      swatch.className = "legend-swatch";
      swatch.style.backgroundColor = definition.colors[index];
      item.append(swatch, document.createTextNode(label));
      legendEl.append(item);
    });
    const missing = document.createElement("span");
    missing.className = "legend-item";
    missing.textContent = "○ unavailable · dashed edge = caution or reporting pending · ≥ provisional precipitation · * partial temperature · colored dot = label overlap";
    legendEl.append(missing);
  }

  function layoutMarkers() {
    const definition = definitionFor(metricEl.value);
    const size = map.getSize();
    const candidates = [...markers.values()].sort((a, b) =>
      Number(String(b.station.uid) === selectedUid) -
        Number(String(a.station.uid) === selectedUid) ||
      Number(finite(b.station[metricEl.value])) -
        Number(finite(a.station[metricEl.value])) ||
      a.station.name.localeCompare(b.station.name));
    const occupied = [];
    candidates.forEach(({ marker, station }) => {
      const color = metricColor(station[metricEl.value], definition);
      const labelAllowed = Boolean(color) || labelUnavailableEl.checked;
      let showLabel = false;
      if (labelAllowed) {
        const point = map.latLngToContainerPoint(marker.getLatLng());
        const label = `${metricEl.value === "pcpn_value" && station.pcpn_status === "PROVISIONAL" ? "≥" : ""}` +
          compactNumber(station[metricEl.value], definition.digits) +
          `${metricEl.value.startsWith("tmean") && station.tmean_status === "PARTIAL" ? "*" : ""}`;
        const width = Math.max(27, 12 + label.length * 8);
        const box = { left: point.x - width / 2, right: point.x + width / 2,
          top: point.y - 12, bottom: point.y + 12 };
        const onMap = box.right >= 0 && box.left <= size.x &&
          box.bottom >= 0 && box.top <= size.y;
        const overlaps = occupied.some(other =>
          box.left < other.right + 4 && box.right + 4 > other.left &&
          box.top < other.bottom + 4 && box.bottom + 4 > other.top);
        showLabel = onMap && (String(station.uid) === selectedUid || !overlaps);
        if (showLabel) occupied.push(box);
      }
      const selected = String(station.uid) === selectedUid;
      marker.setIcon(markerIcon(station, definition, color, selected, showLabel));
    });
  }

  function renderCoverage() {
    const query = searchEl.value.trim().toLocaleLowerCase();
    const fixed = stations.filter(station => station.role === "fixed" &&
      finite(station.latitude) && finite(station.longitude) &&
      (!query || `${station.name} ${station.state}`.toLocaleLowerCase().includes(query)) &&
      (!stateEl.value || station.state === stateEl.value));
    const unavailable = fixed.filter(station => !finite(station[metricEl.value]));
    coverageTitleEl.textContent = unavailable.length ?
      `Why are ${unavailable.length} of ${fixed.length} mapped values unavailable?` :
      `All ${fixed.length} mapped values are available`;
    coverageBreakdownEl.replaceChildren();
    const groups = new Map();
    unavailable.forEach(station => {
      const reason = station[`${metricEl.value}_reason`] || "Unavailable; needs review";
      if (!groups.has(reason)) groups.set(reason, []);
      groups.get(reason).push(station.name);
    });
    const list = document.createElement("ul");
    groups.forEach((names, reason) => {
      const item = document.createElement("li");
      const heading = document.createElement("strong");
      heading.textContent = `${names.length} · ${reason}`;
      const examples = document.createElement("span");
      examples.textContent = names.join(", ");
      item.append(heading, examples);
      list.append(item);
    });
    coverageBreakdownEl.append(list);
    if (availableEl.checked) {
      const note = document.createElement("p");
      note.textContent = "Unavailable stations are hidden by the table filter, but remain counted here.";
      coverageBreakdownEl.append(note);
    }
  }

  function renderMap() {
    markerLayer.clearLayers();
    markers.clear();
    const definition = definitionFor(metricEl.value);
    let shown = 0;
    stations.forEach(station => {
      if (station.role !== "fixed" || !finite(station.latitude) ||
          !finite(station.longitude) || !visible(station)) return;
      shown++;
      const color = metricColor(station[metricEl.value], definition);
      const selected = String(station.uid) === selectedUid;
      const marker = L.marker([Number(station.latitude), Number(station.longitude)], {
        icon: markerIcon(station, definition, color, selected, Boolean(color)),
        title: station.name,
        keyboard: true,
        riseOnHover: true,
        zIndexOffset: selected ? 1000 : 0
      });
      marker.bindTooltip(tooltip(station), { direction: "top", opacity: 0.98 });
      marker.bindPopup(popup(station), {
        maxWidth: 340, minWidth: 275, autoPan: false
      });
      marker.on("click", () => selectStation(station.uid, false, false, true));
      marker.addTo(markerLayer);
      markers.set(String(station.uid), { marker, station });
    });
    layoutMarkers();
    const fixed = stations.filter(station => station.role === "fixed" &&
      finite(station.latitude) && finite(station.longitude));
    const available = fixed.filter(station => finite(station[metricEl.value])).length;
    countEl.textContent = `${available} of ${fixed.length} mapped with a value` +
      (shown < fixed.length ? ` · ${shown} shown` : "");
    renderLegend();
    renderCoverage();
  }

  function chartFrame(inner, min, max, firstDate, lastDate, unit, label) {
    const width = 760, height = 174, left = 43, right = 12, top = 14, bottom = 29;
    const plotHeight = height - top - bottom;
    const ticks = [min, (min + max) / 2, max].map(value => {
      const y = top + (max - value) / (max - min) * plotHeight;
      return `<line x1="${left}" y1="${y}" x2="${width - right}" y2="${y}" class="chart-grid"/>` +
        `<text x="${left - 7}" y="${y + 4}" text-anchor="end" class="chart-axis">${compactNumber(value, 1)}</text>`;
    }).join("");
    return `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeHtml(label)}">` +
      ticks + inner +
      `<text x="${left}" y="${height - 6}" class="chart-axis">${escapeHtml(date(firstDate))}</text>` +
      `<text x="${width - right}" y="${height - 6}" text-anchor="end" class="chart-axis">${escapeHtml(date(lastDate))}</text>` +
      `<text x="${width - right}" y="${top + 11}" text-anchor="end" class="chart-unit">${escapeHtml(unit)}</text>` +
      `</svg>`;
  }
  function precipitationChart(days) {
    const usable = days.filter(day => finite(day.pcpn)).map(day => Number(day.pcpn));
    if (!usable.length) return `<p class="chart-empty">No usable daily precipitation values in this period.</p>`;
    const width = 760, left = 43, right = 12, top = 14, bottomY = 145;
    const plotWidth = width - left - right;
    const max = Math.max(0.25, Math.ceil(Math.max(...usable) * 2) / 2);
    const step = plotWidth / days.length;
    const bars = days.map((day, i) => {
      const x = left + i * step + Math.max(0.2, step * 0.1);
      const barWidth = Math.max(0.8, step * 0.8);
      if (!finite(day.pcpn)) {
        const color = day.pcpn_status === "FLAGGED" ? "#aa5a3f" : "#9caab0";
        return `<rect x="${x}" y="${bottomY - 5}" width="${barWidth}" height="5" fill="${color}">` +
          `<title>${escapeHtml(day.date)}: ${escapeHtml(day.pcpn_status.toLowerCase())}</title></rect>`;
      }
      const height = Math.max(Number(day.pcpn) > 0 ? 1 : 0,
        Number(day.pcpn) / max * (bottomY - top));
      return `<rect x="${x}" y="${bottomY - height}" width="${barWidth}" height="${height}" fill="#327eaa">` +
        `<title>${escapeHtml(day.date)}: ${compactNumber(day.pcpn, 2)} in.${day.pcpn_status === "TRACE" ? " (trace)" : ""}</title></rect>`;
    }).join("");
    return chartFrame(bars, 0, max, days[0].date, days.at(-1).date,
      "inches", "Daily precipitation bars; muted ticks mark missing or flagged days");
  }
  function temperatureChart(days) {
    const usable = days.flatMap(day => [day.maxt, day.mint])
      .filter(finite).map(Number);
    if (!usable.length) return `<p class="chart-empty">No usable daily high or low temperatures in this period.</p>`;
    let min = Math.floor(Math.min(...usable) / 10) * 10;
    let max = Math.ceil(Math.max(...usable) / 10) * 10;
    if (min === max) { min -= 5; max += 5; }
    const width = 760, left = 43, right = 12, top = 14, bottomY = 145;
    const x = i => left + (i + 0.5) * (width - left - right) / days.length;
    const y = value => top + (max - Number(value)) / (max - min) * (bottomY - top);
    const line = (field, color) => {
      let drawing = false;
      const segments = days.map((day, i) => {
        if (!finite(day[field])) { drawing = false; return ""; }
        const command = drawing ? "L" : "M";
        drawing = true;
        return `${command}${x(i).toFixed(1)},${y(day[field]).toFixed(1)}`;
      }).join(" ");
      const points = days.length <= 30 ? days.map((day, i) => finite(day[field]) ?
        `<circle cx="${x(i)}" cy="${y(day[field])}" r="2.5" fill="${color}">` +
        `<title>${escapeHtml(day.date)}: ${compactNumber(day[field], 1)} °F</title></circle>` : "").join("") : "";
      return `<path d="${segments}" fill="none" stroke="${color}" stroke-width="2"/>${points}`;
    };
    return chartFrame(line("maxt", "#b35b37") + line("mint", "#326a9e"),
      min, max, days[0].date, days.at(-1).date, "°F",
      "Daily maximum temperature in orange and minimum temperature in blue; gaps mark unavailable days");
  }
  function percentileGauge(station, variable, label) {
    const percentile = station[`${variable}_percentile`];
    const rank = station[`${variable}_rank`];
    const n = station[`${variable}_reference_years`];
    const first = station[`${variable}_reference_start`];
    const last = station[`${variable}_reference_end`];
    const reference = finite(first) && finite(last) ? `${first}–${last}` : "No eligible earlier periods";
    const value = finite(percentile) ?
      `Percentile ${compactNumber(percentile, 0)} · rank #${rank} of ${n}` +
      (variable === "tmean" && station.tmean_status === "PARTIAL" ? " *" : "") :
      `Unavailable · ${n} eligible earlier periods (25 required)`;
    const marker = finite(percentile) ?
      `<span class="percentile-marker" style="left:${Math.min(100, Math.max(0, Number(percentile)))}%"></span>` : "";
    return `<div class="percentile-item"><strong>${escapeHtml(label)}</strong>` +
      `<span>${escapeHtml(value)}</span><div class="percentile-track ${variable}">${marker}</div>` +
      `<small>Earlier comparable periods: ${escapeHtml(reference)}</small></div>`;
  }
  function recordLine(record, label) {
    if (!record || !record.first_valid) return `<li>${escapeHtml(label)}: no usable daily observations</li>`;
    return `<li><strong>${escapeHtml(label)}</strong>: ${escapeHtml(date(record.first_valid))}–` +
      `${escapeHtml(date(record.last_valid))} · ${record.valid_days.toLocaleString()} usable days</li>`;
  }
  function detailContent(station, detail) {
    const days = detail.daily.filter(day => day.date >= station.period_start &&
      day.date <= station.as_of);
    const coverage = variable => {
      const missing = station[`${variable}_missing_days`];
      const flagged = station[`${variable}_flagged_days`];
      return `${escapeHtml(station[`${variable}_status`])} · ` +
        `${finite(missing) ? missing : "—"} missing ${Number(missing) === 1 ? "day" : "days"} · ` +
        `${finite(flagged) ? flagged : "—"} flagged ${Number(flagged) === 1 ? "day" : "days"}`;
    };
    const stale = !detail.cache_as_of ?
      `<p class="detail-warning">No station cache is available for this date.</p>` :
      detail.cache_as_of < station.as_of ?
      `<p class="detail-warning">Cache last updated ${escapeHtml(date(detail.cache_as_of))}; ` +
      `later days are shown as missing.</p>` : "";
    return stale +
      `<div class="detail-stats"><p><strong>Precipitation:</strong> ${coverage("pcpn")}</p>` +
      `<p><strong>Mean temperature:</strong> ${coverage("tmean")}</p></div>` +
      `<div class="detail-charts"><figure><figcaption>Daily precipitation</figcaption>` +
      precipitationChart(days) + `</figure><figure><figcaption>Daily high and low temperature</figcaption>` +
      temperatureChart(days) + `</figure></div>` +
      `<p class="detail-chart-note">Daily bars are observations, not a cumulative total. ` +
      `Trace precipitation is zero; missing and flagged days are not filled.</p>` +
      `<div class="detail-lower"><section><h3>Historical standing</h3>` +
      `<p>Each rank compares one eligible corresponding ${escapeHtml(periodLabels[station.period])} ` +
      `period per earlier year. Precipitation requires all days; mean temperature allows at most 5% missing paired days and no gap over two days.</p>` +
      percentileGauge(station, "pcpn", "Precipitation") +
      percentileGauge(station, "tmean", "Mean temperature") +
      `</section><section><h3>Usable daily record</h3><ul>` +
      recordLine(detail.record.pcpn, "Precipitation") +
      recordLine(detail.record.maxt, "Maximum temperature") +
      recordLine(detail.record.mint, "Minimum temperature") +
      `</ul><p>These dates describe usable observations in the local cache, ` +
      `not a guarantee of continuous coverage.</p></section></div>`;
  }
  async function renderStationDetail(station) {
    detailEl.hidden = false;
    detailTitleEl.textContent = `${station.name} · ${station.state}`;
    detailSubtitleEl.textContent = `${station.sid} · ${periodLabels[station.period]} period · ` +
      `${date(station.period_start)}–${date(station.as_of)}` +
      (station.role === "fixed" ? "" : " · ThreadEx area series");
    detailContentEl.textContent = "Loading station detail…";
    const uid = String(station.uid);
    if (!/^https?:$/.test(window.location.protocol)) {
      detailContentEl.textContent = "Open this preview through the local server to load station detail.";
      return;
    }
    if (!detailCache.has(uid)) {
      detailCache.set(uid, fetch(`station-details/${encodeURIComponent(uid)}.json`)
        .then(response => {
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          return response.json();
        }));
    }
    try {
      const detail = await detailCache.get(uid);
      if (selectedUid !== uid) return;
      const current = byId.get(uid);
      if (Number(detail.uid) !== Number(uid) || detail.as_of !== current.as_of) {
        throw new Error("Station detail does not match the preview date.");
      }
      detailContentEl.innerHTML = detailContent(current, detail);
    } catch (error) {
      detailCache.delete(uid);
      if (selectedUid === uid) detailContentEl.textContent =
        `Station detail could not be loaded (${error.message}). Rebuild the local detail files and refresh.`;
    }
  }

  const columns = {
    current: [
      { key: "name", label: "Station" }, { key: "state", label: "State" },
      { key: "pcpn_value", label: "Precipitation (in.)", numeric: true, digits: 2 },
      { key: "pcpn_anomaly", label: "Precip departure (in.)", numeric: true, digits: 2 },
      { key: "tmean_value", label: "Mean temp (°F)", numeric: true, digits: 1 },
      { key: "tmean_anomaly", label: "Temp departure (°F)", numeric: true, digits: 1 },
      { key: "status", label: "Data status" }
    ],
    ranks: [
      { key: "name", label: "Station" }, { key: "state", label: "State" },
      { key: "pcpn_percentile", label: "Precip percentile", numeric: true, digits: 0 },
      { key: "pcpn_rank", label: "Precip rank¹", numeric: true },
      { key: "pcpn_reference_years", label: "Precip comparison period (n)", numeric: true },
      { key: "tmean_percentile", label: "Temp percentile", numeric: true, digits: 0 },
      { key: "tmean_rank", label: "Temp rank¹", numeric: true },
      { key: "tmean_reference_years", label: "Temp comparison period (n)", numeric: true }
    ],
    extremes: [
      { key: "name", label: "Station" }, { key: "state", label: "State" },
      { key: "max_daily_pcpn", label: "Largest daily precip (in.)", numeric: true, digits: 2 },
      { key: "max_daily_pcpn_date", label: "Date" },
      { key: "hottest_day", label: "Hottest day (°F)", numeric: true, digits: 1 },
      { key: "hottest_day_date", label: "Date" },
      { key: "coldest_night", label: "Coldest night (°F)", numeric: true, digits: 1 },
      { key: "coldest_night_date", label: "Date" }
    ]
  };

  function cellValue(station, key) {
    if (key === "status") {
      const pending = station.pcpn_status === "PROVISIONAL" ?
        `precip pending ${station.pcpn_pending_days}d` : station.pcpn_status.toLowerCase();
      const temperature = station.tmean_status === "PARTIAL" ?
        `temp partial ${station.tmean_missing_days}d` :
        station.tmean_status === "NEAR_COMPLETE" ?
          `temp near-complete ${station.tmean_missing_days}d` :
          station.tmean_status.toLowerCase();
      return `${pending} / ${temperature}`;
    }
    if (key === "pcpn_rank" || key === "tmean_rank") {
      const variable = key.split("_")[0];
      return finite(station[key]) ?
        `#${station[key]} of ${station[`${variable}_reference_years`]}` +
        (variable === "tmean" && station.tmean_status === "PARTIAL" ? "*" : "") : "—";
    }
    return station[key];
  }
  function compare(a, b, column, ascending) {
    let x = column.key === "status" ? cellValue(a, column.key) : a[column.key];
    let y = column.key === "status" ? cellValue(b, column.key) : b[column.key];
    const xMissing = x === null || x === undefined || x === "";
    const yMissing = y === null || y === undefined || y === "";
    if (xMissing !== yMissing) return xMissing ? 1 : -1;
    if (xMissing) return String(a.name).localeCompare(String(b.name));
    const direction = ascending ? 1 : -1;
    const result = column.numeric ? Number(x) - Number(y) :
      String(x).localeCompare(String(y), undefined, { numeric: true });
    return direction * result || String(a.name).localeCompare(String(b.name));
  }
  function makeCell(station, column) {
    const cell = document.createElement("td");
    if (column.numeric) cell.className = "num";
    if (column.key === "name") {
      const button = document.createElement("button");
      button.className = "station-link";
      button.type = "button";
      button.textContent = station.name;
      button.addEventListener("click", () => selectStation(station.uid, true, true));
      cell.append(button);
      if (station.role !== "fixed") {
        const badge = document.createElement("span");
        badge.className = "threadex";
        badge.textContent = "ThreadEx area";
        cell.append(badge);
      }
    } else if (column.key.endsWith("_date")) {
      cell.textContent = date(station[column.key]);
    } else if (column.key.endsWith("_reference_years")) {
      const variable = column.key.split("_")[0];
      const start = station[`${variable}_reference_start`];
      const end = station[`${variable}_reference_end`];
      cell.textContent = finite(start) && finite(end) ?
        `${start}–${end} (${station[column.key]})` : "—";
    } else if (column.numeric && column.digits !== undefined) {
      const prefix = column.key === "pcpn_value" &&
        station.pcpn_status === "PROVISIONAL" && finite(station[column.key]) ? "≥" : "";
      const suffix = column.key.startsWith("tmean_") &&
        station.tmean_status === "PARTIAL" && finite(station[column.key]) ? "*" : "";
      cell.textContent = prefix + format(station[column.key], column.digits) + suffix;
    } else {
      cell.textContent = cellValue(station, column.key) ?? "—";
    }
    return cell;
  }
  function renderTable(tab) {
    const panel = document.getElementById(`panel-${tab}`);
    panel.replaceChildren();
    const table = document.createElement("table");
    const head = document.createElement("thead");
    const headRow = document.createElement("tr");
    columns[tab].forEach(column => {
      const th = document.createElement("th");
      if (column.numeric) th.className = "num";
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = column.label + (sort[tab].key === column.key ?
        (sort[tab].asc ? " ▲" : " ▼") : "");
      button.addEventListener("click", () => {
        sort[tab] = { key: column.key,
                      asc: sort[tab].key === column.key ? !sort[tab].asc : true };
        renderTable(tab);
      });
      th.append(button);
      headRow.append(th);
    });
    head.append(headRow);
    table.append(head);
    const body = document.createElement("tbody");
    const selectedColumn = columns[tab].find(column => column.key === sort[tab].key);
    stations.filter(visible).sort((a, b) => compare(a, b, selectedColumn, sort[tab].asc))
      .forEach(station => {
        const row = document.createElement("tr");
        row.dataset.uid = String(station.uid);
        if (String(station.uid) === selectedUid) row.dataset.selected = "true";
        columns[tab].forEach(column => row.append(makeCell(station, column)));
        body.append(row);
      });
    table.append(body);
    panel.append(table);
    const caption = document.createElement("div");
    caption.className = "table-caption";
    if (tab === "ranks") caption.textContent =
      `¹ Rank 1 is wettest or warmest. Each comparison ends on the same calendar date in an earlier year. ` +
      "Precipitation requires complete periods; temperature permits at least 95% paired days with no gap over two days. " +
      "At least 25 eligible years are required; 25–29 receive a caution. Percentiles use a midpoint for ties. " +
      "A pending precipitation total has no rank; * marks a temperature result from a partial current period. — means unavailable.";
    else if (tab === "current") caption.textContent =
      "≥ is observed precipitation with 1–2 most recent reporting days pending (at most 1 for 7-day); it is a lower bound, with no departure or rank. " +
      "* marks a temperature result from 95–<98% valid paired days with no gap over two days; ≥98% displays normally. Dashed map edges mark cautions or pending reports. " +
      "Departures use at least 15 eligible 1991–2020 years; 15–19 receive a caution. — means unavailable. ThreadEx is an area composite, not a point station.";
    else caption.textContent =
      `Dates and values refer to the most extreme single valid day in a complete ${periodLabels[periodEl.value]} period; ` +
      "they are unavailable for incomplete periods. Ties use the first date. — means unavailable.";
    panel.append(caption);
  }
  function renderTables() { Object.keys(columns).forEach(renderTable); }
  function selectStation(uid, openPopup = true, showMap = false, fromMarker = false) {
    selectedUid = String(uid);
    const station = byId.get(selectedUid);
    selectedEl.textContent = `${station.name} · ${station.state} · ${station.role === "fixed" ?
      "fixed station" : "ThreadEx area series"}`;
    if (fromMarker) {
      markers.forEach(({ marker }, markerUid) => {
        marker.getElement()?.querySelector(".station-value-label, .station-point")
          ?.classList.toggle("selected", markerUid === selectedUid);
      });
    } else {
      renderMap();
    }
    renderTables();
    void renderStationDetail(station);
    const selectedMarker = markers.get(selectedUid)?.marker;
    if (openPopup && selectedMarker) {
      selectedMarker.openPopup();
      if (showMap) mapEl.scrollIntoView({ behavior: "smooth", block: "center" });
    } else if (showMap) {
      detailEl.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }
  function refresh() {
    updatePeriodHeading(); renderMap(); renderTables();
    if (selectedUid && byId.has(selectedUid)) void renderStationDetail(byId.get(selectedUid));
  }

  [...new Set(stations.map(station => station.state))].sort().forEach(state => {
    const option = document.createElement("option");
    option.value = option.textContent = state;
    stateEl.append(option);
  });
  metricEl.addEventListener("change", refresh);
  periodEl.addEventListener("change", () => {
    stations = allStations.filter(station => station.period === periodEl.value);
    byId = new Map(stations.map(station => [String(station.uid), station]));
    refresh();
  });
  searchEl.addEventListener("input", refresh);
  stateEl.addEventListener("change", refresh);
  availableEl.addEventListener("change", refresh);
  document.getElementById("detail-close").addEventListener("click", () => {
    selectedUid = null;
    detailEl.hidden = true;
    map.closePopup();
    selectedEl.textContent = "Select a station on the map or in a table.";
    renderMap();
    renderTables();
  });
  labelUnavailableEl.addEventListener("change", layoutMarkers);
  map.on("zoomend moveend resize", layoutMarkers);
  document.querySelectorAll('[role="tab"]').forEach(button => {
    button.addEventListener("click", () => {
      activeTab = button.dataset.tab;
      document.querySelectorAll('[role="tab"]').forEach(tab => {
        const isActive = tab.dataset.tab === activeTab;
        tab.setAttribute("aria-selected", String(isActive));
        tab.tabIndex = isActive ? 0 : -1;
        document.getElementById(`panel-${tab.dataset.tab}`).hidden = !isActive;
      });
    });
    button.addEventListener("keydown", event => {
      if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
      event.preventDefault();
      const tabs = [...document.querySelectorAll('[role="tab"]')];
      const next = (tabs.indexOf(button) + (event.key === "ArrowRight" ? 1 : -1) +
        tabs.length) % tabs.length;
      tabs[next].click();
      tabs[next].focus();
    });
  });
  refresh();
})();
