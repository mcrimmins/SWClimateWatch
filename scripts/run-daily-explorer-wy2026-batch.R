source("scripts/load-daily-explorer-wy2026.R")
wy2026_batch<-run_wy2026_explorer_batch(month=getOption("swc.wy2026.month",NULL),
  download=isTRUE(getOption("swc.wy2026.download",FALSE)),
  max_input_dates=getOption("swc.wy2026.max_input_dates",10L),
  max_end_dates=getOption("swc.wy2026.max_end_dates",7L))
