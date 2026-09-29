# Check up to 12 monthly NSIDC directory listings, saving progress after each.
# Run from the project root: source("scripts/inventory-snodas-availability.R")
# Metadata only: no daily tar archives are downloaded.

source("R/config.R")
source("R/snodas.R")
source("R/audit-snodas.R")
source("R/snodas-inventory.R")

snodas_inventory_result <- snodas_inventory_batch()
snodas_inventory_calendar_result <- snodas_inventory_calendar(
  snodas_inventory_result$cache
)
snodas_inventory_month_summary <- summarize_snodas_inventory(
  snodas_inventory_calendar_result
)
snodas_inventory_water_year_summary <- summarize_snodas_inventory_water_year(
  snodas_inventory_month_summary
)
snodas_inventory_dir <- file.path("data", "diagnostics", "snodas-audit")
utils::write.csv(snodas_inventory_calendar_result,
                 file.path(snodas_inventory_dir, "inventory-day-calendar.csv"),
                 row.names = FALSE)
utils::write.csv(snodas_inventory_month_summary,
                 file.path(snodas_inventory_dir, "inventory-month-summary.csv"),
                 row.names = FALSE)
utils::write.csv(snodas_inventory_water_year_summary,
                 file.path(snodas_inventory_dir, "inventory-water-year-summary.csv"),
                 row.names = FALSE)
cat(sprintf("SNODAS monthly listings: %d checked this run; %d of %d checked; %d remaining.\n",
            snodas_inventory_result$checked_this_run,
            sum(snodas_inventory_month_summary$checked),
            nrow(snodas_inventory_month_summary),
            snodas_inventory_result$remaining))
print(subset(snodas_inventory_month_summary,
             checked & (unexplained_unlisted > 0 | errata_conflicts > 0)),
      row.names = FALSE)
