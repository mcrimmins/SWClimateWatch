const assert = require('node:assert/strict');
const model = require('../scripts/daily-explorer-archive-assets/archive-model.js');
const cat = {schema_version:1,archive_pilot:true,latest:'2025-10-02',months:[
  {month:'2025-09',water_year:2025,path:'archive/WY2025/months/2025-09.json',dates:['2025-09-30']},
  {month:'2025-10',water_year:2026,path:'current/months/2025-10.json',dates:['2025-10-01','2025-10-02']}
]};
assert.equal(model.validate(cat),cat);
assert.equal(model.year('2025-09-30'),2025);assert.equal(model.year('2025-10-01'),2026);
assert.equal(model.needed(cat,'2025-10-01').length,2);
assert.throws(() => model.needed(cat,'2025-09-29'),/not built/);
assert.throws(() => model.validate({...cat,latest:'2024-01-01'}));
assert.throws(() => model.validate({...cat,months:[{...cat.months[0],path:'../escape.json'}]}));
const day = date => ({date,water_year:model.year(date),images:Object.fromEntries(Array.from({length:7},(_,i) => [String(i),`archive/WY2025/maps/${date}-${i}.png`]))});
assert.deepEqual(model.records([{schema_version:1,days:[day('2025-10-01')]},{schema_version:1,days:[day('2025-09-30')]}]).map(d => d.date),['2025-09-30','2025-10-01']);
assert.throws(() => model.records([{schema_version:1,days:[day('2025-09-30'),day('2025-09-30')]}]),/Duplicate/);
assert.throws(() => model.records([{schema_version:1,days:[{...day('2025-09-30'),images:{}}]}]),/Incomplete/);
console.log('PASS: archive catalog, safe paths, exact dates, water-year boundary support, deduplication and seven-map guards.');
