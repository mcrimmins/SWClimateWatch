# Exercise the monthly adapter against this checkout without source requests,
# map builds, site staging, rendering, notification or S3 sync.
source("scripts/load-daily-publish.R")
monthly_runner_check <- swc_daily_publish_update_monthly(enabled=TRUE,
  .run=function(today) {
    preview <- run_prism_monthly_update(today=today,dry_run=TRUE)
    if(!preview$summary$status %in% c("ALREADY_COMPLETE","SKIPPED_OUTSIDE_WINDOW"))
      stop("Monthly cycle needs work; use the normal monthly/daily update command. This check makes no source requests.")
    run_prism_monthly_update(today=today,.fetch=function(...) stop("Source requests are forbidden in this check."))
  },
  .stage=function(...) stop("Monthly page needs reconciliation; run scripts/stage-prism-monthly-site.R before repeating this check."))
message(swc_monthly_summary_line(monthly_runner_check))
print(as.data.frame(monthly_runner_check),row.names=FALSE)
if(monthly_runner_check$status=="FAILED"||!isTRUE(monthly_runner_check$publication_ready)||isTRUE(monthly_runner_check$needs_attention))
  stop("Monthly runner check needs attention; see the summary above.")
