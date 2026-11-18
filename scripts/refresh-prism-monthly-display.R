# Refresh completed monthly maps for a display-policy change. No source requests.
source("scripts/load-prism-monthly.R")
source("R/prism-monthly-site.R")
monthly_display_plan <- run_prism_monthly_update(dry_run=TRUE)
if(!monthly_display_plan$summary$status %in% c("REBUILD_ONLY","ALREADY_COMPLETE"))
  stop("Complete the monthly cycle first. This display refresh does not download data.")
monthly_display_refresh <- run_prism_monthly_update(
  .fetch=function(...) stop("Source requests are forbidden during a display-only refresh."))
print(monthly_display_refresh$summary,row.names=FALSE)
if(!monthly_display_refresh$summary$status %in% c("COMPLETE","ALREADY_COMPLETE")) stop("Monthly display refresh is incomplete.")
monthly_site <- stage_prism_monthly_site()
monthly_publication <- validate_prism_monthly_publication()
print(monthly_publication$summary,row.names=FALSE)
if(monthly_publication$summary$status!="PASS") stop("Monthly source publication validation failed.")
