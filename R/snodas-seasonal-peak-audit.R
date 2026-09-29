# Diagnostic provenance for high seasonal SNODAS SWE peaks. This never
# changes the source grids, seasonal rasters, or the archive quality gate.

snodas_seasonal_peak_evidence <- function(
    dates, peak_swe, read_day, threshold_inches = 50,
    radius_days = 7L, near_peak_fraction = 0.75,
    progress_every = 25L) {
  dates <- sort(unique(as.Date(dates)))
  if (!length(dates) || anyNA(dates) ||
      !inherits(peak_swe, "SpatRaster") || terra::nlyr(peak_swe) != 1L ||
      !is.function(read_day) ||
      length(threshold_inches) != 1L || !is.numeric(threshold_inches) ||
      !is.finite(threshold_inches) || threshold_inches <= 0 ||
      length(radius_days) != 1L || !is.numeric(radius_days) ||
      !is.finite(radius_days) || radius_days != floor(radius_days) ||
      radius_days < 1L || radius_days > 30L ||
      length(near_peak_fraction) != 1L ||
      !is.numeric(near_peak_fraction) ||
      !is.finite(near_peak_fraction) ||
      near_peak_fraction <= 0 || near_peak_fraction > 1 ||
      length(progress_every) != 1L || !is.numeric(progress_every) ||
      !is.finite(progress_every) || progress_every != floor(progress_every) ||
      progress_every < 1L) {
    stop("Invalid seasonal peak evidence inputs.", call. = FALSE)
  }
  peak_values <- terra::values(peak_swe, mat = FALSE)
  selected <- which(is.finite(peak_values) &
                      peak_values >= threshold_inches)
  if (!length(selected)) {
    return(data.frame(
      cell = integer(), longitude = numeric(), latitude = numeric(),
      patch_id = integer(), patch_cells = integer(),
      map_peak_inches = numeric(), daily_peak_inches = numeric(),
      peak_date = character(), peak_difference_inches = numeric(),
      nearby_calendar_days = integer(), nearby_valid_days = integer(),
      nearby_near_peak_days = integer(), nearby_near_peak_fraction = numeric(),
      context = character(), stringsAsFactors = FALSE
    ))
  }
  mask_values <- rep(NA_real_, terra::ncell(peak_swe))
  mask_values[selected] <- 1
  high_mask <- terra::setValues(peak_swe, mask_values)
  patch <- terra::values(terra::patches(high_mask, directions = 8),
                         mat = FALSE)[selected]
  patch_count <- table(patch)
  xy <- terra::xyFromCell(peak_swe, selected)
  daily <- matrix(NA_real_, nrow = length(dates), ncol = length(selected))
  for (index in seq_along(dates)) {
    grid <- read_day(dates[index])
    if (!inherits(grid, "SpatRaster") || terra::nlyr(grid) != 1L ||
        !terra::compareGeom(grid, peak_swe, stopOnError = FALSE)) {
      stop("Invalid aligned SNODAS SWE for ", dates[index], call. = FALSE)
    }
    daily[index, ] <- terra::values(grid, mat = FALSE)[selected]
    if (index %% progress_every == 0L || index == length(dates)) {
      message(sprintf("SNODAS peak provenance: %d/%d dates.",
                      index, length(dates)))
    }
  }
  if (any(colSums(is.finite(daily)) == 0L)) {
    stop("A mapped high-SWE cell has no valid daily value.",
         call. = FALSE)
  }
  peak_index <- apply(daily, 2L, which.max)
  daily_peak <- daily[cbind(peak_index, seq_along(selected))]
  if (any(!is.finite(daily_peak))) {
    stop("A mapped high-SWE cell has no valid daily value.",
         call. = FALSE)
  }
  nearby_calendar <- nearby_valid <- nearby_near_peak <-
    integer(length(selected))
  for (index in seq_along(selected)) {
    # Missing inventory dates count in the calendar window, but cannot
    # contribute evidence of persistence.
    full_window <- seq(dates[peak_index[index]] - radius_days,
                       dates[peak_index[index]] + radius_days, by = "day")
    observed <- daily[dates %in% full_window, index]
    nearby_calendar[index] <- length(full_window)
    nearby_valid[index] <- sum(is.finite(observed))
    nearby_near_peak[index] <- sum(
      is.finite(observed) &
        observed >= near_peak_fraction * daily_peak[index])
  }
  nearby_fraction <- nearby_near_peak / pmax(nearby_valid, 1L)
  difference <- abs(daily_peak - peak_values[selected])
  # These are review cues, not a validity mask or an assertion that a
  # solitary, brief peak is necessarily wrong.
  context <- ifelse(
    difference > 0.005 | nearby_valid < radius_days + 1L |
      nearby_fraction < 0.75 | as.integer(patch_count[as.character(patch)]) < 3L,
    "closer inspection", "spatial and temporal support")
  data.frame(
    cell = selected, longitude = xy[, 1L], latitude = xy[, 2L],
    patch_id = as.integer(patch),
    patch_cells = as.integer(patch_count[as.character(patch)]),
    map_peak_inches = peak_values[selected],
    daily_peak_inches = daily_peak,
    peak_date = as.character(dates[peak_index]),
    peak_difference_inches = difference,
    nearby_calendar_days = nearby_calendar,
    nearby_valid_days = nearby_valid,
    nearby_near_peak_days = nearby_near_peak,
    nearby_near_peak_fraction = nearby_fraction,
    context = context, stringsAsFactors = FALSE
  )
}

