# Local review only. Run from project root after a completed monthly map build.
source("scripts/load-prism-monthly.R")
source("R/prism-monthly-site.R")
monthly_site <- stage_prism_monthly_site()
monthly_publication <- validate_prism_monthly_publication()
print(monthly_publication$summary, row.names = FALSE)
if (monthly_publication$summary$status != "PASS") stop("Monthly publication checks failed; inspect diagnostics.")
