# Cached PRISM: current water year plus preceding September. The explicit
# staging-only storm report trial may fetch report metadata; this script never uploads.
source("scripts/load-daily-explorer.R")
if(tolower(Sys.getenv("SWC_STORM_REPORTS_STAGING"))=="true") {
  source("R/storm-reports-staging.R")
  storm_reports_staging_guard()
}
swc_daily_explorer_site <- stage_daily_explorer_site()
if(tolower(Sys.getenv("SWC_STORM_REPORTS_STAGING"))=="true") {
  source("R/storm-reports-staging.R")
  stage_storm_reports_staging()
}
