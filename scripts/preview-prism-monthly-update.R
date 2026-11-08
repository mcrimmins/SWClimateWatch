# Manual preview is allowed any day and never downloads or changes files.
source("scripts/load-prism-monthly.R")
monthly_update_preview <- run_prism_monthly_update(manual = TRUE, dry_run = TRUE)
print(monthly_update_preview$summary, row.names = FALSE)
print(monthly_update_preview$requests, row.names = FALSE)
