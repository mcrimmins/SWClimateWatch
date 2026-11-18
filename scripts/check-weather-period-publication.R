source("R/weather-period-archive.R")
for(directory in c("site/daily-explorer",if(dir.exists("site/_site/daily-explorer"))"site/_site/daily-explorer")) {
  payload<-jsonlite::read_json(file.path(directory,"daily-data.json"))
  if(!isTRUE(payload$circulation_period_means_enabled))stop("Weather period selector is not enabled in ",directory)
  checked<-validate_weather_period_assets(directory)
  message("Weather period check: PASS; ",checked$periods," periods; ",length(checked$images)," maps; ",directory)
}
