# Read monthly cache only; output is isolated from the operational site.
source("scripts/load-prism-monthly.R")
source("R/map-reference-layers.R")
source("R/map-product-scales.R")
source("R/map-southwest.R")
source("R/regional-climate-reference.R")
regional_reference_pilot <- build_regional_climate_reference_pilot()
print(regional_reference_pilot$summary, row.names = FALSE)
print(regional_reference_pilot$samples, row.names = FALSE)
