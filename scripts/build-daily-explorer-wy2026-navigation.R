source("scripts/load-daily-explorer-wy2026.R")
wy2026_preview<-build_wy2026_explorer_navigation(require_complete=isTRUE(getOption("swc.wy2026.require_complete",TRUE)))
