// Offline controller checks; no browser, network, or dependencies required.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const families = ['temperature', 'precipitation', 'spi'];
const durations = ['1', '3', '6', '12'];
function element(extra = {}) {
  return Object.assign({ listeners: {}, attributes: {},
    addEventListener(name, handler) { this.listeners[name] = handler; },
    setAttribute(name, value) { this.attributes[name] = value; },
    getAttribute(name) { return this.attributes[name]; },
    click() { this.listeners.click(); }, focus() { this.focused = true; }
  }, extra);
}
const panels = Object.fromEntries(families.map(f => [`monthly-panel-${f}`, element()]));
const tabs = families.map(f => element({ id: `monthly-tab-${f}`, attributes: { 'aria-controls': `monthly-panel-${f}` } }));
const maps = families.flatMap(f => durations.map(d => element({ family: f, dataset: { duration: d } })));
const selector = element({ value: '1' });
const root = { querySelectorAll: q => q === '[role="tab"]' ? tabs : maps,
  querySelector: () => selector, classList: { add() {} } };
vm.runInNewContext(fs.readFileSync('site/assets/monthly-climate.js', 'utf8'), {
  document: { querySelector: () => root, getElementById: id => panels[id] }
});
for (const duration of durations) {
  selector.value = duration; selector.listeners.change();
  for (let index = 0; index < families.length; index++) {
    tabs[index].click();
    assert.equal(selector.value, duration);
    for (let p = 0; p < families.length; p++) {
      assert.equal(panels[`monthly-panel-${families[p]}`].hidden, p !== index);
      assert.equal(tabs[p].attributes['aria-selected'], String(p === index));
      assert.equal(tabs[p].tabIndex, p === index ? 0 : -1);
    }
    for (const map of maps) assert.equal(map.hidden, map.dataset.duration !== duration);
  }
}
tabs[2].listeners.keydown({ key: 'ArrowRight', preventDefault() {} });
assert.equal(tabs[0].attributes['aria-selected'], 'true');
assert.equal(tabs[0].focused, true);
assert.equal(selector.value, '12');
console.log('PASS: all 12 tab/period combinations, duration retention, and keyboard wrap.');
