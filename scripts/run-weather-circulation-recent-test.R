# Source from the project root in RStudio. Checks seven indexes and renders
# at most three dates (six maps). Reuses verified downloads on subsequent runs.
source("scripts/load-weather-circulation-pilot.R")
source("R/weather-circulation-recent-test.R")
swc_weather_recent <- run_weather_circulation_recent_test()
