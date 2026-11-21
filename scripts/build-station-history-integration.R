# Local combined station preview. No downloads, site staging or daily changes.
source("scripts/load-station-custom-dates-pilot.R")
source("R/station-history-integration.R")
print(build_station_history_integration(), row.names = FALSE)
