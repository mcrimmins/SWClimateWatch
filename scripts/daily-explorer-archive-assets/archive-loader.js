// Appended to a diagnostic copy of explorer.js; production code is unchanged.
let archiveCatalog = null, archiveDate = "", archiveYear = null, archiveSequence = 0;
const archiveMemory = new Map();
function archiveMonths(year) {return archiveCatalog.months.filter(m => m.water_year === Number(year)).sort((a,b) => a.month.localeCompare(b.month));}
function archiveOptions(date) {
  const selected = SWCArchive.partition(archiveCatalog,date);
  const years = [...new Set(archiveCatalog.months.map(m => m.water_year))].sort((a,b) => b-a);
  setOptions($("year"),years.map(y => [String(y),`WY${y} · Oct ${y-1}–Sep ${y}`]),String(selected.water_year));
  setOptions($("archive-month"),archiveMonths(selected.water_year).map(m => [m.month,new Date(`${m.month}-15T12:00:00Z`).toLocaleDateString("en-US",{month:"long",year:"numeric",timeZone:"UTC"})]),selected.month);
}
async function archiveRead(date) {
  const entries = SWCArchive.needed(archiveCatalog,date);
  const parts = await Promise.all(entries.map(async entry => {
    if (archiveMemory.has(entry.path)) return archiveMemory.get(entry.path);
    const r = await fetch(entry.path,{cache:"no-store"});
    if (!r.ok) throw Error(`Month data unavailable (${r.status}).`);
    const p = await r.json();
    if (!Array.isArray(p.days) || p.days.map(d => d.date).join() !== entry.dates.join()) throw Error("Partition dates differ from the catalog.");
    SWCArchive.records([p]); archiveMemory.set(entry.path,p); return p;
  }));
  // At most three month partitions are needed for the supported map windows.
  for (const key of archiveMemory.keys()) if (!entries.some(m => m.path === key)) archiveMemory.delete(key);
  return SWCArchive.records(parts);
}
async function archiveInitialPayload() {
  const r = await fetch("archive-catalog.json",{cache:"no-store"});
  if (!r.ok) throw Error(`Archive catalog unavailable (${r.status}).`);
  archiveCatalog = SWCArchive.validate(await r.json());
  archiveDate = new URL(location.href).searchParams.get("date") || archiveCatalog.latest;
  const entry = SWCArchive.partition(archiveCatalog,archiveDate);
  if (!entry) throw Error("Requested date was not built in this sample archive.");
  archiveYear = entry.water_year; archiveOptions(archiveDate);
  return {schema_version:1,publication_mode:false,baseline:"1991–2020",latest_cached_date:archiveCatalog.latest,
    local_review_note:"PRISM-only navigation pilot. Only the listed sample dates are built. Missing tiles mean not built in this pilot; no other date is substituted.",
    days:await archiveRead(archiveDate)};
}
async function archiveNavigate(date) {
  const sequence = ++archiveSequence;
  $("archive-status").textContent = "Loading selected archive month…";
  try {
    const loaded = await archiveRead(date);
    if (sequence !== archiveSequence) return;
    days = loaded; byDate = new Map(days.map(d => [d.date,d])); selectedDate = date;
    archiveDate = date; archiveYear = SWCArchive.year(date); archiveOptions(date);
    $("season").value = "all"; $("error").hidden = true; render();
  } catch (e) {
    if (sequence !== archiveSequence) return;
    days = []; byDate = new Map(); selectedDate = ""; render();
    $("error").hidden = false; $("error").textContent = e.message;
    $("archive-status").textContent = "Archive month unavailable; no previous selection is being substituted.";
  }
}
function archiveUpdateUrl() {
  if (!archiveCatalog || !selectedDate) return;
  const entry = SWCArchive.partition(archiveCatalog,selectedDate);
  if (entry) $("coverage").textContent = `Built sample maps: ${dayLabel(entry.dates[0])}–${dayLabel(entry.dates.at(-1))} · Latest cached PRISM date: ${dayLabel(archiveCatalog.latest)} · Temperature reference: 1991–2020`;
  const url = new URL(location.href); url.searchParams.set("date",selectedDate); history.replaceState(null,"",url);
  $("archive-status").textContent = `${dayLabel(selectedDate)} · ${$("archive-month").selectedOptions[0]?.textContent || ""} · Sample dates only. Other months and dates have not been backfilled.`;
}
function archiveBind() {
  $("year").addEventListener("change",() => {
    const month = archiveMonths($("year").value).at(-1); archiveNavigate(month.dates.at(-1));
  });
  $("archive-month").addEventListener("change",() => {
    const month = archiveCatalog.months.find(m => m.month === $("archive-month").value); archiveNavigate(month.dates.at(-1));
  });
  archiveUpdateUrl();
}
