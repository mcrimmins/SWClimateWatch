# Scheduled entry point: download window days 1-5; no website publication.
source("scripts/load-prism-monthly.R")
monthly_update_result <- run_prism_monthly_update()
print(monthly_update_result$summary, row.names = FALSE)
if (monthly_update_result$summary$status == "FAILED") stop(monthly_update_result$summary$note, call. = FALSE)
