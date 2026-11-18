# Reuses the reviewed local pilot and PRISM images; no network requests.
source("scripts/load-daily-explorer.R")
source("R/daily-explorer-weather-means-preview.R")
weather_means_explorer_preview<-stage_daily_explorer_weather_means_preview()
