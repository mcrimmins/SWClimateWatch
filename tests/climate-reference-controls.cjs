const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {layoutState}=require('../scripts/climate-reference-assets/climate-reference.js');
const periods=['annual','winter','spring','summer','fall'];
const precip=['precipitation','precipitation_share','wet_days','wet_amount','heavy_days'];
const temp=['temperature','freeze_days','hot_days'];
const catalog=periods.flatMap(period=>[...precip,...temp].filter(metric=>!(period==='annual'&&metric==='precipitation_share')).map(metric=>({period,metric,group:precip.includes(metric)?'precipitation':'temperature'})));
assert.equal(catalog.length,39);
for(const group of ['precipitation','temperature']) for(const period of periods) for(const view of ['single','all']) for(const share of ['total','share']) for(const metric of (group==='precipitation'?precip.filter(x=>x!=='precipitation_share'):temp)) {
  const state=layoutState({group,period,view,share,metric},catalog);
  assert.equal(state.visible.length,view==='all'?(group==='precipitation'?4:3):1);
  assert(state.visible.every(x=>x.period===period&&x.group===group));
  assert.equal(state.shareValue,share==='share'&&period!=='annual'?'share':'total');
  if(view==='single') assert.equal(state.visible[0].metric,group==='precipitation'&&metric==='precipitation'&&period!=='annual'&&share==='share'?'precipitation_share':metric);
}
for(const metric of [...precip,...temp]) for(const period of periods) {
  const state=layoutState({group:'comparison',metric,period,share:'share'},catalog);
  assert.deepEqual(state.visible.map(x=>x.period),periods.slice(1));
  assert(state.visible.every(x=>x.metric===metric));assert(state.periodDisabled);
}
// Exercise the actual DOM event wiring as well as the selection model.
let active='precipitation'; const events={};
function select(value,values){return {value,disabled:false,options:values.map(x=>({value:x,text:x})),get selectedIndex(){return this.options.findIndex(x=>x.value===this.value)},addEventListener(name,fn){this[name]=fn}};}
const elements={
 '#climate-period':select('annual',periods), '#climate-period-hint':{},
 '#climate-precip-mode':select('total',['total','share']), '#climate-share-control':{},'#climate-share-hint':{},
 '#climate-comparison-metric':select('precipitation',[...precip,...temp]),
 '#climate-comparison-maps':{replaceChildren(...nodes){this.children=nodes}},'#climate-comparison-status':{}
};
for(const group of ['precipitation','temperature']) {
 elements['#climate-'+group+'-metric']=select(group==='precipitation'?'precipitation':'temperature',group==='precipitation'?precip:temp);
 elements['#climate-'+group+'-view']=select('single',['single','all']);
 elements['#climate-'+group+'-status']={};
 elements['#climate-'+group+'-maps']={classList:{toggle(){}}};
}
function card(row){return {dataset:{referenceCard:row.group,period:row.period,metric:row.metric},hidden:true,cloneNode(){return card(row)},removeAttribute(){},querySelector(){return {removeAttribute(){}}},prepend(heading){this.heading=heading}};}
const cards=catalog.map(card);
const selects=Object.values(elements).filter(x=>x.options);
const document={readyState:'complete',querySelector(q){if(q.includes('[role="tabpanel"].active')) return {dataset:{climateGroup:active}}; return elements[q]},querySelectorAll(q){return q.startsWith('.climate-map-card')?cards:selects},addEventListener(n,fn){events[n]=fn},createElement(){return {}}};
vm.runInNewContext(fs.readFileSync('scripts/climate-reference-assets/climate-reference.js','utf8'),{document});
function change(id,value){elements[id].value=value;elements[id].change();}
function visible(group){return cards.filter(x=>x.dataset.referenceCard===group&&!x.hidden).map(x=>x.dataset.period+':'+x.dataset.metric);}
assert.deepEqual(visible('precipitation'),['annual:precipitation']);
change('#climate-period','summer');change('#climate-precip-mode','share');
assert.deepEqual(visible('precipitation'),['summer:precipitation_share']);
change('#climate-period','annual');assert.equal(elements['#climate-precip-mode'].value,'total');assert(elements['#climate-precip-mode'].disabled);
change('#climate-period','winter');assert.equal(elements['#climate-precip-mode'].value,'share');
change('#climate-precipitation-metric','wet_days');assert(elements['#climate-share-control'].hidden);
change('#climate-precipitation-view','all');assert.equal(visible('precipitation').length,4);assert(elements['#climate-precipitation-metric'].disabled);
active='temperature';events['shown.bs.tab']();assert.deepEqual(visible('temperature'),['winter:temperature']);
change('#climate-temperature-metric','freeze_days');assert.deepEqual(visible('temperature'),['winter:freeze_days']);
active='comparison';events['shown.bs.tab']();assert(elements['#climate-period'].disabled);
change('#climate-comparison-metric','precipitation_share');
assert.equal(elements['#climate-comparison-maps'].children.length,4);assert(elements['#climate-comparison-maps'].children.every(x=>x.dataset.metric==='precipitation_share'&&!x.hidden));
active='precipitation';events['shown.bs.tab']();assert.equal(elements['#climate-period'].value,'winter');assert(!elements['#climate-period'].disabled);assert.equal(visible('precipitation').length,4);
console.log('PASS: exhaustive topic/period/metric/view/share combinations and DOM change/tab wiring; restored selections and four-season comparisons.');
