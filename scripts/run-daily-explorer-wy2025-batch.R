source("scripts/load-daily-explorer-wy2025.R")
wy2025_batch<-run_wy2025_explorer_batch(month=getOption("swc.wy2025.month",NULL),
  download=isTRUE(getOption("swc.wy2025.download",FALSE)),
  max_input_dates=getOption("swc.wy2025.max_input_dates",10L),
  max_end_dates=getOption("swc.wy2025.max_end_dates",7L))
