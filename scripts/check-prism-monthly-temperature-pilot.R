# Local independent numerical check of the latest pilot and a 1993 end date.
source("scripts/load-prism-monthly.R")
source("R/prism-monthly-temperature-check.R")
monthly_temperature_check <- check_prism_monthly_temperature_pilot()
print(monthly_temperature_check$summary, row.names = FALSE)
print(monthly_temperature_check$samples, row.names = FALSE)
if (monthly_temperature_check$summary$status != "PASS") {
  print(subset(monthly_temperature_check$comparisons, status == "FAIL"), row.names = FALSE)
  stop("Independent monthly check needs investigation; see diagnostic reports.", call. = FALSE)
}
message("Independent monthly checks passed. No downloads or publication.")
