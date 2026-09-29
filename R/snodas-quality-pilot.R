# Bounded SWE/depth content-quality sample. Source config.R, snodas.R,
# audit-snodas.R, snodas-inventory.R, and snodas-grid.R first.

snodas_quality_pilot_dates <- as.Date(c(
  "2008-02-15", # pre-shift winter
  "2012-04-15", # pre-shift spring melt
  "2013-11-15", # post-shift snow onset
  "2017-02-15", # zero-repair-mask interval
  "2023-03-01", # late winter
  "2024-04-15", # recent spring melt
  "2025-02-15", # recent winter
  "2026-09-23"  # recent snow-free season
))

snodas_quality_archive <- function(date, raw_dir = swc_paths$raw) {
  date <- snodas_date(date)
  canonical <- snodas_archive_path(date, raw_dir)
  pilot <- file.path(raw_dir, "snodas", "pilot",
                     paste0("SNODAS_", format(date, "%Y%m%d"), ".tar"))
  if (file.exists(canonical) && file.info(canonical)$size > 0) canonical
  else if (file.exists(pilot) && file.info(pilot)$size > 0) pilot
  else canonical
}

plan_snodas_quality_pilot <- function(
    dates = snodas_quality_pilot_dates,
    inventory_path = file.path("data", "diagnostics", "snodas-audit",
                               "monthly-directory-inventory.csv"),
    raw_dir = swc_paths$raw) {
  dates <- sort(unique(as.Date(dates)))
  if (!length(dates) || anyNA(dates)) {
    stop("Quality pilot requires valid dates.", call. = FALSE)
  }
  if (!file.exists(inventory_path)) {
    stop("Complete the SNODAS directory inventory before the quality pilot.",
         call. = FALSE)
  }
  cache <- read_snodas_inventory(inventory_path)
  historical <- dates[dates <= as.Date("2025-09-30")]
  if (length(historical)) {
    selected_months <- format(historical, "%Y-%m-01")
    selected_rows <- match(selected_months, cache$month)
    listed <- vapply(seq_along(historical), function(index) {
      row <- selected_rows[index]
      if (is.na(row)) return(FALSE)
      as.character(historical[index]) %in% strsplit(
        cache$listed_dates[row], ",", fixed = TRUE
      )[[1L]]
    }, logical(1))
    if (any(!listed)) {
      stop("A historical SNODAS sample date is not confirmed listed.",
           call. = FALSE)
    }
  }
  paths <- vapply(dates, snodas_quality_archive, character(1),
                  raw_dir = raw_dir)
  available <- file.exists(paths)
  available[available] <- file.info(paths[available])$size > 0
  data.frame(date = dates, archive_path = paths,
             available = available, download = !available,
             stringsAsFactors = FALSE)
}

snodas_pair_quality <- function(swe, depth, date,
                                repair_mask_path = file.path(
                                  swc_paths$raw, "snodas", "reference",
                                  "SNODAS_Zero_Repair_Mask.tif")) {
  date <- snodas_date(date)
  if (!terra::compareGeom(swe, depth, stopOnError = FALSE)) {
    stop("SWE and depth do not share a grid.", call. = FALSE)
  }
  swe_quality <- snodas_raster_quality(swe, date, "swe", repair_mask_path)
  depth_quality <- snodas_raster_quality(depth, date, "depth", repair_mask_path)
  swe_values <- as.vector(terra::values(swe))
  depth_values <- as.vector(terra::values(depth))
  both <- is.finite(swe_values) & is.finite(depth_values)
  snow <- both & (swe_values > 0 | depth_values > 0)
  rows <- rbind(swe_quality, depth_quality)
  rows$both_valid_fraction <- mean(both)
  rows$snow_cells_both_valid <- sum(snow)
  rows$swe_positive_depth_zero <- sum(both & swe_values > 0 & depth_values == 0)
  rows$depth_positive_swe_zero <- sum(both & depth_values > 0 & swe_values == 0)
  rows$swe_exceeds_depth_cells <- sum(snow & swe_values > depth_values + 1e-6)
  rows
}
