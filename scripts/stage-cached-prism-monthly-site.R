# Restage accepted local monthly maps before a site render. No requests or rebuilds.
source("scripts/load-prism-monthly.R")
source("R/prism-monthly-site.R")
monthly_cached_site <- stage_cached_prism_monthly_site()
monthly_cached_check <- validate_prism_monthly_publication()
print(monthly_cached_check$summary,row.names=FALSE)
if(monthly_cached_check$summary$status!="PASS")stop("Cached Monthly Climate release failed validation; publication stopped before rendering.")
