# Build/stage optional weather assets only. Does not render Quarto or sync S3.
# Run after Daily Explorer has been staged for the latest PRISM inputs.
source("scripts/load-weather-circulation-archive.R")
swc_weather_archive <- update_weather_circulation_archive()
