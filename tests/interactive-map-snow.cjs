// Native-grid numerical and selector checks. No external requests.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const api=require('../scripts/interactive-map-assets/pilot.js');
const folder=process.argv[2]||'data/diagnostics/interactive-map-snow-pilot';
const manifest=JSON.parse(fs.readFileSync(path.join(folder,'manifest.json')));
(async()=>{
  let cells=0,low=0,supported=0,missing=0;
  for(const [id,layer] of Object.entries(manifest.layers).filter(([id])=>id.startsWith('snow-'))){
    const bytes=fs.readFileSync(path.join(folder,layer.file));
    assert.equal(crypto.createHash('md5').update(bytes).digest('hex'),layer.md5);
    const buffer=bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength);
    const data=await api.decodePayload(buffer,layer),n=layer.grid.rows*layer.grid.cols;
    assert.ok(Math.abs(layer.grid.dx*3600-30)<1e-8);
    assert.ok(bytes.length<2*1024*1024,'Review transfer budget above 2 MiB per snapshot');
    assert.equal(data.observed.length,n);cells+=n;
    for(const metric of ['swe','departure','percent','change']){
      const s=api.resolveSelection(manifest,{frequency:'current',variable:'snow',measure:'snowpack',metric,period:layer.date});
      assert.equal(s.id,id);assert.equal(s.available,metric!=='change'||layer.change_available);
      assert.deepEqual(api.companions(manifest,s,layer),[]);
    }
    for(let i=0;i<n;i++){
      if(data.percent_status[i]===1){
        supported++;assert.ok(data.years[i]>=18);assert.ok(data.median[i]>=1);
        assert.equal(data.percent[i],100*data.observed[i]/data.median[i]);
      }else {assert.ok(!Number.isFinite(data.percent[i]));if(data.percent_status[i]===2)low++;else missing++;}
      if(Number.isFinite(data.departure[i]))assert.equal(data.departure[i],data.observed[i]-data.median[i]);
      if(!layer.change_available)assert.ok(!Number.isFinite(data.change[i]));
      const k=api.category(api.styleFor({variable:'snow',metric:'percent'}),data,i);
      if(data.percent_status[i]===2)assert.equal(k,8);
      if(data.percent_status[i]===3)assert.equal(k,9);
    }
    const zero=data.observed.findIndex(v=>v===0);
    assert.ok(zero>=0);
    assert.equal(api.pointStats({variable:'snow',metric:'swe'},data,zero).rows[0][1],'0.00 in.');
    assert.equal(api.cellAt(layer.grid,layer.grid.north,layer.grid.west),0);
    assert.equal(api.cellAt(layer.grid,layer.grid.south,layer.grid.west),-1);
    await assert.rejects(()=>api.decodePayload(buffer.slice(0,-1),layer),/length/);
  }
  assert.ok(low>0&&supported>0&&missing>0);
  const sweStyle=api.styleFor({variable:'snow',metric:'swe'});
  assert.equal(sweStyle.colors[api.category(sweStyle,{observed:[0]},0)],'transparent');
  assert.notEqual(sweStyle.colors[api.category(sweStyle,{observed:[.00001]},0)],'transparent');
  assert.equal(sweStyle.labels[api.category(sweStyle,{observed:[NaN]},0)],'Unavailable');
  for(const metric of ['departure','percent','change']){
    const style=api.styleFor({variable:'snow',metric});
    const data={departure:[0],percent:[0],change:[0],departure_status:[1],percent_status:[1]};
    assert.notEqual(style.colors[api.category(style,data,0)],'transparent');
  }
  for(const [v,expected] of [[0,0],[50,1],[75,2],[90,3],[110,4],[125,5],[150,6],[200,7]])
    assert.equal(api.category(api.styleFor({variable:'snow',metric:'percent'}),{percent:[v],percent_status:[1]},0),expected);
  assert.equal(api.category(api.styleFor({variable:'snow',metric:'change'}),{change:[-.25]},0),4);
  assert.equal(api.category(api.styleFor({variable:'snow',metric:'change'}),{change:[4]},0),8);
  // Switching to PRISM modes resolves a valid variable rather than leaving Snow active.
  for(const frequency of ['daily','monthly'])assert.notEqual(api.resolveSelection(manifest,{frequency,variable:'snow'}).variable,'snow');
  console.log(`PASS: ${cells.toLocaleString()} native snow cells; exact derived values, masks, gzip integrity, missing endpoints and linked selectors.`);
})().catch(e=>{console.error(e);process.exitCode=1;});
