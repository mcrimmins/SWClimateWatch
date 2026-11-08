# Read-only input analysis, local diagnostics and PNG only. No downloads/publication.
source("scripts/load-prism-monthly.R")
source("R/map-reference-layers.R")
source("R/map-product-scales.R")
source("R/map-southwest.R")
monthly_temperature_pilot <- build_prism_monthly_temperature_pilot()
print(monthly_temperature_pilot$summary, row.names = FALSE)
print(monthly_temperature_pilot$paths)
