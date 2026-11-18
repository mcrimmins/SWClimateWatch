// Exercise the real initialization, event handlers and renderers together.
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
function element(tag = 'div') {
  return {tag, children: [], attributes: {}, listeners: {}, value: '', hidden: false, open: false,
    textContent: '', style: {}, classList: {toggle() {}},
    get selectedOptions() {return [this.children.find(x => x.value === this.value) || {textContent: this.value}];},
    append(...nodes) {this.children.push(...nodes); if (this.tag === 'select' && !this.value) this.value = nodes[0].value;},
    replaceChildren(...nodes) {this.children = nodes; if (this.tag === 'select') this.value = nodes[0]?.value || '';},
    setAttribute(key, value) {this.attributes[key] = value;},
    getAttribute(key) {return key === 'src' ? this.src || null : this.attributes[key] || null;},
    removeAttribute(key) {delete this.attributes[key]; delete this[key];},
    addEventListener(key, value) {this.listeners[key] = value;}, focus() {}, scrollIntoView() {}};
}
const html = fs.readFileSync('scripts/daily-explorer-assets/index.html', 'utf8');
const controls = Object.fromEntries([...html.matchAll(/<(\w+)([^>]*\bid="([^"]+)"[^>]*)>/g)]
  .map(([, tag, , id]) => [id, element(tag)]));
for (const [id, value] of Object.entries({season:'all', region:'AZNM', variable:'pcpn', view:'departure',
  compare:'single', 'circulation-compare':'single'})) controls[id].value = value;
const dates = Array.from({length:62}, (_, i) => new Date(Date.UTC(2026, 8, 1 + i)).toISOString().slice(0,10));
const days = dates.map(date => ({date, water_year:date < '2026-10-01' ? 2026 : 2027,
  images:Object.fromEntries(['pcpn_observed','maxt_observed','maxt_departure','mint_observed',
    'mint_departure','tmean_observed','tmean_departure'].map(key => [key, `maps/${date}-${key}.png`])),
  regions:Object.fromEntries(['AZNM','AZ','NM'].map(region => [region,
    Object.fromEntries(['pcpn','maxt','mint','tmean'].map(variable => [variable,
      {mean:1, departure:2, rain010:3, rain050:4, rain100:5, spatial_p99:6, warm:7, cold:8, freeze:9}]))]))}));
const weather = {schema_version:1, days:dates.filter(date => date !== '2026-11-01').map(date => ({
  date,status:'available',images:Object.fromEntries(['height500','jet250','moisture']
    .map(field => [field, `circulation/maps/${date}-${field}.png`]))}))};
let weatherRequests = 0;
const context = vm.createContext({URLSearchParams,
  document:{getElementById:id => controls[id], createElement:element},
  fetch:async url => ({ok:true, json:async () => {
    if (url === 'daily-data.json') return {schema_version:1, days, latest_cached_date:'2026-11-01',
      circulation_enabled:true, publication_mode:true, baseline:'1991-2020'};
    assert.equal(url, 'circulation-manifest.json'); weatherRequests++; return weather;
  }})});
vm.runInContext(fs.readFileSync('scripts/daily-explorer-assets/explorer.js','utf8')
  .replace(/initialize\(\);\s*$/, ''), context);
const run = expression => vm.runInContext(expression, context);
async function change(id, value) {controls[id].value = value; await controls[id].listeners.change(); await run('renderCirculation()');}
function activeFigure() {return controls['circulation-maps'].children.find(figure => !figure.hidden);}
(async () => {
  await run('initialize()');
  assert.equal(controls.date.value, '2026-11-01');
  assert.equal(controls['circulation-date-input'].value,controls.date.value);
  assert.equal(controls['circulation-date-input'].min,'2026-09-01');
  assert.equal(controls['circulation-date-input'].max,'2026-11-01');
  assert.equal(weatherRequests, 0); // Closed section has no weather traffic.
  await change('compare','30');
  assert.equal(controls['circulation-compare'].value, '30');
  controls['circulation-panel'].open = true;
  await controls['circulation-panel'].listeners.toggle();
  assert.equal(weatherRequests, 1);
  assert.equal(activeFigure().circulationGrid.children.length, 30);
  assert.match(controls['circulation-status'].textContent,/Nov 1.*No other date/);
  // Real event handlers: either mode selector updates both grids and timeline.
  for (const source of ['compare','circulation-compare']) {
    for (const mode of ['single','7','30']) {
      await change(source,mode);
      for (const variable of ['pcpn','tmean','maxt','mint']) {
        await change('variable',variable);
        for (const region of ['AZNM','AZ','NM']) {
          await change('region',region);
          assert.equal(controls.compare.value, mode);
          assert.equal(controls['circulation-compare'].value, mode);
          assert.equal(controls['circulation-date-input'].value,controls.date.value);
          assert.equal(controls['circulation-previous'].disabled,controls.previous.disabled);
          assert.equal(controls['circulation-next'].disabled,controls.next.disabled);
          assert.equal(controls['circulation-latest'].disabled,controls.latest.disabled);
          const count = mode === 'single' ? 32 : Number(mode);
          assert.equal(controls.timeline.children.length,count);
          assert.equal(controls.comparison.children.length,mode === 'single' ? 0 : Number(mode));
          assert.match(controls.map.src, new RegExp(variable));
          for (const field of ['height500','jet250','moisture']) {
            controls[`circulation-tab-${field}`].listeners.click();
            if (mode !== 'single') {
              assert.equal(activeFigure().circulationField, field);
              assert.equal(activeFigure().circulationGrid.children.length,Number(mode));
              assert.ok(activeFigure().circulationActions.children.includes(controls['circulation-view-control']));
              assert.equal(controls['circulation-view-fallback'].hidden,true);
            }
          }
        }
      }
    }
  }
  // Clicking a weather thumbnail drives the shared date, PRISM map and timeline.
  const thumbnail = activeFigure().circulationGrid.children.find(button =>
    button.attributes['aria-label'].includes('Oct 10, 2026'));
  thumbnail.listeners.click(); await run('renderCirculation()');
  assert.equal(controls.date.value,'2026-10-10');
  assert.match(controls.map.src,/2026-10-10/);
  assert.match(activeFigure().children[0].src,/2026-10-10-moisture/);
  assert.match(controls['timeline-caption'].textContent,/Oct 10/);
  await change('circulation-compare','7');
  assert.equal(controls.date.value,'2026-10-10'); // Seven days preserves selection.
  await change('circulation-compare','30');
  assert.equal(controls.date.value,'2026-11-01'); // Month view returns to latest.
  // Weather navigation uses the same date, limits, sections and active product.
  controls['circulation-previous'].listeners.click(); await run('renderCirculation()');
  assert.equal(controls.date.value,'2026-10-31');
  assert.equal(controls['circulation-date-input'].value,'2026-10-31');
  assert.match(controls['discussion-date'].textContent,/Oct 31/);
  assert.match(controls.map.src,/2026-10-31/);
  assert.equal(activeFigure().circulationField,'moisture');
  controls['circulation-next'].listeners.click(); await run('renderCirculation()');
  assert.equal(controls.date.value,'2026-11-01');
  assert.equal(controls['circulation-next'].disabled,true);
  assert.match(controls['circulation-status'].textContent,/Nov 1.*No other date/);
  await change('circulation-date-input','2026-10-01');
  controls['circulation-previous'].listeners.click(); await run('renderCirculation()');
  assert.equal(controls.date.value,'2026-09-30');
  assert.equal(controls.year.value,'2026');
  controls['circulation-next'].listeners.click(); await run('renderCirculation()');
  assert.equal(controls.date.value,'2026-10-01');
  assert.equal(controls.year.value,'2027');
  await change('circulation-date-input','2026-09-01');
  assert.equal(controls.previous.disabled,true);
  assert.equal(controls['circulation-previous'].disabled,true);
  controls['circulation-latest'].listeners.click(); await run('renderCirculation()');
  assert.equal(controls.date.value,'2026-11-01');
  assert.equal(controls['circulation-latest'].disabled,true);
  await change('circulation-date-input','2026-11-02');
  assert.equal(controls['circulation-date-input'].value,'2026-11-01');
  assert.equal(controls.date.value,'2026-11-01');
  await change('circulation-date-input','');
  assert.equal(controls['circulation-date-input'].value,'2026-11-01');
  await change('year','2026');
  assert.equal(controls.date.value,'2026-09-30');
  assert.equal(activeFigure().circulationGrid.children.length,30);
  await change('season','monsoon');
  assert.equal(controls.date.value,'2026-09-30');
  controls.latest.listeners.click(); await run('renderCirculation()');
  assert.equal(controls.year.value,'2027'); assert.equal(controls.season.value,'all');
  assert.equal(controls.date.value,'2026-11-01');
  controls.previous.listeners.click(); await run('renderCirculation()');
  assert.equal(controls.date.value,'2026-10-31');
  controls.next.listeners.click(); await run('renderCirculation()');
  assert.equal(controls.date.value,'2026-11-01');
  await change('season','monsoon'); // Current WY has no monsoon dates yet.
  assert.equal(controls.date.value,'');
  assert.match(controls['circulation-status'].textContent,/Select a date/);
  controls.latest.listeners.click(); await run('renderCirculation()');
  assert.equal(controls.date.value,'2026-11-01');
  assert.equal(weatherRequests,1);
  assert.equal(controls.error.textContent,'');
  assert.equal((html.match(/id="circulation-compare"/g) || []).length,1);
  console.log('Daily Explorer selector combinations passed: shared modes, dates, fields, regions, seasons and missing weather.');
})().catch(error => {console.error(error); process.exitCode = 1;});
