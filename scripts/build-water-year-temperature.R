# Cached daily PRISM only: three maps, no downloads, render or publication.
for (module in c("config.R","acis-prism.R","process-prism.R",
    "build-prism-climatology.R","prism-percentile-rank.R","prism-workflow.R",
    "map-reference-layers.R","map-product-scales.R","map-southwest.R",
    "build-current-prism-maps.R","build-current-prism-precipitation-maps.R",
    "prism-accumulation-cache.R","prism-water-year-cache.R","prism-water-year-temperature.R","map-product-site.R"))
  source(file.path("R",module))
water_year_temperature <- build_current_prism_water_year_temperature_maps()
print(water_year_temperature,row.names=FALSE)
message("Water-year temperature maps ready locally. No downloads or S3 publication.")
