# Cached PRISM: current water year plus preceding September. The explicit
# staging-only storm report trial may fetch report metadata; this script never uploads.
source("scripts/load-daily-explorer.R")
if(tolower(Sys.getenv("SWC_DAILY_ARCHIVE_STAGING"))=="true") {
  source("R/daily-explorer-archive-staging.R")
  daily_archive_staging_guard()
}
if(tolower(Sys.getenv("SWC_NWS_HAZARDS"))=="true") {
  source("R/nws-hazards-daily.R")
  nws_hazards_daily_guard()
}
if(tolower(Sys.getenv("SWC_NWS_HAZARDS_STAGING"))=="true") {
  source("R/nws-hazards-staging.R")
  nws_hazards_staging_guard()
}
if(tolower(Sys.getenv("SWC_STORM_REPORTS"))=="true") {
  source("R/storm-reports-daily.R")
  storm_reports_daily_guard()
}
if(tolower(Sys.getenv("SWC_STORM_REPORTS_STAGING"))=="true") {
  source("R/storm-reports-staging.R")
  storm_reports_staging_guard()
}
swc_daily_explorer_site <- stage_daily_explorer_site()
if(tolower(Sys.getenv("SWC_STORM_REPORTS"))=="true") {
  source("R/storm-reports-daily.R")
  prepare_storm_reports_daily(download=FALSE)
} else if(tolower(Sys.getenv("SWC_STORM_REPORTS_STAGING"))=="true") {
  source("R/storm-reports-staging.R")
  stage_storm_reports_staging()
}
if(tolower(Sys.getenv("SWC_NWS_HAZARDS"))=="true") {
  source("R/nws-hazards-daily.R")
  prepare_nws_hazards_daily(download=FALSE)
} else if(tolower(Sys.getenv("SWC_NWS_HAZARDS_STAGING"))=="true") {
  source("R/nws-hazards-staging.R")
  stage_nws_hazards_staging()
}
if(tolower(Sys.getenv("SWC_DAILY_ARCHIVE_STAGING"))=="true") {
  source("R/daily-explorer-archive-staging.R")
  stage_daily_archive_trial()
}
