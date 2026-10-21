// Run with: node tests/test-daily-explorer-ui.cjs (no browser dependencies).
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const controls = {compare: {value: 'single'}};
const context = vm.createContext({document: {getElementById: id => controls[id]}});
const code = fs.readFileSync('scripts/daily-explorer-assets/explorer.js', 'utf8')
  .replace(/initialize\(\);\s*$/, '');
vm.runInContext(code, context);
const evaluate = expression => vm.runInContext(expression, context);
evaluate('selectedDate = "2026-10-02"');
assert.equal(evaluate('comparisonDates().length'), 0);
controls.compare.value = '7';
assert.equal(evaluate('comparisonDates().length'), 7);
assert.equal(evaluate('comparisonDates()[0]'), '2026-09-29');
assert.equal(evaluate('comparisonDates().at(-1)'), '2026-10-05');
controls.compare.value = '30';
assert.equal(evaluate('comparisonDates().length'), 30);
assert.equal(evaluate('comparisonDates()[0]'), '2026-09-03');
assert.equal(evaluate('comparisonDates().at(-1)'), '2026-10-02');
evaluate('selectedDate = "2024-03-01"');
assert.equal(evaluate('comparisonDates()[0]'), '2024-02-01');
assert.equal(evaluate('METRICS.tmean.mean[1]'), '°F');
assert.equal(evaluate('"warm" in METRICS.tmean'), false);
// Both renderers must consume the shared window; navigation/rankings retain
// seasonal visibleDates rather than being accidentally restricted by Map View.
assert.match(code, /const timelineDates = .*comparisonDates\(\)/);
assert.match(code, /for \(const date of comparisonDates\(\)\)/);
assert.doesNotMatch(code, /addStat\("Regional data coverage"/);
// Date controls use the complete cache, not the selected water year.
controls.year = {value: '2027'};
controls.season = {value: 'cool'};
evaluate(`days = [
  {date: '2026-09-30', water_year: 2026},
  {date: '2026-10-01', water_year: 2027}
]; byDate = new Map(days.map(day => [day.date, day])); render = () => {};`);
assert.equal(evaluate('inCachedDateRange(shift("2026-10-01", -1))'), true);
assert.equal(evaluate('inCachedDateRange(shift("2026-09-30", 1))'), true);
assert.equal(evaluate('inCachedDateRange("2026-09-29")'), false);
assert.equal(evaluate('inCachedDateRange("2026-10-02")'), false);
evaluate('selectDate("2026-09-30")');
assert.equal(controls.year.value, '2026');
assert.equal(controls.season.value, 'all');
assert.equal(evaluate('selectedDate'), '2026-09-30');
evaluate('selectDate("2026-10-01")');
assert.equal(controls.year.value, '2027');
assert.equal(evaluate('selectedDate'), '2026-10-01');
console.log('Daily Explorer UI: date windows, leap day, mean metrics and hidden coverage passed.');
