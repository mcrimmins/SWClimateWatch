const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
function fixture(periods, query = '') {
  const maps = periods.map(period => ({ dataset: { period } }));
  const selector = { addEventListener(name, fn) { this[name] = fn; } };
  const root = { querySelector: () => selector, querySelectorAll: () => maps, classList: { add() {} } };
  const window = { location: { search: query, href: `http://localhost/precipitation.html${query}` },
    history: { replaceState(a, b, url) { window.lastUrl = url; } } };
  vm.runInNewContext(fs.readFileSync('scripts/temperature-tabs-preview-assets/precipitation-periods.js', 'utf8'), {
    document: { querySelector: () => root }, window, URL, URLSearchParams
  });
  return { maps, selector, window };
}
for (const periods of [['1','7','30','90'], ['7','30','90']]) {
  const f = fixture(periods);
  assert.equal(f.selector.value, periods[0]);
  for (const period of periods) {
    f.selector.value = period; f.selector.change();
    f.maps.forEach(map => assert.equal(map.hidden, map.dataset.period !== period));
    assert.equal(f.maps.filter(map => !map.hidden).length, 1);
    assert.equal(f.window.lastUrl.searchParams.get('period'), period);
  }
  const saved = fixture(periods, '?period=90');
  assert.equal(saved.maps.find(map => !map.hidden).dataset.period, '90');
  assert.equal(fixture(periods, '?period=invalid').selector.value, periods[0]);
}
assert.equal(fixture(['7','30','90'], '?period=1').selector.value, '7');
console.log('PASS: seven precipitation views, matching panel visibility, bookmarks and unsupported-period fallback.');
