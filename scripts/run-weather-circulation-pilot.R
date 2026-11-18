# Bounded local test: one index and three small GRIB records, cached thereafter.
# No production changes, large archive download or ERA5 request.
source("scripts/load-weather-circulation-pilot.R")
swc_weather_pilot <- run_weather_circulation_pilot()
print(swc_weather_pilot$summary, row.names = FALSE)
