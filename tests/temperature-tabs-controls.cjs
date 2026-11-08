// Offline checks for grouped temperature views and bookmark state.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
function fixture(departures, query = '') {
  const variables = ['maxt', 'tmean', 'mint'];
  const periods = departures ? ['daily', '30day'] : ['daily'];
  function element(extra = {}) {
    return Object.assign({ listeners: {}, attributes: {},
      addEventListener(name, fn) { this.listeners[name] = fn; },
      setAttribute(name, value) { this.attributes[name] = value; },
      getAttribute(name) { return this.attributes[name]; },
      click() { this.listeners.click(); }, focus() { this.focused = true; }
    }, extra);
  }
  const panels = Object.fromEntries(variables.map(v => [`temperature-panel-${v}`, element()]));
  const tabs = variables.map(v => element({ id: `temperature-tab-${v}`, attributes: { 'aria-controls': `temperature-panel-${v}` } }));
  const maps = variables.flatMap(variable => periods.map(period => element({ variable, dataset: { period } })));
  const selector = departures ? element({ value: 'daily' }) : null;
  const root = { querySelectorAll: q => q === '[role="tab"]' ? tabs : maps,
    querySelector: () => selector, classList: { add() {} } };
  const window = { location: { search: query, href: `http://localhost/${departures ? 'departures' : 'index'}.html${query}` },
    history: { replaceState(a, b, url) { window.lastUrl = url; } } };
  vm.runInNewContext(fs.readFileSync('scripts/temperature-tabs-preview-assets/temperature-tabs.js', 'utf8'), {
    document: { querySelector: () => root, getElementById: id => panels[id] }, window, URL, URLSearchParams
  });
  return { variables, periods, tabs, maps, selector, panels, window };
}
for (const departures of [false, true]) {
  const f = fixture(departures);
  for (const period of f.periods) {
    if (f.selector) { f.selector.value = period; f.selector.listeners.change(); }
    f.tabs.forEach((tab, i) => {
      tab.click();
      f.variables.forEach((variable, j) => {
        assert.equal(f.panels[`temperature-panel-${variable}`].hidden, i !== j);
        assert.equal(f.tabs[j].attributes['aria-selected'], String(i === j));
        assert.equal(f.tabs[j].tabIndex, i === j ? 0 : -1);
      });
      f.maps.forEach(map => assert.equal(map.hidden, map.dataset.period !== period));
      assert.equal(f.window.lastUrl.searchParams.get('variable'), f.variables[i]);
      if (f.selector) assert.equal(f.window.lastUrl.searchParams.get('period'), period);
    });
  }
  f.tabs[2].listeners.keydown({ key: 'ArrowRight', preventDefault() {} });
  assert.equal(f.tabs[0].focused, true);
}
const saved = fixture(true, '?variable=mint&period=30day');
assert.equal(saved.selector.value, '30day');
assert.equal(saved.panels['temperature-panel-mint'].hidden, false);
const invalid = fixture(true, '?variable=invalid&period=invalid');
assert.equal(invalid.selector.value, 'daily');
assert.equal(invalid.panels['temperature-panel-maxt'].hidden, false);
console.log('PASS: all 9 views, retained periods, keyboard tabs, saved URLs and invalid-state defaults.');
