# Run from the project root. Reads cached histories only; no production changes.
source("R/config.R")
source("R/acis-station-inventory.R")
source("R/acis-station-current-prototype.R")
source("R/acis-station-cumulative-pilot.R")
station_cumulative_pilot <- build_acis_station_cumulative_pilot()
