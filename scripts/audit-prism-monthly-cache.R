source("scripts/load-prism-monthly.R")
monthly_cache_audit <- audit_prism_monthly_cache()
print(monthly_cache_audit$summary, row.names = FALSE)
if (monthly_cache_audit$summary$status == "FAIL") {
  print(subset(monthly_cache_audit$months, status == "FAIL"), row.names = FALSE)
  stop("Monthly cache audit failed. Inputs were not changed.", call. = FALSE)
}
