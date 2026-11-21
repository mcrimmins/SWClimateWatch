const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
class Element {
  constructor(tag){this.tag=tag;this.children=[];this.attributes={};this.events={};this.dataset={};this.parent=null;this.hidden=false;
    if(tag==='iframe')this.contentWindow={messages:[],postMessage(x){this.messages.push(x);}};}
  setAttribute(k,v){this.attributes[k]=String(v);}getAttribute(k){return this.attributes[k];}
  addEventListener(k,v){this.events[k]=v;}
  append(...items){for(const x of items){x.parent=this;this.children.push(x);}}
  replaceChildren(...items){this.children=[];this.append(...items);}
  contains(x){return this===x||this.children.some(y=>y.contains(x));}
  remove(){if(this.parent)this.parent.children=this.parent.children.filter(x=>x!==this);this.parent=null;}
  focus(){this.focused=true;}
}
const subtitle={textContent:'Current 30-day dates'},listeners=new Set();
const document={createElement:tag=>new Element(tag),getElementById:id=>{assert.equal(id,'detail-subtitle');return subtitle;}};
const window={addEventListener:(name,fn)=>{assert.equal(name,'message');listeners.add(fn);},removeEventListener:(_,fn)=>listeners.delete(fn)};
vm.runInNewContext(fs.readFileSync('scripts/station-custom-dates-assets/station-history-tabs.js','utf8'),{window,document,location:{origin:'http://localhost'}});
const api=window.SWCStationHistoryTabs,root=new Element('div'),station={uid:1,sid:'ID1',name:'Station one'};
api.render(root,'CURRENT PLOTS',station);
assert.equal(root.children[1].innerHTML,'CURRENT PLOTS');assert.equal(root.children[2].hidden,true);
assert.equal(root.children[2].children.filter(x=>x.tag==='iframe').length,0,'default current tab must not load history');
const tabs=root.children[0].children;tabs[1].events.click();
let frame=root.children[2].children.find(x=>x.tag==='iframe');assert.match(frame.src,/uid=1$/);
assert.equal(root.children[1].hidden,true);assert.equal(tabs[1].getAttribute('aria-selected'),'true');
const selection={type:'swc-station-history-selection',uid:'1',start:'1900-01-01',end:'1900-01-07',cutoff:'2026-11-03'};
for(const fn of listeners)fn({origin:'http://wrong',source:frame.contentWindow,data:selection});assert.doesNotMatch(subtitle.textContent,/1900/);
for(const fn of listeners)fn({origin:'http://localhost',source:frame.contentWindow,data:selection});assert.match(subtitle.textContent,/1900/);
assert.equal(api.prepare(root,'1'),true);subtitle.textContent='New current 7-day dates';api.render(root,'NEW CURRENT PLOTS',station);
assert.equal(root.children[2].children.find(x=>x.tag==='iframe'),frame,'preset changes must preserve the history frame');
assert.match(subtitle.textContent,/1900/);root.children[0].children[0].events.click();
assert.equal(subtitle.textContent,'New current 7-day dates');assert.equal(frame.contentWindow.messages.at(-1).type,'swc-station-history-pause');
root.children[0].children[1].events.click();assert.equal(api.prepare(root,'2'),false);assert.equal(frame.parent,null);
subtitle.textContent='Station two current dates';api.render(root,'TWO CURRENT PLOTS',{uid:2,sid:'ID2',name:'Station two'});
frame=root.children[2].children.find(x=>x.tag==='iframe');assert.match(frame.src,/uid=2$/);assert.doesNotMatch(subtitle.textContent,/1900/);
assert.equal(listeners.size,1);api.close(root);assert.equal(listeners.size,0);assert.equal(root.children.length,0);
subtitle.textContent='Fresh current';api.render(root,'FRESH',station);assert.equal(root.children[2].hidden,true);
root.children[0].children[0].events.keydown({key:'ArrowRight',preventDefault(){}});assert.equal(root.children[2].hidden,false);
root.children[0].children[1].events.keydown({key:'Home',preventDefault(){}});assert.equal(root.children[1].hidden,false);
console.log('PASS: lazy history, unchanged current content, preset independence, selected-station switching, message guards, keyboard tabs and close cleanup.');
