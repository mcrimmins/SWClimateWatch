source("scripts/load-daily-explorer-wy2026.R")
wy2026_check<-validate_wy2026_explorer(require_complete=isTRUE(getOption("swc.wy2026.require_complete",TRUE)))
