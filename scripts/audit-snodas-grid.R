# Bounded six-date check of the fixed post-2013 SNODAS grid.
# No network requests. Run from project root: source("scripts/audit-snodas-grid.R")

source("R/config.R")
source("R/snodas.R")
source("R/snodas-grid.R")
source("R/audit-snodas.R")

snodas_grid_sample_dates <- as.Date(c(
  "2008-02-15", "2013-02-15", "2014-02-15",
  "2017-02-15", "2023-03-01", "2025-02-15"
))
snodas_grid_template <- snodas_common_grid()
snodas_grid_audit_dir <- file.path("data", "diagnostics", "snodas-grid-pilot")
dir.create(snodas_grid_audit_dir, recursive = TRUE, showWarnings = FALSE)

snodas_grid_pilot <- do.call(rbind, lapply(snodas_grid_sample_dates, function(date) {
  native_path <- snodas_processed_path(date, "swe")
  if (!file.exists(native_path)) {
    archive <- snodas_archive_path(date)
    if (!file.exists(archive)) {
      archive <- file.path(
        swc_paths$raw, "snodas", "pilot",
        paste0("SNODAS_", format(date, "%Y%m%d"), ".tar")
      )
    }
    if (!file.exists(archive)) {
      stop("Sample SNODAS archive is not available: ", date, call. = FALSE)
    }
    process_snodas_date(date, "swe", archive = archive)
  }
  native <- terra::rast(native_path)
  aligned <- snodas_align_common_grid(native, snodas_grid_template)
  metrics <- snodas_alignment_metrics(native, aligned,
                                      snodas_grid_template, date)
  quality <- snodas_raster_quality(
    aligned, date, "swe",
    repair_mask_path = file.path(
      swc_paths$raw, "snodas", "reference", "SNODAS_Zero_Repair_Mask.tif"
    )
  )
  metrics$aligned_valid_fraction <- quality$valid_fraction
  metrics$snow_fraction_valid <- quality$snow_fraction_valid
  metrics$negative_cells <- quality$negative_cells
  metrics$saturated_cells <- quality$saturated_cells
  metrics$repair_mask_cells <- quality$repair_mask_cells
  metrics$repair_zero_cells <- quality$repair_zero_cells
  output_path <- file.path(
    snodas_grid_audit_dir, paste0("swe-", date, "-common-grid.tif")
  )
  terra::writeRaster(aligned, output_path, overwrite = TRUE,
                     datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
  metrics$path <- output_path
  metrics
}))

utils::write.csv(snodas_grid_pilot,
                 file.path(snodas_grid_audit_dir, "alignment-metrics.csv"),
                 row.names = FALSE)
print(snodas_grid_pilot, row.names = FALSE)
