(() => {
  const root = document.querySelector('.precipitation-period-preview');
  if (!root) return;
  const selector = root.querySelector('#precipitation-period');
  const maps = [...root.querySelectorAll('[data-period]')];
  const allowed = maps.map(map => map.dataset.period);
  const requested = new URLSearchParams(window.location.search).get('period');
  selector.value = allowed.includes(requested) ? requested : allowed[0];
  function render(updateUrl = true) {
    maps.forEach(map => { map.hidden = map.dataset.period !== selector.value; });
    if (updateUrl) {
      const url = new URL(window.location.href);
      url.searchParams.set('period', selector.value);
      window.history.replaceState(null, '', url);
    }
  }
  selector.addEventListener('change', () => render());
  root.classList.add('precipitation-enhanced');
  render(false);
})();
