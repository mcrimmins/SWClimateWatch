// Exercise the exact browser worker and CSV serializer against real annual files.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=process.argv[2],out=process.argv[3];if(!root||!out)throw Error('Supply history and diagnostic output folders.');
fs.mkdirSync(out,{recursive:true});
const catalog=JSON.parse(fs.readFileSync(path.join(root,'catalog.json'),'utf8'));
const station=name=>{const s=catalog.stations.find(x=>x.name===name);if(!s)throw Error('Missing fixture station: '+name);return s;};
const cases=[['short-missing-temperature','ANVIL RANCH',false],['short-trace','TUCSON INTERNATIONAL AIRPORT',false],['long-full-record','Yuma Area',true]];
const reports=[];
for(const [label,name,full] of cases){
  const s=station(name),index=JSON.parse(fs.readFileSync(path.join(root,s.index),'utf8'));
  const end=index.last,start=full?index.first:new Date(Date.parse(end+'T00:00:00Z')-29*86400000).toISOString().slice(0,10);
  const chunks=index.years.filter(y=>y.end>=start&&y.start<=end).map(y=>JSON.parse(fs.readFileSync(path.join(root,y.file),'utf8')));
  let response;
  const context={performance,self:{postMessage:x=>{response=x;}}};
  vm.createContext(context);context.importScripts=file=>vm.runInContext(fs.readFileSync(path.join(root,file),'utf8'),context);
  vm.runInContext(fs.readFileSync(path.join(root,'worker.js'),'utf8'),context);
  context.self.onmessage({data:{id:1,type:'compute',chunks:chunks.map(c=>context.StationCustomModel.decode(c,s.uid)),start,end,station:s}});
  assert.ok(!response.error,response.error);const summary=response.summary;
  const before=performance.now();context.self.onmessage({data:{id:2,type:'csv'}});
  assert.ok(!response.error,response.error);assert.ok(response.csv.startsWith('\uFEFF'));assert.ok(response.csv.endsWith('\r\n'));
  const filename=`station-${s.uid}-${start}-to-${end}.csv`;fs.writeFileSync(path.join(out,filename),response.csv,'utf8');
  reports.push({label,uid:s.uid,start,end,rows:summary.days,filename,bytes:Buffer.byteLength(response.csv),export_ms:Math.round((performance.now()-before)*10)/10});
}
fs.writeFileSync(path.join(out,'cases.json'),JSON.stringify(reports,null,2));
console.log('PASS: browser worker CSV exported for short missing/trace periods and the longest full record.');
