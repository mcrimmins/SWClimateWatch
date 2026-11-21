# Use the exact daily overlay and atomic station stage, without ACIS or uploads.
source("scripts/load-station-custom-dates-pilot.R")
source("R/acis-station-site.R")
if(!swc_station_history_enabled())stop("Set SWC_STATION_HISTORY=true before testing the cached daily path.")
station_history_cached_result <- swc_station_beta_finish()
print(station_history_cached_result$history,row.names=FALSE)
message("Daily station-history path staged from existing caches; no observations downloaded or site uploaded.")
