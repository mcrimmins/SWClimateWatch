source("scripts/load-prism-monthly.R")
source("R/historic-monthly-pilot.R")
source("R/historic-monthly-backfill.R")
source("R/historic-monthly-site-preview.R")
print(validate_historic_monthly_site_preview(historic_monthly_backfill_site(), TRUE,
  expected_years = historic_monthly_backfill_years(), allow_early = TRUE), row.names = FALSE)
historic_backfill_index <- normalizePath(file.path(historic_monthly_backfill_site(), "_site/index.html"),
  winslash = "/", mustWork = TRUE)
if (interactive()) utils::browseURL(historic_backfill_index)
message("Historic Years backfill preview: ", historic_backfill_index)
