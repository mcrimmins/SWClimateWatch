"use strict";
const SWCArchive = (() => {
  const iso = d => /^\d{4}-\d{2}-\d{2}$/.test(d) && !Number.isNaN(Date.parse(`${d}T12:00:00Z`)) && new Date(`${d}T12:00:00Z`).toISOString().slice(0,10) === d;
  const year = d => Number(d.slice(0,4)) + (Number(d.slice(5,7)) >= 10 ? 1 : 0);
  const safe = p => typeof p === "string" && /^[A-Za-z0-9_./-]+$/.test(p) && !p.startsWith("/") && !p.split("/").some(x => x === "." || x === ".." || !x);
  function validate(c) {
    if (c.schema_version !== 1 || c.archive_pilot !== true || !Array.isArray(c.months) || !c.months.length) throw Error("Invalid pilot archive catalog.");
    const all = new Set(), keys = new Set();
    for (const m of c.months) {
      if (!/^\d{4}-\d{2}$/.test(m.month) || keys.has(m.month) || !safe(m.path) || !Array.isArray(m.dates) || !m.dates.length) throw Error("Invalid month partition.");
      keys.add(m.month);
      for (const d of m.dates) {
        if (!iso(d) || !d.startsWith(m.month) || year(d) !== m.water_year || all.has(d)) throw Error("Invalid or duplicate archived date.");
        all.add(d);
      }
      if (m.dates.join() !== [...m.dates].sort().join()) throw Error("Unsorted archive dates.");
    }
    if (!all.has(c.latest)) throw Error("Latest archive date is not built.");
    return c;
  }
  function partition(c,d) { return c.months.find(m => m.dates.includes(d)); }
  function needed(c,d) {
    if (!partition(c,d)) throw Error("This date was not built in the local pilot.");
    const center = new Date(`${d}T12:00:00Z`), a = new Date(center), b = new Date(center);
    a.setUTCDate(a.getUTCDate()-29); b.setUTCDate(b.getUTCDate()+3);
    const first = a.toISOString().slice(0,10), last = b.toISOString().slice(0,10);
    return c.months.filter(m => m.dates.some(x => x >= first && x <= last));
  }
  function records(parts) {
    const map = new Map();
    for (const p of parts) {
      if (p.schema_version !== 1 || !Array.isArray(p.days)) throw Error("Invalid archive data.");
      for (const d of p.days) {
        if (!iso(d.date) || d.water_year !== year(d.date) || map.has(d.date)) throw Error("Duplicate or invalid day record.");
        if (Object.keys(d.images || {}).length !== 7 || !Object.values(d.images).every(safe)) throw Error("Incomplete or unsafe map references.");
        map.set(d.date,d);
      }
    }
    return [...map.values()].sort((a,b) => a.date.localeCompare(b.date));
  }
  return {validate,partition,needed,records,year,safe};
})();
if (typeof module !== "undefined") module.exports = SWCArchive;
