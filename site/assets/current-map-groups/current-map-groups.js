(() => {
  const root = document.querySelector('.current-group-preview');
  if (!root) return;
  const tabs = [...root.querySelectorAll('[role="tab"]')];
  const maps = [...root.querySelectorAll('.group-map')];
  const variant = root.querySelector('#group-variant');
  const variantControl = root.querySelector('.group-variant-control');
  const layout = root.querySelector('#group-layout');
  const tablist = root.querySelector('[role="tablist"]');
  const panel = root.querySelector('#group-maps');
  const params = new URLSearchParams(window.location.search);
  let active = tabs.some(t => t.dataset.tab === params.get('tab')) ? params.get('tab') : tabs[0].dataset.tab;
  let selected = params.get('display');
  if (layout) layout.value = params.get('view') === 'all' ? 'all' : 'single';
  function render(updateUrl = true) {
    const choices = maps.filter(map => map.dataset.tab === active);
    if (!choices.some(map => map.dataset.variant === selected)) selected = choices[0].dataset.variant;
    variant.replaceChildren(...choices.map(map => {
      const option = document.createElement('option');
      option.value = map.dataset.variant; option.textContent = map.dataset.option;
      return option;
    }));
    variant.value = selected;
    const all = layout && layout.value === 'all';
    root.classList.toggle('group-all-maps', Boolean(all));
    tablist.hidden = Boolean(all) || tabs.length < 2;
    variantControl.hidden = Boolean(all) || choices.length < 2;
    tabs.forEach(tab => {
      const current = tab.dataset.tab === active;
      tab.setAttribute('aria-selected', String(current)); tab.tabIndex = current ? 0 : -1;
    });
    panel.setAttribute('role', all ? 'region' : 'tabpanel');
    if (all) {
      panel.removeAttribute('aria-labelledby'); panel.setAttribute('aria-label', 'All snow maps');
    } else {
      panel.removeAttribute('aria-label'); panel.setAttribute('aria-labelledby', `group-tab-${active}`);
    }
    maps.forEach(map => { map.hidden = !all && (map.dataset.tab !== active || map.dataset.variant !== selected); });
    if (updateUrl) {
      const url = new URL(window.location.href);
      url.searchParams.set('tab', active); url.searchParams.set('display', selected);
      if (layout) url.searchParams.set('view', layout.value);
      window.history.replaceState(null, '', url);
    }
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => { active = tab.dataset.tab; render(); });
    tab.addEventListener('keydown', event => {
      const next = event.key === 'ArrowRight' ? (index + 1) % tabs.length : event.key === 'ArrowLeft' ?
        (index + tabs.length - 1) % tabs.length : event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : null;
      if (next === null) return;
      event.preventDefault(); tabs[next].click(); tabs[next].focus();
    });
  });
  variant.addEventListener('change', () => { selected = variant.value; render(); });
  if (layout) layout.addEventListener('change', () => render());
  root.classList.add('group-enhanced');
  render(false);
})();
