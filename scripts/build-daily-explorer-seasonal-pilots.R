source("R/daily-explorer-seasonal-pilots.R")
seasonal_explorer_load()
seasonal_build<-build_seasonal_explorer(download_events=isTRUE(getOption("swc.seasonal.download",FALSE)),
  max_end_dates=getOption("swc.seasonal.max_end_dates",7L))
