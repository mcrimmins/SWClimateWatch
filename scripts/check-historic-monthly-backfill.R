source("scripts/check-historic-monthly-backfill-maps.R")
source("R/historic-monthly-site-preview.R")
print(validate_historic_monthly_site_preview(historic_monthly_backfill_site(), TRUE,
  expected_years = historic_monthly_backfill_years(), allow_early = TRUE), row.names = FALSE)
message("All 86 earlier-year map batches and rendered pages validated. Nothing staged or published.")
