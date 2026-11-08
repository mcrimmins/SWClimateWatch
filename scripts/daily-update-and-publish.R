# Daily entry point. Sourcing this updates PRISM and (in season) SNODAS,
# then renders, validates, and syncs changed site content. The confirmed live
# S3 prefix is the default; SWC_S3_DESTINATION can select a staging prefix.
# No remote objects are deleted. Run from the project root in RStudio.
# SWC_MONTHLY_MAPS=true adds the revision-aware monthly cycle (days 1-5),
# with retained monthly maps and no new source requests after completion.
source("scripts/load-daily-publish.R")
swc_daily_publish_result <- run_swc_daily_publish(dry_run = FALSE)
