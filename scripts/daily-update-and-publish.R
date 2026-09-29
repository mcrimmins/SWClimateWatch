# LIVE daily entry point. Sourcing this updates PRISM and (in season) SNODAS,
# then renders, validates, and syncs changed site content to the confirmed S3
# prefix. No remote objects are deleted. Run from the project root in RStudio.
source("scripts/load-daily-publish.R")
swc_daily_publish_result <- run_swc_daily_publish(dry_run = FALSE)
message("Daily site workflow: ", swc_daily_publish_result$status)
