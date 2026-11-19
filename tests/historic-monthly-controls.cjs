const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('scripts/historic-monthly-pilot-assets/controls.js', 'utf8');
const {selection, matches} = require('../scripts/historic-monthly-pilot-assets/controls.js');
const metrics = ['precipitation_total', 'precipitation_rank', 'temperature_mean', 'temperature_departure', 'temperature_rank'];
const cards = [];
for (const year of ['2002', '2005', '2020']) for (const period of ['water-year', 'cool-season', 'spring', 'monsoon']) {
  for (const metric of [...metrics, ...(period === 'water-year' ? ['spi12'] : [])]) cards.push({dataset: {year, period, metric}});
}
assert.equal(cards.length, 63);
for (const year of ['all', '2002', '2005', '2020']) for (const period of ['water-year', 'cool-season', 'spring', 'monsoon']) {
  for (const metric of [...metrics, 'spi12', 'all']) {
    const s = selection(year, period, metric);
    const n = cards.filter(c => matches(c.dataset, s)).length;
    const perYear = metric === 'all' ? (period === 'water-year' ? 6 : 5) : 1;
    assert.equal(n, perYear * (year === 'all' ? 3 : 1));
  }
}
const controls = Object.fromEntries(['year','period','metric','selection-status'].map(id => [id, {
  value: id === 'year' ? 'all' : id === 'period' ? 'spring' : 'temperature_rank',
  disabled: false, selectedIndex: 0, options: [{text: 'fixture'}], handlers: {},
  addEventListener(event, handler) { this.handlers[event] = handler; }
}]));
vm.runInNewContext(source, {document: {getElementById: id => controls[id], querySelectorAll: () => cards}});
assert.equal(cards.filter(c => !c.hidden).length, 3);
controls.metric.value = 'spi12'; controls.metric.handlers.change();
assert.equal(controls.period.value, 'water-year'); assert.equal(controls.period.disabled, true);
assert.equal(cards.filter(c => !c.hidden).length, 3);
controls.metric.value = 'precipitation_total'; controls.metric.handlers.change();
assert.equal(controls.period.value, 'spring'); assert.equal(controls.period.disabled, false);
controls.year.value = '2005'; controls.year.handlers.change();
assert.equal(cards.filter(c => !c.hidden).length, 1);
controls.metric.value = 'all'; controls.metric.handlers.change();
assert.equal(cards.filter(c => !c.hidden).length, 5);
controls.period.value = 'monsoon'; controls.period.handlers.change();
assert.equal(cards.filter(c => !c.hidden).length, 5);
console.log('PASS: 112 year/period/metric combinations, 63 cards, SPI-only water-year guard, spring restoration and monsoon change wiring.');
