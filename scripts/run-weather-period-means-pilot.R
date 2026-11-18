# Local pilot only. Downloads are opt-in and bounded to selected fields.
source("scripts/load-weather-circulation-pilot.R")
source("R/weather-moisture-pilot.R")
source("R/weather-seven-day-pilot.R")
source("R/weather-period-means-pilot.R")
weather_period_end<-Sys.getenv("SWC_WEATHER_MEAN_END","2026-10-05")
weather_period_first<-run_weather_period_suite(weather_period_end,
  download_missing=identical(tolower(Sys.getenv("SWC_WEATHER_MEAN_DOWNLOAD","false")),"true"))
weather_period_cached<-run_weather_period_suite(weather_period_end,download_missing=FALSE)
stopifnot(weather_period_cached$summary$reused==9L,weather_period_cached$summary$requests==0L)
weather_period_runs<-rbind(transform(weather_period_first$summary,pass="first"),
  transform(weather_period_cached$summary,pass="cache check"))
write.csv(weather_period_runs,"data/diagnostics/weather-period-means-pilot/two-pass-summary.csv",row.names=FALSE)
print(weather_period_runs,row.names=FALSE)
if(file.exists("data/diagnostics/weather-period-means-pilot/overlay-inputs.csv"))
  source("scripts/run-weather-period-moisture-overlays.R")
