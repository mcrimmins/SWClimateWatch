# Local, read-only audit of high SNODAS SWE areas and their short-term
# persistence. This is diagnostic work, not an automated quality mask.

snodas_high_swe_window_metrics <- function(
    anchor, window_values, thresholds = c(12, 20, 30, 40),
    persistence_fraction = 0.75) {
  if (!inherits(anchor, "SpatRaster") || terra::nlyr(anchor) != 1L ||
      !is.list(window_values) || !length(window_values) ||
      !is.numeric(thresholds) || !length(thresholds) ||
      any(!is.finite(thresholds) | thresholds <= 0) ||
      !is.numeric(persistence_fraction) ||
      length(persistence_fraction) != 1L ||
      !is.finite(persistence_fraction) ||
      persistence_fraction <= 0 || persistence_fraction > 1) {
    stop("Invalid high-SWE audit inputs.", call. = FALSE)
  }
  anchor_values <- terra::values(anchor, mat = FALSE)
  if (any(!vapply(window_values, function(values) {
    is.numeric(values) && length(values) == length(anchor_values)
  }, logical(1)))) {
    stop("Window values must match the anchor grid.", call. = FALSE)
  }
  area_values <- terra::values(terra::cellSize(anchor, unit = "km"),
                               mat = FALSE)
  valid_cells <- sum(is.finite(anchor_values))
  result <- lapply(sort(unique(thresholds)), function(threshold) {
    selected <- which(is.finite(anchor_values) &
                        anchor_values >= threshold)
    if (!length(selected)) {
      return(data.frame(
        threshold_inches = threshold, high_cells = 0L,
        high_percent_valid = 0, high_area_km2 = 0,
        patch_count = 0L, largest_patch_percent = NA_real_,
        persistent_cells = 0L, persistent_percent = NA_real_
      ))
    }
    high_mask <- anchor
    mask_values <- rep(NA_real_, length(anchor_values))
    mask_values[selected] <- 1
    terra::values(high_mask) <- mask_values
    patch_frequency <- terra::freq(terra::patches(high_mask,
                                                  directions = 8))
    patch_sizes <- patch_frequency$count[is.finite(patch_frequency$value)]
    valid_days <- integer(length(selected))
    high_days <- integer(length(selected))
    for (values in window_values) {
      observed <- values[selected]
      present <- is.finite(observed)
      valid_days <- valid_days + as.integer(present)
      high_days <- high_days + as.integer(present &
                                           observed >= threshold)
    }
    required <- ceiling(persistence_fraction * length(window_values))
    persistent <- valid_days >= required &
      high_days / pmax(valid_days, 1L) >= persistence_fraction
    data.frame(
      threshold_inches = threshold,
      high_cells = length(selected),
      high_percent_valid = 100 * length(selected) / valid_cells,
      high_area_km2 = sum(area_values[selected], na.rm = TRUE),
      patch_count = length(patch_sizes),
      largest_patch_percent = 100 * max(patch_sizes) / length(selected),
      persistent_cells = sum(persistent),
      persistent_percent = 100 * mean(persistent)
    )
  })
  do.call(rbind, result)
}

snodas_screened_swe_for_audit <- function(
    date, processed_dir = swc_paths$processed,
    template = snodas_common_grid()) {
  swe <- terra::rast(snodas_processed_path(date, "swe", processed_dir))
  depth <- terra::rast(snodas_processed_path(date, "depth", processed_dir))
  screened <- screen_snodas_analysis_pair(swe, depth)
  snodas_align_common_grid(screened$swe, template)
}

audit_snodas_high_swe_date <- function(
    date, radius_days = 7L, thresholds = c(12, 20, 30, 40),
    persistence_fraction = 0.75,
    processed_dir = swc_paths$processed,
    template = snodas_common_grid()) {
  date <- snodas_date(date)
  if (!is.numeric(radius_days) || length(radius_days) != 1L ||
      is.na(radius_days) || radius_days != floor(radius_days) ||
      radius_days < 0L || radius_days > 30L) {
    stop("`radius_days` must be a whole number from 0 to 30.",
         call. = FALSE)
  }
  window_dates <- seq(date - as.integer(radius_days),
                      date + as.integer(radius_days), by = "day")
  plan <- data.frame(
    date = window_dates,
    path = vapply(window_dates, snodas_processed_path, character(1),
                  variable = "swe", processed_dir = processed_dir),
    complete = TRUE
  )
  status <- snodas_cool_season_processed(plan, processed_dir)
  if (!status$complete[window_dates == date]) {
    stop("Anchor SNODAS SWE/depth pair is not processed: ", date,
         call. = FALSE)
  }
  available_dates <- window_dates[status$complete]
  window_values <- lapply(available_dates, function(day) {
    terra::values(snodas_screened_swe_for_audit(
      day, processed_dir, template
    ), mat = FALSE)
  })
  anchor <- snodas_screened_swe_for_audit(date, processed_dir, template)
  summary <- snodas_high_swe_window_metrics(
    anchor, window_values, thresholds, persistence_fraction
  )
  values <- terra::values(anchor, mat = FALSE)
  peak <- which.max(values)
  peak_xy <- terra::xyFromCell(anchor, peak)
  summary$date <- as.character(date)
  summary$days_expected <- length(window_dates)
  summary$days_available <- length(available_dates)
  summary$max_inches <- values[[peak]]
  summary$max_longitude <- peak_xy[[1L]]
  summary$max_latitude <- peak_xy[[2L]]
  summary[, c("date", "days_expected", "days_available",
              "threshold_inches", "high_cells", "high_percent_valid",
              "high_area_km2", "patch_count", "largest_patch_percent",
              "persistent_cells", "persistent_percent", "max_inches",
              "max_longitude", "max_latitude")]
}
