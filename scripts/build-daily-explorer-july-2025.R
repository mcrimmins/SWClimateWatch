source("R/daily-explorer-july-pilot.R")
july_pilot_load()
july_build<-build_daily_explorer_july(download_events=isTRUE(getOption("swc.july.download",FALSE)),
  max_end_dates=getOption("swc.july.max_end_dates",7L))
if(identical(july_build$status,"READY"))validate_daily_explorer_july()
