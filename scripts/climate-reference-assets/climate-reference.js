(function () {
  'use strict';
  const periods = ['winter','spring','summer','fall'];
  const labels = {annual:'Annual (Jan-Dec)',winter:'Winter (Jan-Mar)',spring:'Spring (Apr-Jun)',summer:'Summer (Jul-Sep)',fall:'Fall (Oct-Dec)'};
  function layoutState(state, catalog) {
    const period = Object.hasOwn(labels,state.period) ? state.period : 'annual';
    const group = ['precipitation','temperature','comparison'].includes(state.group) ? state.group : 'precipitation';
    const view = state.view === 'all' ? 'all' : 'single';
    const share = state.share === 'share' && period !== 'annual';
    const metric = state.metric || (group === 'temperature' ? 'temperature' : 'precipitation');
    const metricMatch = row => row.metric === (metric === 'precipitation' && share ? 'precipitation_share' : metric);
    const visible = group === 'comparison' ? catalog.filter(row => periods.includes(row.period) && row.metric === metric) :
      catalog.filter(row => row.group === group && row.period === period && (view === 'single' ? metricMatch(row) :
        row.metric !== (share ? 'precipitation' : 'precipitation_share')));
    return {group,period,view,visible,periodDisabled:group === 'comparison',shareDisabled:period === 'annual',
      shareValue:share?'share':'total',shareShown:group === 'precipitation' && (view === 'all' || metric === 'precipitation')};
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = {layoutState};
  if (typeof document === 'undefined') return;
  function init() {
    const periodSelect = document.querySelector('#climate-period');
    if (!periodSelect) return;
    const sourceCards = Array.from(document.querySelectorAll('.climate-map-card[data-reference-card]'));
    const catalog = sourceCards.map(card=>({period:card.dataset.period,metric:card.dataset.metric,group:card.dataset.referenceCard,card}));
    const shareSelect = document.querySelector('#climate-precip-mode');
    let desiredShare = 'total';
    let comparisonKey = '';
    function render() {
      const panel = document.querySelector('.climate-reference-tabs [role="tabpanel"].active [data-climate-group]');
      const group = panel ? panel.dataset.climateGroup : 'precipitation';
      periodSelect.disabled = group === 'comparison';
      document.querySelector('#climate-period-hint').textContent = group === 'comparison' ? 'Comparing all four seasons; your selected period is retained.' : '';
      for (const topic of ['precipitation','temperature']) {
        const metricSelect = document.querySelector('#climate-'+topic+'-metric');
        const viewSelect = document.querySelector('#climate-'+topic+'-view');
        const state = layoutState({group:topic,period:periodSelect.value,metric:metricSelect.value,view:viewSelect.value,share:desiredShare},catalog);
        const visible = new Set(state.visible.map(row=>row.card));
        catalog.filter(row=>row.group === topic).forEach(row=>{ row.card.hidden = !visible.has(row.card); });
        const grid = document.querySelector('#climate-'+topic+'-maps');
        grid.classList.toggle('climate-all-metrics',state.view === 'all');
        metricSelect.disabled = state.view === 'all';
        document.querySelector('#climate-'+topic+'-status').textContent = labels[state.period]+' · '+(state.view === 'all' ? 'All metrics' : metricSelect.options[metricSelect.selectedIndex].text)+(state.shareShown && state.shareValue === 'share' ? ' · Share of annual' : '');
        if (topic === 'precipitation' && shareSelect) {
          shareSelect.disabled = state.shareDisabled;
          shareSelect.value = state.shareValue;
          document.querySelector('#climate-share-control').hidden = !state.shareShown;
          document.querySelector('#climate-share-hint').hidden = !state.shareShown;
          document.querySelector('#climate-share-hint').textContent = state.shareDisabled ? 'Share of annual is available for seasons.' : '';
        }
      }
      const metricSelect = document.querySelector('#climate-comparison-metric');
      const metric = metricSelect.value;
      if (metric !== comparisonKey) {
        const grid = document.querySelector('#climate-comparison-maps');
        const nodes = periods.map(period=>{
          const row = catalog.find(row=>row.period === period && row.metric === metric);
          if (!row) {const notice=document.createElement('p');notice.textContent=labels[period]+': map unavailable.';return notice;}
          const card=row.card.cloneNode(true); card.hidden=false;
          card.removeAttribute('data-reference-card');
          card.querySelector('img').removeAttribute('data-reference-map');
          const heading=document.createElement('h3');heading.className='climate-comparison-season';heading.textContent=labels[period];card.prepend(heading);
          return card;
        });
        grid.replaceChildren(...nodes);
        comparisonKey=metric;
      }
      document.querySelector('#climate-comparison-status').textContent = metricSelect.options[metricSelect.selectedIndex].text+' · Four seasons · Shared scale';
    }
    document.querySelectorAll('#climate-shared-controls select, [data-climate-group] select').forEach(select=>{
      select.addEventListener('change',()=>{
        if(select === shareSelect && !shareSelect.disabled) desiredShare=shareSelect.value;
        render();
      });
    });
    document.addEventListener('shown.bs.tab',render);
    render();
  }
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded',init);else init();
}());
