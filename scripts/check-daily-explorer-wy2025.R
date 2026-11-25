source("scripts/load-daily-explorer-wy2025.R")
wy2025_check<-validate_wy2025_explorer(require_complete=isTRUE(getOption("swc.wy2025.require_complete",TRUE)))
