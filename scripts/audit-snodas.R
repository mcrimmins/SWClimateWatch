# Offline, bounded SNODAS availability/quality report from NSIDC's errata list
# and whatever daily grids have already been processed locally.
# Run from the project root: source("scripts/audit-snodas.R")

source("R/config.R")
source("R/snodas.R")
source("R/audit-snodas.R")

snodas_audit_dir <- file.path("data", "diagnostics", "snodas-audit")
dir.create(snodas_audit_dir, recursive = TRUE, showWarnings = FALSE)

snodas_errata <- read_snodas_missing_days(file.path(
  swc_paths$raw, "snodas", "reference", "G02158_missing_files.txt"
))
snodas_day_calendar <- snodas_availability_calendar(errata = snodas_errata)
snodas_water_year_summary <- summarize_snodas_availability(snodas_day_calendar)
utils::write.csv(snodas_day_calendar,
                 file.path(snodas_audit_dir, "day-calendar.csv"), row.names = FALSE)
utils::write.csv(snodas_water_year_summary,
                 file.path(snodas_audit_dir, "water-year-summary.csv"),
                 row.names = FALSE)
print(snodas_water_year_summary, row.names = FALSE)

snodas_processed_manifest <- read_snodas_manifest(
  snodas_manifest_path("processed")
)
snodas_quality_rows <- list()
if (nrow(snodas_processed_manifest) &&
    all(c("date", "variable", "path") %in% names(snodas_processed_manifest))) {
  repair_mask_path <- file.path(
    swc_paths$raw, "snodas", "reference", "SNODAS_Zero_Repair_Mask.tif"
  )
  for (index in seq_len(nrow(snodas_processed_manifest))) {
    row <- snodas_processed_manifest[index, , drop = FALSE]
    if (!file.exists(row$path)) next
    snodas_quality_rows[[length(snodas_quality_rows) + 1L]] <-
      snodas_raster_quality(
        terra::rast(row$path), as.Date(row$date), row$variable,
        repair_mask_path = if (file.exists(repair_mask_path)) {
          repair_mask_path
        } else NULL
      )
  }
}
snodas_local_quality <- if (length(snodas_quality_rows)) {
  do.call(rbind, snodas_quality_rows)
} else data.frame()
utils::write.csv(snodas_local_quality,
                 file.path(snodas_audit_dir, "local-raster-quality.csv"),
                 row.names = FALSE)
print(snodas_local_quality, row.names = FALSE)
