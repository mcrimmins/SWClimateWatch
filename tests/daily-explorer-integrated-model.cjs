const assert=require('node:assert/strict');
const fs=require('node:fs');
const model=require('../scripts/daily-explorer-archive-assets/archive-model.js');
const catalog=model.validate(JSON.parse(fs.readFileSync('data/diagnostics/daily-explorer-archive-integrated/archive-catalog.json','utf8')));
assert.equal(catalog.archive_integration_pilot,true);
for(let d=1;d<=31;d++) {
  const m=model.partition(catalog,`2025-07-${String(d).padStart(2,'0')}`);
  assert.equal(m.full,true);assert.equal(m.viewer,'bundles/2025-07/index.html');
}
assert.equal(model.partition(catalog,'2025-09-30').viewer,'prism/index.html');
assert.equal(model.partition(catalog,'2025-10-01').viewer,'prism/index.html');
assert.equal(model.partition(catalog,'2025-09-30').water_year,2025);
assert.equal(model.partition(catalog,'2025-10-01').water_year,2026);
assert.equal(model.partition(catalog,catalog.latest).full,false);
assert.equal(model.partition(catalog,'2025-08-01'),undefined);
console.log('PASS: all July dates route to the full suite; samples, year boundary and unbuilt dates route explicitly.');
