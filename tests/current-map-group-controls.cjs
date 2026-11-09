// Integration checks using the generated local pilot's actual combinations.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const siteMode = process.argv.includes('--site');
const rootDir = siteMode ? 'site/pages' : 'data/diagnostics/temperature-tabs-preview';
const groups = [...(siteMode ? ['temperature-values','temperature-departures','precipitation-totals','precipitation-ranks','temperature-extremes','freeze-nights','precipitation-percent-normal','precipitation-change','water-year-precipitation','water-year-extremes'] : []),
  'temperature-daily-ranks', 'temperature-rolling-ranks', 'freeze-monitoring', 'dry-spells', 'wet-days', 'snow-conditions'];
function fixture(group, query = '') {
  const html = fs.readFileSync(`${rootDir}/${group}.qmd`, 'utf8');
  function element(extra = {}) {
    return Object.assign({ attrs: {}, listeners: {}, children: [],
      addEventListener(n, fn) { this.listeners[n] = fn; },
      setAttribute(n, v) { this.attrs[n] = v; }, removeAttribute(n) { delete this.attrs[n]; },
      replaceChildren(...children) { this.children = children; },
      click() { this.listeners.click(); }, focus() { this.focused = true; }
    }, extra);
  }
  const maps = [...html.matchAll(/<article[^>]+data-tab="([^"]+)" data-variant="([^"]+)" data-option="([^"]+)"/g)]
    .map(m => element({ dataset: { tab: m[1], variant: m[2], option: m[3] } }));
  const tabNames = [...new Set(maps.map(m => m.dataset.tab))];
  const tabs = tabNames.map(tab => element({ dataset: { tab } }));
  const variant = element(); const control = element(); const panel = element(); const tablist = element();
  const layout = group === 'snow-conditions' ? element({ value: 'single' }) : null;
  const classes = new Set();
  const root = { querySelectorAll: s => s === '[role="tab"]' ? tabs : maps,
    querySelector: s => ({ '#group-variant': variant, '.group-variant-control': control,
      '#group-layout': layout, '[role="tablist"]': tablist, '#group-maps': panel })[s],
    classList: { add(c) { classes.add(c); }, toggle(c, on) { if (on) classes.add(c); else classes.delete(c); } } };
  const window = { location: { search: query, href: `http://localhost/${group}.html${query}` },
    history: { replaceState(a,b,url) { window.lastUrl = url; } } };
  vm.runInNewContext(fs.readFileSync('scripts/temperature-tabs-preview-assets/current-map-groups.js', 'utf8'), {
    document: { querySelector: () => root, createElement: () => element() }, window, URL, URLSearchParams
  });
  return { maps, tabs, variant, control, panel, layout, tablist, classes, window };
}
let combinations = 0;
for (const group of groups) {
  const f = fixture(group);
  for (const tab of f.tabs) {
    tab.click();
    const choices = f.maps.filter(m => m.dataset.tab === tab.dataset.tab);
    assert.deepEqual(f.variant.children.map(o => o.value), choices.map(m => m.dataset.variant));
    for (const map of choices) {
      f.variant.value = map.dataset.variant; f.variant.listeners.change();
      assert.deepEqual(f.maps.filter(m => !m.hidden), [map]);
      assert.equal(f.variant.value, map.dataset.variant);
      assert.equal(f.window.lastUrl.searchParams.get('tab'), tab.dataset.tab);
      assert.equal(f.window.lastUrl.searchParams.get('display'), map.dataset.variant);
      combinations++;
    }
  }
  assert.equal(f.control.hidden, f.variant.children.length === 1);
  assert.equal(f.tablist.hidden, f.tabs.length === 1);
  const url = f.window.lastUrl;
  const saved = fixture(group, url.search);
  assert.equal(saved.maps.filter(m => !m.hidden)[0].dataset.tab, url.searchParams.get('tab'));
  const invalid = fixture(group, '?tab=bad&display=bad&view=bad');
  assert.equal(invalid.maps.filter(m => !m.hidden).length, 1);
  f.tabs.at(-1).listeners.keydown({key:'ArrowRight', preventDefault(){}});
  assert.equal(f.tabs[0].focused, true);
}
const freeze = fixture('freeze-monitoring');
freeze.tabs[2].click(); assert.equal(freeze.variant.children[0].textContent, 'Length');
freeze.variant.value = 'departure'; freeze.variant.listeners.change();
freeze.tabs[0].click(); assert.equal(freeze.variant.value, 'departure');
assert.equal(freeze.variant.children[0].textContent, 'Date');
const snow = fixture('snow-conditions'); snow.tabs[2].click();
snow.layout.value = 'all'; snow.layout.listeners.change();
assert.equal(snow.maps.filter(m => !m.hidden).length, 4);
assert.equal(snow.tablist.hidden, true); assert.equal(snow.panel.attrs.role, 'region');
snow.layout.value = 'single'; snow.layout.listeners.change();
assert.equal(snow.maps.filter(m => !m.hidden)[0].dataset.tab, 'percent');
assert.equal(snow.panel.attrs.role, 'tabpanel');
const allSaved = fixture('snow-conditions', '?view=all&tab=change&display=map');
assert.equal(allSaved.maps.filter(m => !m.hidden).length, 4);
console.log(`PASS: ${combinations} grouped views; options, labels, retained selection, bookmarks, keyboard and snow grid.`);
