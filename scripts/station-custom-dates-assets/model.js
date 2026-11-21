(function (root) {
  'use strict';
  const DAY = 86400000;
  function day(value) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw Error('Choose valid calendar dates.');
    const time = Date.parse(value + 'T00:00:00Z');
    if (!Number.isFinite(time) || new Date(time).toISOString().slice(0, 10) !== value) throw Error('Invalid calendar date.');
    return time / DAY;
  }
  const iso = value => new Date(value * DAY).toISOString().slice(0, 10);
  function decode(data, uid) {
    if (data.schema !== 1 || String(data.uid) !== String(uid) || day(data.end) - day(data.start) + 1 !== data.n)
      throw Error('Station history identity or dates do not match.');
    const chunk = {...data, first: day(data.start)};
    for (const field of ['pcpn', 'maxt', 'mint']) {
      for (const name of [field, field + '_status']) chunk[name] = Array.isArray(data[name]) ? data[name] : [data[name]];
      if (chunk[field].length !== data.n || chunk[field + '_status'].length !== data.n) throw Error('Incomplete history chunk.');
      for (let i = 0; i < data.n; i++) {
        const status = chunk[field + '_status'][i], value = chunk[field][i];
        if (![0, 1, 2, 3].includes(status) || ((status === 1 || status === 2) && !Number.isFinite(value)) ||
            ((status === 0 || status === 3) && value != null)) throw Error('Invalid observation/status pair.');
      }
    }
    return chunk;
  }
  function select(chunks, start, end) {
    const first = day(start), last = day(end);
    if (first > last) throw Error('Start date must be on or before end date.');
    const result = [];
    for (const chunk of [...chunks].sort((a, b) => a.first - b.first)) {
      for (let i = Math.max(0, first - chunk.first); i < chunk.n && chunk.first + i <= last; i++) {
        const time = chunk.first + i;
        if (time < first) continue;
        if (time !== first + result.length) throw Error('Missing or overlapping annual history files.');
        result.push({date: iso(time), pcpn: chunk.pcpn[i], maxt: chunk.maxt[i], mint: chunk.mint[i],
          pcpn_status: chunk.pcpn_status[i], maxt_status: chunk.maxt_status[i], mint_status: chunk.mint_status[i]});
      }
    }
    if (result.length !== last - first + 1) throw Error('The requested period is not fully represented.');
    return result;
  }
  function summarize(rows) {
    if (!rows.length) throw Error('No selected days.');
    const p = {sum: 0, valid: 0, missing: 0, flagged: 0, trace: 0, max: null, dates: []};
    const t = {sum: 0, paired: 0, missing: 0, flagged: 0, high: null, low: null, highDates: [], lowDates: []};
    for (const r of rows) {
      if (r.pcpn == null) {p[r.pcpn_status === 3 ? 'flagged' : 'missing']++;}
      else {
        p.sum += r.pcpn; p.valid++; if (r.pcpn_status === 2) p.trace++;
        if (p.max == null || r.pcpn > p.max) {p.max = r.pcpn; p.dates = [r.date];}
        else if (r.pcpn === p.max) p.dates.push(r.date);
      }
      if (r.maxt != null && r.mint != null) {t.sum += (r.maxt + r.mint) / 2; t.paired++;}
      else t[r.maxt_status === 3 || r.mint_status === 3 ? 'flagged' : 'missing']++;
      if (r.maxt != null) {
        if (t.high == null || r.maxt > t.high) {t.high = r.maxt; t.highDates = [r.date];}
        else if (r.maxt === t.high) t.highDates.push(r.date);
      }
      if (r.mint != null) {
        if (t.low == null || r.mint < t.low) {t.low = r.mint; t.lowDates = [r.date];}
        else if (r.mint === t.low) t.lowDates.push(r.date);
      }
    }
    p.value = p.valid ? p.sum : null; p.complete = p.valid === rows.length;
    t.mean = t.paired ? t.sum / t.paired : null; t.complete = t.paired === rows.length;
    return {days: rows.length, start: rows[0].date, end: rows[rows.length - 1].date, p, t};
  }
  function bins(rows, maximum = 600) {
    const step = Math.max(1, Math.ceil(rows.length / maximum)), result = [];
    for (let i = 0; i < rows.length; i += step) {
      const part = rows.slice(i, i + step), s = summarize(part);
      const paired = part.filter(r => r.maxt != null && r.mint != null);
      result.push({...s, high: paired.length ? paired.reduce((a, r) => a + r.maxt, 0) / paired.length : null,
        low: paired.length ? paired.reduce((a, r) => a + r.mint, 0) / paired.length : null});
    }
    return {step, values: result};
  }
  function csv(rows, station) {
    const cell = value => {
      if (value == null) return '';
      if (typeof value === 'number') return String(value);
      let s = String(value); if (/^[\s]*[=+@-]/.test(s)) s = "'" + s;
      return '"' + s.replace(/"/g, '""') + '"';
    };
    const labels = ['MISSING', 'AVAILABLE', 'TRACE', 'FLAGGED'];
    const header = ['station_uid', 'station_id', 'station_name', 'date', 'precipitation_inches', 'high_f', 'low_f',
      'precipitation_status', 'high_status', 'low_status'];
    return '\uFEFF' + [header, ...rows.map(r => [station.uid, station.sid, station.name, r.date,
      r.pcpn, r.maxt, r.mint, labels[r.pcpn_status], labels[r.maxt_status], labels[r.mint_status]])]
      .map(r => r.map(cell).join(',')).join('\r\n') + '\r\n';
  }
  const api = {DAY, day, iso, decode, select, summarize, bins, csv};
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.StationCustomModel = api;
})(typeof window === 'undefined' ? globalThis : window);
