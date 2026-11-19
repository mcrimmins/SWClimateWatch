(function () {
  function selection(year, period, metric) {
    return {year: String(year), period: metric === 'spi12' ? 'water-year' : period, metric: metric};
  }
  function matches(card, selected) {
    return (selected.year === 'all' || card.year === selected.year) && card.period === selected.period &&
      (selected.metric === 'all' || card.metric === selected.metric);
  }
  if (typeof module !== 'undefined') module.exports = {selection, matches};
  if (typeof document === 'undefined') return;
  var year = document.getElementById('year'), period = document.getElementById('period'), metric = document.getElementById('metric');
  var previousPeriod = period.value;
  function update() {
    if (metric.value === 'spi12') {
      if (!period.disabled) previousPeriod = period.value;
      period.value = 'water-year'; period.disabled = true;
    } else if (period.disabled) {
      period.disabled = false; period.value = previousPeriod;
    }
    var selected = selection(year.value, period.value, metric.value), count = 0;
    document.querySelectorAll('article[data-year]').forEach(function (card) {
      card.hidden = !matches(card.dataset, selected);
      if (!card.hidden) count++;
    });
    document.getElementById('selection-status').textContent = count + ' maps shown. ' +
      (metric.value === 'spi12' ? 'September SPI-12 covers the complete October–September water year.' :
        period.options[period.selectedIndex].text + ' · ' + metric.options[metric.selectedIndex].text + '.');
  }
  [year, period, metric].forEach(function (control) { control.addEventListener('change', update); });
  update();
}());
