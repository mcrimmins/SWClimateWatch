source("R/map-cleanup-audit.R")
map_cleanup_audit <- audit_map_cleanup(
  grace_days = getOption("swc.cleanup.grace_days", 30L),
  keep_latest = getOption("swc.cleanup.keep_latest", 2L))
