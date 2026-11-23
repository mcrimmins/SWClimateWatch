source("R/nws-hazards-pilot.R")
nws_hazards_pilot<-build_nws_hazards_pilot(refresh=isTRUE(getOption("swc.hazards.refresh",FALSE)))
message("Review workload.csv and view-workload.csv, then source('scripts/preview-nws-hazards-pilot.R'). No site files or publication changed.")
