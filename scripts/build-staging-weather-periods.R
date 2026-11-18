# Explicit manual staging trial; never invoked by the operational daily cron.
if(!identical(Sys.getenv("SWC_S3_DESTINATION"),"s3://cales-climate-reports/climate/watch-staging/"))
  stop("This test requires SWC_S3_DESTINATION=s3://cales-climate-reports/climate/watch-staging/.")
source("scripts/load-weather-period-archive.R")
weather_period_staging<-build_weather_period_archive(
  max_new_end_dates=as.integer(Sys.getenv("SWC_WEATHER_MEANS_MAX_NEW_DATES","3")))
if(weather_period_staging$periods==0L)stop("No complete weather mean periods; inspect data/processed/weather-period-means/last-batch.csv.")
