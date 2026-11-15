# Definitions only: no update entry point, data requests or publication.
for(file in c('config.R','acis-prism.R','process-prism.R','build-prism-climatology.R',
  'prism-percentile-rank.R','prism-workflow.R','map-reference-layers.R','map-product-scales.R',
  'map-southwest.R','build-current-prism-maps.R','build-current-prism-precipitation-maps.R',
  'prism-accumulation-cache.R','prism-rolling-temperature-percentile.R','prism-temperature-threshold-cache.R',
  'prism-first-freeze.R','prism-last-freeze.R','prism-freeze-free-season.R','prism-water-year-cache.R',
  'prism-water-year-temperature.R','prism-dry-spell.R','prism-longest-dry-spell.R','prism-wet-day-count.R',
  'prism-wet-day-intensity.R','prism-very-wet-contribution.R','build-current-prism-water-year-maps.R',
  'prism-water-year-maximum.R','map-product-site.R','refresh-retained-freeze-maps.R','update-enabled-prism-maps.R')) source(file.path('R',file))
