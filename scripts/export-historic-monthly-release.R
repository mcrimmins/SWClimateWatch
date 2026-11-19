# Re-render only verified cached fields, with publication footers; no downloads.
source("scripts/load-historic-monthly-publication.R")
source("R/map-reference-layers.R")
source("R/map-product-scales.R")
source("R/map-southwest.R")
source("R/historic-monthly-archive.R")
print(check_historic_monthly_archive_maps(), row.names = FALSE)
invisible(export_historic_monthly_release())
message("Portable archive READY: data/processed/historic-monthly-release. No site pages changed or uploaded.")