audit_snodas_seasonal_peaks <- function(
    water_year = 2017L,
    inventory_path = file.path("data", "diagnostics", "snodas-audit",
                               "monthly-directory-inventory.csv"),
    raw_dir = swc_paths$raw,
    processed_dir = swc_paths$processed,
    output_dir = file.path("data", "diagnostics", "snodas-seasonal-archive",
                           sprintf("wy%04d", water_year)),
    template = snodas_common_grid(),
    threshold_inches = 50, radius_days = 7L) {
  if (length(water_year) != 1L || !is.numeric(water_year) ||
      !is.finite(water_year) || water_year != floor(water_year) ||
      water_year < 2005L || water_year > 2025L) {
    stop("Choose a complete SNODAS water year from 2005-2025.",
         call. = FALSE)
  }
  peak_path <- file.path(output_dir, "peak_swe.tif")
  marker_path <- file.path(output_dir, "complete.csv")
  if (!file.exists(peak_path) || !file.exists(marker_path)) {
    stop("Build the complete seasonal archive year before auditing peaks.",
         call. = FALSE)
  }
  plan <- plan_snodas_cool_season(water_year, inventory_path, raw_dir)
  if (any(!snodas_cool_season_processed(plan, processed_dir)$complete)) {
    stop("SNODAS WY", water_year, " has unprocessed listed dates.",
         call. = FALSE)
  }
  inputs <- unlist(lapply(swc_snodas$variables, function(variable) {
    vapply(plan$date, snodas_processed_path, character(1),
           variable = variable, processed_dir = processed_dir)
  }), use.names = FALSE)
  source_md5 <- unname(tools::md5sum(inputs))
  if (anyNA(source_md5)) {
    stop("Could not checksum the seasonal source grids.", call. = FALSE)
  }
  signature <- snodas_seasonal_source_signature(
    plan$date, source_md5, template, water_year)
  marker <- tryCatch(utils::read.csv(marker_path, stringsAsFactors = FALSE),
                     error = function(e) NULL)
  if (is.null(marker) || nrow(marker) != 1L ||
      !all(c("source_signature", "peak_swe_md5") %in% names(marker)) ||
      !identical(marker$source_signature, signature) ||
      !identical(marker$peak_swe_md5,
                 unname(tools::md5sum(peak_path)))) {
    stop("The seasonal peak grid is not verified against current sources; ",
         "rebuild the archive year first.", call. = FALSE)
  }
  peak <- terra::rast(peak_path)
  if (!terra::compareGeom(peak, template, stopOnError = FALSE) ||
      terra::nlyr(peak) != 1L) {
    stop("Seasonal peak grid geometry does not match the common grid.",
         call. = FALSE)
  }
  read_day <- function(date) {
    swe <- terra::rast(snodas_processed_path(date, "swe", processed_dir))
    depth <- terra::rast(snodas_processed_path(date, "depth", processed_dir))
    if (length(terra::time(swe)) != 1L ||
        length(terra::time(depth)) != 1L ||
        is.na(terra::time(swe)) || is.na(terra::time(depth)) ||
        as.Date(terra::time(swe)) != date ||
        as.Date(terra::time(depth)) != date) {
      stop("SNODAS source date mismatch: ", date, call. = FALSE)
    }
    screened <- screen_snodas_analysis_pair(swe, depth)
    snodas_align_common_grid(screened$swe, template)
  }
  cells <- snodas_seasonal_peak_evidence(
    plan$date, peak, read_day, threshold_inches, radius_days)
  summary <- data.frame(
    water_year = water_year,
    source_signature = signature,
    peak_swe_md5 = marker$peak_swe_md5,
    threshold_inches = threshold_inches,
    radius_days = radius_days,
    near_peak_fraction = 0.75,
    dates_read = nrow(plan),
    high_peak_cells = nrow(cells),
    high_peak_patches = length(unique(cells$patch_id)),
    cells_for_closer_inspection = sum(cells$context == "closer inspection"),
    map_daily_mismatch_cells = sum(cells$peak_difference_inches > 0.005),
    stringsAsFactors = FALSE
  )
  cell_path <- file.path(output_dir, "peak-provenance-cells.csv")
  summary_path <- file.path(output_dir, "peak-provenance-summary.csv")
  utils::write.csv(cells, cell_path, row.names = FALSE)
  utils::write.csv(summary, summary_path, row.names = FALSE)
  list(summary = summary, cells = cells,
       paths = c(summary = summary_path, cells = cell_path))
}
