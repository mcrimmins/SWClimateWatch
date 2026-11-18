/* Shared daily-chart selection and client-side export; no data requests. */
window.SWCStationChartTools = (() => {
  const dayDate = hit => hit?.dataset.temperatureDate || hit?.dataset.precipitationDate;
  function selectDay(root, hit, render) {
    const selected = dayDate(hit);
    if (!selected) return;
    for (const candidate of root.querySelectorAll('.detail-charts .chart-day')) {
      const matches = dayDate(candidate) === selected;
      candidate.tabIndex = matches ? 0 : -1;
      candidate.classList.toggle('chart-selected', matches);
      if (matches) {
        const readout = candidate.closest('figure')?.querySelector('.chart-readout');
        if (readout) render(candidate, readout);
      }
    }
    return selected;
  }
  const fields = [
    ['pcpn','precipitation_inches'],['pcpn_status','precipitation_status'],
    ['pcpn_record_observation_status','precipitation_record_observation_status'],
    ['maxt','high_f'],['maxt_status','high_status'],['mint','low_f'],['mint_status','low_status'],
    ['normal_maxt','normal_high_f'],['normal_mint','normal_low_f'],['normal_years','normal_minimum_sample_years'],
    ['record_high','earlier_record_high_f'],['record_high_years','earlier_record_high_years'],
    ['record_high_status','high_record_status'],['record_high_n','high_record_sample_years'],
    ['record_low','earlier_record_low_f'],['record_low_years','earlier_record_low_years'],
    ['record_low_status','low_record_status'],['record_low_n','low_record_sample_years'],
    ['record_pcpn','earlier_record_precipitation_inches'],['record_pcpn_years','earlier_record_precipitation_years'],
    ['record_pcpn_status','precipitation_record_status'],['record_pcpn_n','precipitation_record_sample_years']
  ];
  function cell(value) {
    if (value == null || (typeof value === 'number' && !Number.isFinite(value))) return '';
    if (typeof value === 'number') return String(value);
    // Prevent station names/labels from becoming spreadsheet formulas.
    let text = String(value);
    if (/^[\s]*[=+@-]/.test(text)) text = "'" + text;
    return '"' + text.replace(/"/g, '""') + '"';
  }
  function dailyCsv(station, detail) {
    if (String(station.uid) !== String(detail.uid) || station.as_of !== detail.as_of)
      throw Error('Station export does not match the selected station/date.');
    const header = ['station_uid','station_id','station_name','state','station_role','summary_period',
      'period_start','period_end','date',...fields.map(x=>x[1]),'normal_reference','record_reference'];
    const rows = detail.daily.filter(day=>day.date>=station.period_start && day.date<=station.as_of)
      .map(day=>[station.uid,station.sid,station.name,station.state,station.role,station.period,
        station.period_start,station.as_of,day.date,...fields.map(([key])=>day[key]),
        'Project-calculated 1991–2020 paired-day normals; centered 15-day smoothing',
        'Earlier eligible years on exact calendar date; not certified official records']);
    return '\uFEFF' + [header,...rows].map(row=>row.map(cell).join(',')).join('\r\n')+'\r\n';
  }
  function download(station, detail) {
    const blob = new Blob([dailyCsv(station,detail)],{type:'text/csv;charset=utf-8'});
    const url = URL.createObjectURL(blob), link = document.createElement('a');
    link.href = url;
    link.download = `station-${String(station.uid).replace(/[^0-9]/g,'')}-daily-${station.period_start}-to-${station.as_of}.csv`;
    document.body.append(link);link.click();link.remove();
    setTimeout(()=>URL.revokeObjectURL(url),1000);
  }
  return {selectDay,dailyCsv,download};
})();
