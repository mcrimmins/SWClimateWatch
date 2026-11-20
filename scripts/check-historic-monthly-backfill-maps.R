source("scripts/load-prism-monthly.R")
source("R/historic-monthly-pilot.R")
source("R/historic-monthly-backfill.R")
print(check_historic_monthly_backfill_maps(), row.names = FALSE)
