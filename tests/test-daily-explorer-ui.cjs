// Run with: node tests/test-daily-explorer-ui.cjs (no browser dependencies).
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const controls = {compare: {value: 'single'}};
const element = () => ({children: [], attributes: {}, textContent: '', hidden: false,
  listeners: {},
  append(...items) {this.children.push(...items);},
  replaceChildren(...items) {this.children = items;},
  addEventListener(name, callback) {this.listeners[name] = callback;},
  getAttribute(name) {return name === 'src' ? (this.src || null) : (this.attributes[name] || null);},
  removeAttribute(name) {delete this.attributes[name]; if (name === 'src') delete this.src; if (name === 'href') delete this.href;},
  setAttribute(name, value) {this.attributes[name] = value;}});
const context = vm.createContext({URLSearchParams, document: {
  getElementById: id => controls[id], createElement: element}});
const code = fs.readFileSync('scripts/daily-explorer-assets/explorer.js', 'utf8')
  .replace(/initialize\(\);\s*$/, '');
vm.runInContext(code, context);
const evaluate = expression => vm.runInContext(expression, context);

// Archive links are bounded UTC searches, not "latest" products or fetches.
for (const [date, end] of [['2026-09-30','2026-10-01'], ['2026-12-31','2027-01-01'],
  ['2024-02-28','2024-02-29'], ['2024-02-29','2024-03-01'], ['2026-02-28','2026-03-01']]) {
  const url = new URL(evaluate(`discussionArchiveUrl('${date}', 'AFDPSR')`));
  assert.equal(url.origin, 'https://mesonet.agron.iastate.edu');
  assert.equal(url.searchParams.get('sdate'), `${date}T00:00Z`);
  assert.equal(url.searchParams.get('edate'), `${end}T00:00Z`);
  assert.equal(url.searchParams.get('limit'), '100');
  assert.equal(url.searchParams.get('order'), 'asc');
  assert.equal(url.searchParams.get('fmt'), 'html');
}
for (const date of ['', 'bad', '2026-02-29', '2026-04-31'])
  assert.equal(evaluate(`discussionArchiveUrl('${date}', 'AFDPSR')`), null);
assert.equal(evaluate(`discussionArchiveUrl('2026-10-01', 'UNSAFE')`), null);
assert.equal(evaluate(`discussionArchiveUrl('2026-10-01', 'PMDSPD')`).includes('pil=PMDSPD'), true);
for (const id of ['discussion-date','discussion-content','discussion-no-date',
  'discussion-window','discussion-local','discussion-adjacent','discussion-national',
  'discussion-reader','discussion-frame','discussion-original','discussion-reader-title',
  'discussion-reader-status','discussion-close']) controls[id] = element();
evaluate('selectedDate = "2026-10-01"; renderDiscussions()');
assert.equal(controls['discussion-content'].hidden, false);
assert.equal(controls['discussion-local'].children.length, 5);
assert.equal(controls['discussion-adjacent'].children.length, 5);
assert.equal(controls['discussion-national'].children.length, 5);
assert.equal(controls['discussion-frame'].getAttribute('src'), null);
for (const id of ['discussion-local','discussion-adjacent','discussion-national']) {
  for (const item of controls[id].children) {
    const link = item.children[0];
    assert.equal(link.target, '_blank');
    assert.equal(link.rel, 'noopener noreferrer');
    assert.match(link.attributes['aria-label'], /2026-10-01 UTC/);
    assert.equal(new URL(link.href).searchParams.get('sdate'), '2026-10-01T00:00Z');
  }
}
// Primary selection loads the reader; modified clicks keep browser new-tab behavior.
const officeLink = controls['discussion-local'].children[0].children[0];
let prevented = false;
officeLink.listeners.click({button:0, ctrlKey:true, preventDefault(){prevented=true;}});
assert.equal(prevented, false);
assert.equal(controls['discussion-frame'].getAttribute('src'), null);
officeLink.listeners.click({button:0, preventDefault(){prevented=true;}});
assert.equal(prevented, true);
assert.equal(controls['discussion-reader'].hidden, false);
assert.equal(controls['discussion-frame'].src, officeLink.href);
assert.equal(controls['discussion-original'].href, officeLink.href);
assert.match(controls['discussion-reader-title'].textContent, /Phoenix.*Oct 1, 2026/);
evaluate('renderDiscussions()');
assert.equal(controls['discussion-frame'].src, officeLink.href);
assert.equal(controls['discussion-local'].children[0].children[0].attributes['aria-current'], 'true');
evaluate('openDiscussion("PMDSPD", "Short-range discussion")');
assert.equal(new URL(controls['discussion-frame'].src).searchParams.get('pil'), 'PMDSPD');
evaluate('selectedDate = "2026-09-30"; renderDiscussions()');
assert.equal(controls['discussion-reader'].hidden, true);
assert.equal(controls['discussion-frame'].getAttribute('src'), null);
assert.match(controls['discussion-window'].textContent, /2026-09-30.*2026-10-01/);
assert.equal(controls['discussion-local'].children.length, 5); // No duplicate links.
evaluate('openDiscussion("AFDPSR", "Phoenix (PSR)"); closeDiscussionReader()');
assert.equal(controls['discussion-reader'].hidden, true);
assert.equal(controls['discussion-frame'].getAttribute('src'), null);
evaluate('selectedDate = ""; renderDiscussions()');
assert.equal(controls['discussion-content'].hidden, true);
assert.equal(controls['discussion-no-date'].hidden, false);
assert.equal(controls['discussion-local'].children.length, 0);
assert.match(code, /renderComparison\(\); renderDiscussions\(\)/);
// Only the existing local climate payload is fetched, never an archive URL.
assert.equal((code.match(/\bfetch\(/g) || []).length, 1);
assert.match(code, /fetch\("daily-data.json"/);
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
]; byDate = new Map(days.map(day => [day.date, day])); render = () => renderDiscussions();`);
assert.equal(evaluate('inCachedDateRange(shift("2026-10-01", -1))'), true);
assert.equal(evaluate('inCachedDateRange(shift("2026-09-30", 1))'), true);
assert.equal(evaluate('inCachedDateRange("2026-09-29")'), false);
assert.equal(evaluate('inCachedDateRange("2026-10-02")'), false);
evaluate('selectDate("2026-09-30")');
assert.equal(controls.year.value, '2026');
assert.equal(controls.season.value, 'all');
assert.equal(evaluate('selectedDate'), '2026-09-30');
assert.equal(new URL(controls['discussion-local'].children[0].children[0].href).searchParams.get('sdate'), '2026-09-30T00:00Z');
evaluate('selectDate("2026-10-01")');
assert.equal(controls.year.value, '2027');
assert.equal(evaluate('selectedDate'), '2026-10-01');
assert.equal(new URL(controls['discussion-national'].children[0].children[0].href).searchParams.get('sdate'), '2026-10-01T00:00Z');
const html = fs.readFileSync('scripts/daily-explorer-assets/index.html', 'utf8');
for (const id of Object.keys(controls).filter(id => id.startsWith('discussion-')))
  assert.ok(html.includes(`id="${id}"`), `Missing discussion panel element ${id}`);
assert.match(html, /id="discussion-frame"[^>]*sandbox=""[^>]*referrerpolicy="no-referrer"/);
assert.doesNotMatch(html, /id="discussion-frame"[^>]*\bsrc=/);
console.log('Daily Explorer UI: embedded reader, archive links, date windows and climate metrics passed.');
