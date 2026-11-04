const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const header = fs.readFileSync('site/_includes/google-analytics.html', 'utf8').replace(/\r\n/g,'\n');
const bootstrap = header.match(/<script>([\s\S]*?)<\/script>/)[1];
const analytics = fs.readFileSync('site/assets/site-analytics.js', 'utf8');
function environment(hostname, pathname, embedded=false) {
  const scripts=[];
  const window={location:{hostname, pathname, origin:`https://${hostname}`, search:'?private=value'}};
  window.self=window; window.top=embedded?{}:window;
  return {scripts, window, context:vm.createContext({window, document:{
    createElement:()=>({}), head:{appendChild:script=>scripts.push(script)}}})};
}
for (const [host,path,embedded] of [
  ['127.0.0.1','/',false], ['localhost','/climate/watch/',false],
  ['cales.arizona.edu','/climate/watch-staging/',false],
  ['cales.arizona.edu','/climate/watch-other/',false],
  ['cales.arizona.edu','/droughtandgrazing/',false],
  ['example.com','/climate/watch/',false],
  ['cales.arizona.edu','/climate/watch/stations/index.html',true]
]) {
  const e=environment(host,path,embedded);
  vm.runInContext(bootstrap,e.context); vm.runInContext(analytics,e.context);
  assert.equal(e.scripts.length,0,`${host}${path} must not load analytics`);
  assert.equal(e.window.dataLayer,undefined);
}
for (const path of ['/climate/watch/','/climate/watch/pages/archive/wy2025.html',
  '/climate/watch/daily-explorer/index.html','/climate/watch/stations/index.html']) {
  const e=environment('cales.arizona.edu',path);
  vm.runInContext(bootstrap,e.context); vm.runInContext(bootstrap,e.context);
  assert.equal(e.scripts.length,1); assert.equal(e.scripts[0].src,'/climate/watch/assets/site-analytics.js');
  vm.runInContext(analytics,e.context); vm.runInContext(analytics,e.context);
  assert.equal(e.scripts.length,2); assert.match(e.scripts[1].src,/id=G-XS7RFBPW01$/);
  const configuration=e.window.dataLayer[1];
  assert.equal(configuration[0],'config'); assert.equal(configuration[1],'G-XS7RFBPW01');
  assert.equal(configuration[2].page_location,`https://cales.arizona.edu${path}`);
  assert.equal(e.window.dataLayer.length,2,'Only one page-view configuration');
}
for (const path of ['scripts/station-explorer-assets/index.html','scripts/daily-explorer-assets/index.html'])
  assert.ok(fs.readFileSync(path,'utf8').replace(/\r\n/g,'\n').includes(header),`${path} must use the shared bootstrap verbatim`);
assert.match(fs.readFileSync('site/_quarto.yml','utf8'),/include-in-header: _includes\/google-analytics.html/);
console.log('Analytics passed: production scope, staging/local exclusion, embedded deduplication and query removal.');
