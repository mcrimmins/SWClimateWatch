source("R/daily-explorer-july-pilot.R")
july_pilot_load()
july_inputs<-prepare_daily_explorer_july(download=isTRUE(getOption("swc.july.download",FALSE)),
  max_new_dates=getOption("swc.july.max_input_dates",10L))
