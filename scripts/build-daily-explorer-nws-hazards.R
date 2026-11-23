source("R/nws-hazards-explorer.R")
nws_hazards_explorer<-build_nws_hazards_explorer(refresh=isTRUE(getOption("swc.hazards.refresh",FALSE)))
message("Local only. Preview with source('scripts/preview-daily-explorer-nws-hazards.R').")
