const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const root='data/diagnostics/weather-period-means-pilot/';
const html=fs.readFileSync(root+'index.html','utf8');
const script=html.match(/<script>([\s\S]*?)<\/script>/)[1];
const elements=Object.fromEntries(['period','map','full','range','note'].map(id=>[id,{value:'7',addEventListener(type,fn){this[type]=fn;}}]));
const fields=['height500','jet250','pwat'];
const buttons=fields.map(field=>({dataset:{field},attributes:{},setAttribute(k,v){this.attributes[k]=v;},addEventListener(type,fn){this[type]=fn;}}));
vm.runInNewContext(script,{document:{getElementById:id=>elements[id],querySelectorAll:()=>buttons}});
for(const days of ['1','7','30']){
  elements.period.value=days;elements.period.change();
  for(let i=0;i<3;i++){
    buttons[i].click();const name=fields[i]==='pwat'&&html.includes('const moistureOverlays=true')?'pwat-overlay':fields[i];const expected=`${days}day/${name}-${days}day.png`;
    assert.equal(elements.map.src,expected);assert.equal(elements.full.href,expected);
    assert(fs.existsSync(root+expected));assert(elements.range.textContent.includes(`${days} complete`));
    assert.equal(buttons[i].attributes['aria-selected'],'true');
    assert.equal(buttons.filter(b=>b.attributes['aria-selected']==='true').length,1);
  }
}
assert(elements.note.textContent.includes('water vapor'));
buttons[1].click();assert(elements.note.textContent.includes('not mean scalar wind speed'));
console.log('PASS: all nine variable/period combinations update maps, links, dates, notes and tab selection together.');
