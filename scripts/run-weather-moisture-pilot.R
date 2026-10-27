# Two-date local PWAT/MSLP/850-mb prototype. No publication or archive backfill.
source("scripts/load-weather-circulation-pilot.R")
source("R/weather-moisture-pilot.R")
swc_moisture_pilot <- run_weather_moisture_pilot()
