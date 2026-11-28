// Exercise the real navigation adapter in full-screen and nested site layouts.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync(require.resolve('../scripts/streamflow-assets/explorer-streamflow.js'),'utf8');
function check({embedded=false,reduced=false,header=0}={}){
  const buttons=[],scrolls=[],opened=[];let nav;
  const root={scrollY:500,frameElement:null,document:{getElementById:()=>header?{getBoundingClientRect:()=>({top:0,bottom:header})}:null},
    getComputedStyle:()=>({position:'fixed'}),matchMedia:()=>({matches:reduced}),scrollTo:m=>scrolls.push(m)};
  const shell=embedded?{frameElement:{clientTop:2,getBoundingClientRect:()=>({top:200}),ownerDocument:{defaultView:root}},
    addEventListener(){},scrollTo(){throw Error('Must scroll the site page, not the embedded shell');}}:root;
  shell.addEventListener=()=>{};
  const month={frameElement:{clientTop:1,getBoundingClientRect:()=>({top:300}),ownerDocument:{defaultView:shell}}};
  const heading={ownerDocument:{defaultView:month},getBoundingClientRect:()=>({top:1800}),setAttribute(){},focus:o=>assert.equal(o.preventScroll,true)};
  const target={hidden:false,tagName:'DETAILS',parentElement:null,open:false,matches:()=>true,querySelector:()=>heading};
  const frame={src:'https://example.test/current/index.html?archiveToken=1',contentDocument:{querySelector:()=>target},contentWindow:{postMessage(){}},
    addEventListener:(type,fn)=>{if(type==='load')opened.push(fn);}};
  const document={getElementById:id=>id==='connected-viewer'?frame:null,
    querySelector:s=>s==='.archive-controls'?{after:n=>{nav=n;}}:{src:'https://example.test/connected/explorer-streamflow.swc-123.js'},
    createElement:tag=>{const handlers={};const el={setAttribute(){},append(){},getBoundingClientRect:()=>({height:60}),
      addEventListener:(type,fn)=>{handlers[type]=fn;},click:()=>handlers.click()};if(tag==='button')buttons.push(el);return el;}};
  class MutationObserver{observe(){}}
  vm.runInNewContext(source,{document,window:shell,URL,location:{origin:'https://example.test',href:'https://example.test/connected/'},MutationObserver,requestAnimationFrame:fn=>fn()});
  assert.ok(nav);opened.forEach(fn=>fn());assert.equal(buttons.length,8);
  for(const button of buttons){assert.equal(button.disabled,false);target.open=false;button.click();assert.equal(target.open,true);}
  const expected=500+1800+300+1+(embedded?202:0)-76-header;
  assert.equal(scrolls.length,8);
  for(const scroll of scrolls){assert.equal(scroll.top,expected);assert.equal(scroll.behavior,reduced?'instant':'smooth');}
}
check();check({embedded:true});check({embedded:true,reduced:true,header:64});
console.log('PASS: all eight jumps scroll the outer site page or full-screen viewer, open sections, focus headings and respect reduced motion.');
