const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const context=vm.createContext({window:{}});
vm.runInContext(fs.readFileSync('scripts/station-temperature-normals-assets/temperature-normals.js','utf8'),context);
assert.equal(fs.readFileSync('scripts/station-explorer-assets/temperature-normals.js','utf8'),
  fs.readFileSync('scripts/station-temperature-normals-assets/temperature-normals.js','utf8'));
const integrated=fs.readFileSync('scripts/station-explorer-assets/explorer.js','utf8');
assert.match(integrated,/Normals.precipitationBarStyle\(day\)/);
assert.match(integrated,/Normals.renderReadout\(hit,readout\)/);
assert.match(integrated,/selectedExtremeSummary\(station\) \+ `<details class="station-cumulative"><summary>Seasonal precipitation and historical comparisons<\/summary>/);
assert.doesNotMatch(integrated,/<details class="station-cumulative"[^>]* open/);
assert.doesNotMatch(integrated,/station-seasonal-integration/);
const integratedSeasonal=fs.readFileSync('scripts/station-seasonal-assets/index.html','utf8');
assert.doesNotMatch(integratedSeasonal,/station-history-toggle/);
assert.match(integratedSeasonal,/<section id="station-card"/);
assert.match(integratedSeasonal,/<section id="annual-history"/);
assert.match(integratedSeasonal,/<details class="card methods"><summary>How to read these plots<\/summary>/);
const adapter=context.window.SWCStationTemperatureNormals;
const days=[{normal_maxt:80,normal_mint:50,normal_years:30,maxt:90,mint:45},
  {normal_maxt:null,normal_mint:null,normal_years:19,maxt:null,mint:null},
  {normal_maxt:82,normal_mint:52,normal_years:25,maxt:null,mint:52}];
const paths=adapter.paths(days,i=>i,v=>v);
assert.match(paths,/stroke-dasharray="6 4"/);
assert.match(paths,/M0\.0,80\.0\s+M2\.0,82\.0/);
assert.doesNotMatch(paths,/L1|NaN/);
assert.match(adapter.readout(days[0]),/normal high 80\.0°F \(\+10\.0°F departure\)/i);
assert.match(adapter.readout(days[0]),/normal low 50\.0°F \(-5\.0°F departure\)/);
assert.match(adapter.readout(days[1]),/insufficient reference support/);
assert.doesNotMatch(adapter.readout(days[2]),/NaN|normal high.*departure.*normal low/);
assert.match(adapter.legend(days,{smoothing_days:15,minimum_years:20}),/1991–2020 normal/);
assert.match(adapter.legend([days[1]],{}),/unavailable/);
const event={maxt:110,mint:25,record_high:108,record_low:25,record_high_years:'1990,2005',
  record_low_years:'1980',record_high_n:80,record_low_n:79,record_high_first_year:1940,
  record_high_last_year:2025,record_low_first_year:1940,record_low_last_year:2025,
  record_high_status:'NEW_HIGH',record_low_status:'TIED_LOW'};
const recordText=adapter.readout(event);
assert.match(recordText,/Earlier record high: 108.0°F \(1990, 2005\)/);
assert.match(recordText,/NEW HIGH/);assert.match(recordText,/TIED LOW/);
assert.match(adapter.markers([event],i=>i,v=>v),/class="chart-new-record"/);
assert.match(adapter.markers([event],i=>i,v=>v),/class="chart-tied-record"/);
assert.doesNotMatch(adapter.markers([event],i=>i,v=>v),/<circle|fill="none"/);
for(const length of [7,30,90,184,365]) {
  const rendered=adapter.markers(Array(length).fill(event),i=>i,v=>v);
  assert.equal((rendered.match(/chart-new-record/g)||[]).length,length);
  assert.equal((rendered.match(/chart-tied-record/g)||[]).length,length);
}
assert.match(adapter.legend(Array(91).fill(event),{},{}),/High: 91 new, 0 tied/);
assert.doesNotMatch(adapter.legend(Array(91).fill(event),{},{}),/Markers hidden/);
assert.match(adapter.legend([event],{},{}),/Dotted: earlier record/);
const selected={...event,date:'2026-10-14',normal_maxt:87.5,normal_mint:58.9,normal_years:30};
assert.ok(adapter.tooltip(selected).length<150);
assert.match(adapter.tooltip(selected),/Oct 14, 2026\nHigh/);
assert.doesNotMatch(adapter.tooltip(selected),/1940|1990|valid years|Normal/);
const table=adapter.readoutHtml(selected);
assert.match(table,/<table/);assert.match(table,/1990, 2005/);
assert.match(table,/Reference coverage/);assert.doesNotMatch(table,/<details[^>]* open/);
assert.match(table,/temperature-delta warm/);assert.match(table,/temperature-delta cool/);
assert.doesNotMatch(adapter.readoutHtml({...selected,record_high_years:'<img onerror="x">'}),/<img/);
adapter.bind([selected],{});
const container={innerHTML:'',querySelector:()=>null};
assert.equal(adapter.renderReadout({dataset:{temperatureDate:selected.date}},container),true);
assert.match(container.innerHTML,/<table/);
assert.equal(adapter.renderReadout({dataset:{}},container),false);
assert.match(adapter.hit(selected,10,20,true),/data-temperature-date="2026-10-14"/);
const rain={date:'2026-10-14',pcpn:2.25,pcpn_status:'AVAILABLE',record_pcpn:2,
  record_pcpn_years:'1985,2000',record_pcpn_n:78,record_pcpn_first_year:1946,
  record_pcpn_last_year:2025,record_pcpn_status:'NEW_RECORD'};
assert.ok(adapter.precipitationTooltip(rain).length<150);
assert.doesNotMatch(adapter.precipitationTooltip(rain),/1946|1985|valid years/);
assert.match(adapter.precipitationReadoutHtml(rain),/2.25 in./);
assert.match(adapter.precipitationReadoutHtml(rain),/1985, 2000/);
assert.match(adapter.precipitationReadoutHtml(rain),/New daily record/);
assert.doesNotMatch(adapter.precipitationReadoutHtml(rain),/<details[^>]* open/);
assert.match(adapter.precipitationObserved({...rain,pcpn_status:'TRACE'}),/Trace/);
assert.match(adapter.precipitationObserved({...rain,pcpn_record_observation_status:'ACCUMULATED'}),/not a daily total/);
assert.match(adapter.precipitationObserved({...rain,pcpn_status:'FLAGGED'}),/withheld/);
assert.match(adapter.precipitationObserved({...rain,pcpn_status:'MISSING'}),/Missing/);
const zero={...rain,pcpn:0,record_pcpn:0,record_pcpn_years:'',record_pcpn_status:'NO_MEASURABLE_RECORD'};
assert.match(adapter.precipitationReadoutHtml(zero),/No measurable rain/);
assert.doesNotMatch(adapter.precipitationReadoutHtml(zero),/Tied daily record/);
adapter.bind([rain],{});
assert.equal(adapter.renderReadout({dataset:{precipitationDate:rain.date}},container),true);
assert.match(container.innerHTML,/Daily precipitation comparison/);
assert.match(adapter.precipitationHit(rain,10,20,true),/data-precipitation-date="2026-10-14"/);
assert.match(adapter.precipitationBarStyle(rain),/#703b86/);
assert.match(adapter.precipitationBarStyle({...rain,record_pcpn_status:'TIED_RECORD'}),/url\(#precipitation-record-tie\)/);
assert.match(adapter.precipitationBarStyle({...rain,pcpn_status:'TRACE',pcpn_record_observation_status:'TRACE'}),/#327eaa/);
assert.match(adapter.precipitationBarStyle({...rain,record_pcpn:null}),/#327eaa/);
assert.match(adapter.precipitationLegend(),/Wettest day/);
assert.match(adapter.precipitationLegend(),/selected period/);
assert.match(adapter.precipitationDefinitions(),/patternUnits="userSpaceOnUse"/);
const root='data/diagnostics/station-temperature-normals-preview';
if(fs.existsSync(root+'/index.html')){
  const js=fs.readFileSync(root+'/explorer.js','utf8'),html=fs.readFileSync(root+'/index.html','utf8');
  assert.match(js,/days\.flatMap\(day => \[day.maxt, day.mint, day.normal_maxt, day.normal_mint, day.record_high, day.record_low\]\)/);
  assert.match(js,/Normals.paths\(days,x,y\) \+ line\("maxt"/);
  assert.match(js,/Normals.markers\(days,x,y\) \+ empty \+ hits/);
  assert.doesNotMatch(js,/marks \+ window.SWCStationTemperatureNormals.markers/);
  assert.match(js,/Normals.bind\(days,station\)/);
  assert.match(js,/Normals.hit\(day,/);
  assert.match(js,/Normals.renderReadout\(hit,readout\)/);
  assert.match(js,/Normals.precipitationHit\(day,/);
  assert.ok(html.indexOf('src="temperature-normals.js"')<html.indexOf('src="explorer.js"'));
  assert.match(js,/selectedExtremeSummary\(station\) \+ `<section class="station-cumulative"/);
  const extremesStart=js.indexOf('function selectedExtremeSummary(station)');
  const dailyStart=js.indexOf('function detailContent(station, detail)');
  const standingPosition=js.indexOf('<h3>Historical standing</h3>');
  assert.ok(standingPosition>extremesStart && standingPosition<dailyStart);
  assert.ok(standingPosition<js.indexOf('<h3>Frequency and persistence</h3>'));
  assert.equal((js.match(/<h3>Historical standing<\/h3>/g)||[]).length,1);
  const seasonal=fs.readFileSync(root+'/seasonal/index.html','utf8');
  assert.match(seasonal,/<base href="\.\.\/\.\.\/station-seasonal-integration\/seasonal\/">/);
  assert.equal((seasonal.match(/class="card station-history-toggle"/g)||[]).length,2);
  assert.doesNotMatch(seasonal,/<details[^>]*station-history-toggle[^>]* open/);
}
console.log('PASS: normal-line gaps, high/low departures, support notices and local chart hooks.');
