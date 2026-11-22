# Up to 62 cached Explorer dates; a single bounded AZ/NM report request on first
# build, plus one preceding UTC date for PRISM timing. Reruns reuse the verified
# raw caches unless explicitly refreshed.
source("R/storm-reports-pilot.R")
storm_reports_pilot <- build_storm_reports_pilot(
  source_dir=getOption("swc.storm.source_dir","site/daily-explorer"),
  refresh=isTRUE(getOption("swc.storm.refresh",FALSE)))
message("Local only. Preview with source('scripts/preview-daily-explorer-storm-reports.R').")
