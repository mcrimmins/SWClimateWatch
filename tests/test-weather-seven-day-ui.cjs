const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const path='data/diagnostics/weather-seven-day-pilot/index.html';
if(!fs.existsSync(path)){console.log('SKIP: build the local seven-day pilot first.');process.exit(0);}
const html=fs.readFileSync(path,'utf8'),script=html.match(/<script>([\s\S]*?)<\/script>/)[1];
const buttons=[{dataset:{image:'height500-7day.png'},textContent:'500-mb heights'},
  {dataset:{image:'pwat-7day.png'},textContent:'Precipitable water'}];
buttons.forEach(b=>{b.attributes={};b.setAttribute=(name,v)=>b.attributes[name]=v;});
const map={},link={};
vm.runInNewContext(script,{document:{querySelectorAll:()=>buttons,getElementById:id=>id==='map'?map:link}});
buttons[1].onclick();assert(map.src.endsWith('/pwat-7day.png'));assert.equal(link.href,map.src);
assert.equal(buttons[1].attributes['aria-selected'],'true');assert.equal(buttons[0].attributes['aria-selected'],'false');
assert(map.alt.includes('Precipitable water'));
buttons[0].onclick();assert(map.src.endsWith('/height500-7day.png'));assert.equal(link.href,map.src);
assert.equal(buttons[0].attributes['aria-selected'],'true');
assert(html.includes('Seven complete days'));assert(html.includes('2026'));
console.log('PASS: pilot tabs switch the image, accessible label, selection state and full-resolution link together.');
