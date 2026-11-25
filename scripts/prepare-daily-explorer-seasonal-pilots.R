source("R/daily-explorer-seasonal-pilots.R")
seasonal_explorer_load()
seasonal_inputs<-prepare_seasonal_explorer(download=isTRUE(getOption("swc.seasonal.download",FALSE)),
  max_new_dates=getOption("swc.seasonal.max_input_dates",10L))
