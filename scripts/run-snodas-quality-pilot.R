# Three new daily tar files at most; all other dates reuse local archives.
# Run from project root: source("scripts/run-snodas-quality-pilot.R")
# This is diagnostic only; it does not publish maps or enable daily updates.

source("R/config.R")
source("R/snodas.R")
source("R/audit-snodas.R")
source("R/snodas-inventory.R")
source("R/snodas-grid.R")
source("R/snodas-quality-pilot.R")

if (!requireNamespace("terra", quietly = TRUE)) {
  stop("The terra package is required for the SNODAS quality pilot.",
       call. = FALSE)
}
snodas_quality_repair_mask <- file.path(
  swc_paths$raw, "snodas", "reference", "SNODAS_Zero_Repair_Mask.tif"
)
if (!file.exists(snodas_quality_repair_mask)) {
  stop("SNODAS zero-repair mask is required: ", snodas_quality_repair_mask,
       call. = FALSE)
}

snodas_quality_plan <- plan_snodas_quality_pilot()
snodas_quality_new_dates <- snodas_quality_plan$date[snodas_quality_plan$download]
if (length(snodas_quality_new_dates) > 3L) {
  stop("Quality pilot unexpectedly requires more than three new archives.",
       call. = FALSE)
}
message(sprintf("SNODAS quality pilot: %d dates; %d cached; %d new archives.",
                nrow(snodas_quality_plan),
                sum(snodas_quality_plan$available),
                length(snodas_quality_new_dates)))
if (length(snodas_quality_new_dates)) {
  snodas_quality_download_plan <- plan_snodas_download(
    snodas_quality_new_dates
  )
  download_snodas_plan(snodas_quality_download_plan,
                       max_requests = length(snodas_quality_new_dates))
}

snodas_quality_dir <- file.path("data", "diagnostics", "snodas-quality-pilot")
dir.create(snodas_quality_dir, recursive = TRUE, showWarnings = FALSE)
snodas_quality_rows <- vector("list", nrow(snodas_quality_plan))
for (index in seq_len(nrow(snodas_quality_plan))) {
  date <- snodas_quality_plan$date[index]
  archive <- snodas_quality_archive(date)
  snodas_archive_members(archive, date, "swe")
  snodas_archive_members(archive, date, "depth")
  processed <- process_snodas_date(date, c("swe", "depth"), archive = archive,
                                   repair_mask_path = snodas_quality_repair_mask)
  swe <- snodas_align_common_grid(terra::rast(
    snodas_processed_path(date, "swe")))
  depth <- snodas_align_common_grid(terra::rast(
    snodas_processed_path(date, "depth")))
  quality <- snodas_pair_quality(swe, depth, date,
                                 snodas_quality_repair_mask)
  quality$archive_bytes <- file.info(archive)$size
  quality$archive_path <- archive
  quality$processed_this_run <- processed$refreshed
  snodas_quality_rows[[index]] <- quality
  completed <- do.call(rbind, snodas_quality_rows[seq_len(index)])
  utils::write.csv(completed,
                   file.path(snodas_quality_dir, "swe-depth-quality.csv"),
                   row.names = FALSE)
  message(sprintf("SNODAS quality %d/%d: %s (SWE and depth)",
                  index, nrow(snodas_quality_plan), date))
}
snodas_quality_report <- do.call(rbind, snodas_quality_rows)
print(snodas_quality_report[, c(
  "date", "variable", "valid_fraction", "snow_fraction_valid",
  "max_inches", "negative_cells", "saturated_cells",
  "repair_zero_cells", "swe_exceeds_depth_cells"
)], row.names = FALSE)
