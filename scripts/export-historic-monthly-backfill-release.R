source("scripts/load-historic-monthly-backfill-publication.R")
source("R/map-reference-layers.R")
source("R/map-product-scales.R")
source("R/map-southwest.R")
source("R/historic-monthly-backfill.R")
print(check_historic_monthly_backfill_maps(), row.names = FALSE)
invisible(export_historic_monthly_release(source_dir = historic_monthly_backfill_root(),
  root = historic_monthly_backfill_release_root(), expected_years = historic_monthly_backfill_years()))
message("Portable backfill READY: data/processed/historic-monthly-backfill-release. No site changes or uploads.")
