# Run from project root. Cached inputs only; no operational maps are changed.
source("scripts/load-prism-monthly.R")
source("R/map-reference-layers.R")
source("R/map-product-scales.R")
source("R/map-southwest.R")
source("R/historic-monthly-pilot.R")
historic_monthly_pilot <- build_historic_monthly_pilot(
  years = getOption("swc.historic.monthly.years", c(2002L, 2005L, 2020L)),
  end = getOption("swc.historic.monthly.end", prism_monthly_latest_complete()),
  force = isTRUE(getOption("swc.historic.monthly.force", FALSE)))
print(historic_monthly_pilot$summary, row.names = FALSE)
message("Local gallery: ", historic_monthly_pilot$gallery, ". No existing pages or maps replaced.")
