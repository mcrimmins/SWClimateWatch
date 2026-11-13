# Read-only startup check matching the daily publisher. No requests or builds.
source("scripts/load-daily-publish.R")
station_context_check<-swc_daily_publish_station_context()
required<-c("run_swc_station_beta_update","run_acis_station_explorer_update_pilot",
  "build_acis_station_explorer_prototype","validate_acis_station_monthly_detail")
stopifnot(all(vapply(required,function(name)exists(name,envir=station_context_check,inherits=FALSE),logical(1))))
message("PASS: isolated daily station modules and monthly climatology loaded; no downloads, page changes or publication.")
