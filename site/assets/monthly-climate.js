(() => {
  const root = document.querySelector('.monthly-climate');
  if (!root) return;
  const tabs = [...root.querySelectorAll('[role="tab"]')];
  const selector = root.querySelector('#monthly-duration');
  let active = 'temperature';
  function render() {
    tabs.forEach(tab => {
      const selected = tab.id === `monthly-tab-${active}`;
      tab.setAttribute('aria-selected', String(selected));
      tab.tabIndex = selected ? 0 : -1;
      document.getElementById(tab.getAttribute('aria-controls')).hidden = !selected;
    });
    root.querySelectorAll('.monthly-map').forEach(map => {
      map.hidden = map.dataset.duration !== selector.value;
    });
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => { active = tab.id.replace('monthly-tab-', ''); render(); });
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
  selector.addEventListener('change', render);
  root.classList.add('monthly-enhanced');
  render();
})();
