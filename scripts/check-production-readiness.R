# Read-only local/VM readiness check. No downloads, rendering, or S3 calls.
# Run from the repository root: Rscript scripts/check-production-readiness.R
source("R/config.R")
source("scripts/load-daily-publish.R")
source("R/production-preflight.R")

swc_production_preflight_result <- swc_production_preflight()
for (index in seq_len(nrow(swc_production_preflight_result$checks))) {
  check <- swc_production_preflight_result$checks[index, ]
  cat(sprintf("%-7s %-14s %s\n", check$status, check$group, check$item))
}
message("Destination: ", swc_production_preflight_result$destination)
if (!swc_production_preflight_result$staging_destination) {
  message("This is the LIVE destination; set SWC_S3_DESTINATION to a dedicated staging prefix before the VM trial.")
}
message("Effective time zone: ", swc_production_preflight_result$timezone,
        if (swc_production_preflight_result$timezone_matches) " (Arizona time)"
        else " (set TZ=America/Phoenix before scheduling)")
message("Environment and transferred assets: ",
        if (swc_production_preflight_result$ready) "PASS" else "INCOMPLETE")
message("Local staging preflight: ",
        if (swc_production_preflight_result$ready &&
            swc_production_preflight_result$staging_destination &&
            swc_production_preflight_result$timezone_matches) "PASS" else "INCOMPLETE",
        " (AWS permissions and machine capacity not checked)")
