# Default is cached-only. Opt in explicitly to at most four missing dates.
source("scripts/load-weather-circulation-pilot.R")
source("R/weather-moisture-pilot.R")
source("R/weather-seven-day-pilot.R")
weather_mean_end<-Sys.getenv("SWC_WEATHER_MEAN_END","2026-10-05")
weather_seven_day_first<-run_weather_seven_day_pilot(weather_mean_end,
  download_missing=identical(tolower(Sys.getenv("SWC_WEATHER_MEAN_DOWNLOAD","false")),"true"))
weather_seven_day_cached<-run_weather_seven_day_pilot(weather_mean_end,download_missing=FALSE)
stopifnot(weather_seven_day_cached$reused,weather_seven_day_cached$requests==0L)
weather_seven_day_runs<-rbind(transform(weather_seven_day_first,pass="first"),transform(weather_seven_day_cached,pass="cache check"))
write.csv(weather_seven_day_runs,"data/diagnostics/weather-seven-day-pilot/two-pass-summary.csv",row.names=FALSE)
print(weather_seven_day_runs,row.names=FALSE)
