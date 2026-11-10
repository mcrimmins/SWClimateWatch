# Run from the project root. Cached observations only; production is unchanged.
source("R/config.R")
source("R/acis-station-inventory.R")
source("R/acis-station-current-prototype.R")
source("R/acis-station-cumulative-pilot.R")
source("R/acis-station-seasonal-pilot.R")
station_seasonal_pilot <- build_acis_station_seasonal_pilot()
