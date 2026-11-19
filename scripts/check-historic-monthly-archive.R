source("scripts/load-prism-monthly.R")
source("R/historic-monthly-pilot.R")
source("R/historic-monthly-archive.R")
source("R/historic-monthly-site-preview.R")
print(check_historic_monthly_archive_maps(), row.names = FALSE)
print(validate_historic_monthly_site_preview("data/diagnostics/historic-monthly-archive-site", TRUE,
  expected_years = historic_monthly_archive_years()), row.names = FALSE)
message("Existing-year map and rendered-page validation complete. Nothing staged or published.")
