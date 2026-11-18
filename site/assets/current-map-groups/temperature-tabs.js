(() => {
  const root = document.querySelector('.temperature-tabs-preview');
  if (!root) return;
  const tabs = [...root.querySelectorAll('[role="tab"]')];
  const period = root.querySelector('#temperature-period');
  const variables = ['maxt', 'tmean', 'mint'];
  const periods = period ? ['daily', '30day'] : ['daily'];
  const query = new URLSearchParams(window.location.search);
  let active = variables.includes(query.get('variable')) ? query.get('variable') : 'maxt';
  if (period) period.value = periods.includes(query.get('period')) ? query.get('period') : 'daily';
  function render(updateUrl = true) {
    const selectedPeriod = period ? period.value : 'daily';
    tabs.forEach(tab => {
      const selected = tab.id === `temperature-tab-${active}`;
      tab.setAttribute('aria-selected', String(selected));
      tab.tabIndex = selected ? 0 : -1;
      document.getElementById(tab.getAttribute('aria-controls')).hidden = !selected;
    });
    root.querySelectorAll('.temperature-map').forEach(map => {
      map.hidden = map.dataset.period !== selectedPeriod;
    });
    if (updateUrl) {
      const url = new URL(window.location.href);
      url.searchParams.set('variable', active);
      if (period) url.searchParams.set('period', selectedPeriod);
      window.history.replaceState(null, '', url);
    }
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => { active = variables[index]; render(); });
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = tabs.length - 1;
      if (next === undefined) return;
      event.preventDefault(); tabs[next].click(); tabs[next].focus();
    });
  });
  if (period) period.addEventListener('change', () => render());
  root.classList.add('temperature-enhanced');
  render(false);
})();
