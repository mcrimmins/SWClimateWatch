# Existing local caches only; no station updates, publication or site changes.
source("scripts/load-station-custom-dates-pilot.R")
station_custom_pilot <- build_station_custom_dates_pilot()
print(station_custom_pilot$summary, row.names = FALSE)
message("Local custom-date pilot ready. Rerun to measure unchanged-cache reuse.")
