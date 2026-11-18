# Local only. Reuses an existing Daily Explorer; no PRISM downloads or S3 sync.
source("scripts/load-weather-circulation-pilot.R")
source("R/weather-moisture-pilot.R")
source("R/daily-explorer-circulation.R")
swc_circulation_preview <- stage_daily_explorer_circulation_preview()
if(any(swc_circulation_preview$status$status=="FAILED"))
  stop("Weather preview has failed dates; inspect swc_circulation_preview$status before staging.")
