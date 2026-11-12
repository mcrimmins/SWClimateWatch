# Build base period suite first if it does not exist. No publishing.
source("scripts/load-weather-circulation-pilot.R")
source("R/weather-moisture-pilot.R")
source("R/weather-seven-day-pilot.R")
source("R/weather-period-means-pilot.R")
source("R/weather-period-moisture-overlays.R")
overlay_allow_download<-identical(tolower(Sys.getenv("SWC_WEATHER_MEAN_DOWNLOAD","false")),"true")
weather_overlay_first<-run_weather_period_moisture_overlays(download_missing=overlay_allow_download)
weather_overlay_cached<-run_weather_period_moisture_overlays(download_missing=FALSE)
stopifnot(weather_overlay_cached$requests==0L,weather_overlay_cached$reused==3L)
write.csv(rbind(transform(weather_overlay_first,pass="first"),transform(weather_overlay_cached,pass="cache check")),
  "data/diagnostics/weather-period-means-pilot/overlay-two-pass.csv",row.names=FALSE)
