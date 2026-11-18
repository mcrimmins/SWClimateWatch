# Small, resumable true-monthly sample. No daily data, maps or publication changed.
source("scripts/load-prism-monthly.R")
monthly_pilot_started <- proc.time()[["elapsed"]]
monthly_pilot_months <- unique(c("1895-01", "1991-01", "2020-07",
  prism_monthly_latest_complete()))
monthly_pilot_plan <- plan_prism_monthly_download(months = monthly_pilot_months)
monthly_pilot_result <- download_prism_monthly_plan(monthly_pilot_plan)
monthly_pilot_after <- plan_prism_monthly_download(months = monthly_pilot_months)
monthly_pilot_pairs <- lapply(monthly_pilot_months, function(month) {
  rows <- monthly_pilot_after[monthly_pilot_after$month == month, ]
  if (!all(rows$complete)) return(data.frame(month = month, status = "PENDING", max_below_min_cells = NA_real_))
  hi <- terra::rast(rows$path[rows$variable == "maxt"])
  lo <- terra::rast(rows$path[rows$variable == "mint"])
  bad <- terra::global(hi < lo, "sum", na.rm = TRUE)[1, 1]
  data.frame(month = month, status = if (bad == 0) "PASS" else "FAIL", max_below_min_cells = bad)
})
monthly_pilot_pairs <- do.call(rbind, monthly_pilot_pairs)
monthly_pilot_dir <- "data/diagnostics/prism-monthly-access-pilot"
dir.create(monthly_pilot_dir, recursive = TRUE, showWarnings = FALSE)
write.csv(monthly_pilot_after, file.path(monthly_pilot_dir, "inventory.csv"), row.names = FALSE)
write.csv(monthly_pilot_result, file.path(monthly_pilot_dir, "last-run.csv"), row.names = FALSE)
write.csv(monthly_pilot_pairs, file.path(monthly_pilot_dir, "temperature-pairs.csv"), row.names = FALSE)
monthly_pilot_summary <- data.frame(
  inputs = nrow(monthly_pilot_after), verified = sum(monthly_pilot_after$complete),
  pending = sum(!monthly_pilot_after$complete),
  temperature_pair_failures = sum(monthly_pilot_pairs$status == "FAIL"),
  attempted = nrow(monthly_pilot_result),
  saved_mb = sum(file.info(monthly_pilot_after$path)$size, na.rm = TRUE) / 1024^2,
  elapsed_seconds = proc.time()[["elapsed"]] - monthly_pilot_started)
write.csv(monthly_pilot_summary, file.path(monthly_pilot_dir, "summary.csv"), row.names = FALSE)
print(monthly_pilot_summary, row.names = FALSE)
if (nrow(monthly_pilot_result)) print(monthly_pilot_result, row.names = FALSE)
if (monthly_pilot_summary$pending > 0 || monthly_pilot_summary$temperature_pair_failures > 0) {
  stop("Monthly pilot incomplete; see last-run.csv. Rerun the same script to resume.", call. = FALSE)
}
message("Monthly sample verified. Rerun to check cache reuse; no maps or publication changed.")
