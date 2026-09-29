# Read-only relative-anomaly discovery on completed SNODAS seasonal peak maps.
# Published peak maps are never modified; documented masks are restored only
# in memory after verification against the original processed daily grids.

snodas_relative_peak_candidates <- function(
    peak, minimum_inches = 10, contrast_inches = 10,
    contrast_ratio = 1.5) {
  if (!inherits(peak, "SpatRaster") || terra::nlyr(peak) != 1L ||
      length(minimum_inches) != 1L || !is.numeric(minimum_inches) ||
      !is.finite(minimum_inches) || minimum_inches <= 0 ||
      length(contrast_inches) != 1L || !is.numeric(contrast_inches) ||
      !is.finite(contrast_inches) || contrast_inches <= 0 ||
      length(contrast_ratio) != 1L || !is.numeric(contrast_ratio) ||
      !is.finite(contrast_ratio) || contrast_ratio <= 1) {
    stop("Invalid SNODAS relative-peak inputs.", call. = FALSE)
  }
  values <- terra::values(peak, mat = FALSE)
  # An NA center weight excludes the focal cell. This is the median of the
  # eight *other* cells, not a center-inclusive approximation.
  neighbor_window <- matrix(1, 3L, 3L)
  neighbor_window[2L, 2L] <- NA_real_
  focal_median <- terra::values(
    terra::focal(peak, w = neighbor_window, fun = "median",
                 na.rm = TRUE),
    mat = FALSE)
  possible <- which(is.finite(values) & is.finite(focal_median) &
                      values >= minimum_inches &
                      values >= focal_median + contrast_inches &
                      values >= focal_median * contrast_ratio)
  empty <- data.frame(
    cell = integer(), longitude = numeric(), latitude = numeric(),
    peak_swe_inches = numeric(), neighbor_count = integer(),
    neighbor_median_inches = numeric(),
    above_neighbor_median_inches = numeric(),
    peak_to_neighbor_median = numeric(),
    patch_id = integer(), patch_cells = integer())
  if (!length(possible)) return(empty)
  context <- snodas_peak_neighbor_context(
    values, possible, terra::nrow(peak), terra::ncol(peak),
    contrast_inches = contrast_inches, contrast_ratio = contrast_ratio)
  context <- context[context$sharp_local_contrast, , drop = FALSE]
  if (!nrow(context)) return(empty)
  cells <- context$cell
  mask_values <- rep(NA_real_, terra::ncell(peak))
  mask_values[cells] <- 1
  patch <- terra::values(terra::patches(
    terra::setValues(peak, mask_values), directions = 8),
    mat = FALSE)[cells]
  patch_count <- table(patch)
  xy <- terra::xyFromCell(peak, cells)
  data.frame(
    cell = cells, longitude = xy[, 1L], latitude = xy[, 2L],
    peak_swe_inches = values[cells],
    neighbor_count = context$neighbor_count,
    neighbor_median_inches = context$neighbor_median_inches,
    above_neighbor_median_inches =
      context$above_neighbor_median_inches,
    peak_to_neighbor_median = context$peak_to_neighbor_median,
    patch_id = as.integer(patch),
    patch_cells = as.integer(patch_count[as.character(patch)]))
}

snodas_relative_source_peak <- function(
    water_year, point, processed_dir = swc_paths$processed) {
  dates <- seq(as.Date(sprintf("%d-10-01", water_year - 1L)),
               as.Date(sprintf("%d-05-31", water_year)), by = "day")
  swe <- rep(NA_real_, length(dates))
  depth <- rep(NA_real_, length(dates))
  for (i in seq_along(dates)) {
    swe_path <- snodas_processed_path(dates[i], "swe", processed_dir)
    depth_path <- snodas_processed_path(dates[i], "depth", processed_dir)
    if (!file.exists(swe_path) || !file.exists(depth_path)) next
    grids <- tryCatch(
      list(swe = terra::rast(swe_path), depth = terra::rast(depth_path)),
      error = function(e) NULL)
    if (is.null(grids) ||
        !terra::compareGeom(grids$swe, grids$depth,
                            stopOnError = FALSE) ||
        length(terra::time(grids$swe)) != 1L ||
        length(terra::time(grids$depth)) != 1L ||
        is.na(terra::time(grids$swe)) ||
        is.na(terra::time(grids$depth)) ||
        as.Date(terra::time(grids$swe)) != dates[i] ||
        as.Date(terra::time(grids$depth)) != dates[i]) next
    swe_at_point <- terra::extract(grids$swe, point)
    depth_at_point <- terra::extract(grids$depth, point)
    swe[i] <- as.numeric(swe_at_point[1L, ncol(swe_at_point)])
    depth[i] <- as.numeric(depth_at_point[1L, ncol(depth_at_point)])
  }
  valid <- is.finite(swe) & is.finite(depth) & swe >= 0 & depth >= 0 &
    swe <= depth + 1e-6 & swe < 32767 / 25.4 &
    depth < 32767 / 25.4
  if (!any(valid)) {
    return(data.frame(source_peak_inches = NA_real_,
                      source_peak_date = NA_character_,
                      source_depth_inches = NA_real_,
                      valid_days = 0L))
  }
  maximum <- max(swe[valid])
  index <- which(valid & swe == maximum)[1L]
  data.frame(source_peak_inches = maximum,
             source_peak_date = as.character(dates[index]),
             source_depth_inches = depth[index],
             valid_days = sum(valid))
}

build_snodas_relative_qc_pilot <- function(
    years = 2005:2025,
    archive_dir = file.path("data", "diagnostics", "snodas-seasonal-archive"),
    output_dir = file.path("data", "diagnostics", "snodas-relative-qc-pilot"),
    processed_dir = swc_paths$processed) {
  review <- build_snodas_seasonal_review_queue(
    years, archive_dir, file.path(output_dir, "review-queue"))
  details <- vector("list", nrow(review$years))
  benchmarks <- vector("list", nrow(review$years))
  summary <- review$years[, c("water_year", "archive_state")]
  summary$relative_candidates <- NA_integer_
  summary$relative_candidates_under_50in <- NA_integer_
  summary$relative_patches <- NA_integer_
  summary$known_masks_detected <- NA_integer_
  for (i in seq_len(nrow(summary))) {
    year <- summary$water_year[i]
    if (summary$archive_state[i] != "OUTPUTS_VERIFIED") next
    peak <- terra::rast(file.path(archive_dir,
                                  sprintf("wy%04d", year),
                                  "peak_swe.tif"))
    values <- terra::values(peak, mat = FALSE)
    rules <- snodas_seasonal_peak_qc_rules(year)
    if (nrow(rules)) {
      checks <- vector("list", nrow(rules))
      for (j in seq_len(nrow(rules))) {
        point <- matrix(c(rules$longitude[j], rules$latitude[j]),
                        ncol = 2L)
        cell <- terra::cellFromXY(peak, point)
        if (length(cell) != 1L || is.na(cell) ||
            !is.na(values[cell]) ||
            any(abs(terra::xyFromCell(peak, cell) - point) > 1e-4)) {
          stop("Documented SNODAS mask is not at its expected cell: ",
               rules$rule_id[j], call. = FALSE)
        }
        source <- snodas_relative_source_peak(year, point, processed_dir)
        matched <- is.finite(source$source_peak_inches) &&
          abs(source$source_peak_inches -
                rules$expected_peak_inches[j]) <=
          rules$tolerance_inches[j]
        if (matched) values[cell] <- source$source_peak_inches
        checks[[j]] <- data.frame(
          water_year = year, rule_id = rules$rule_id[j], cell = cell,
          expected_peak_inches = rules$expected_peak_inches[j],
          source_peak_inches = source$source_peak_inches,
          source_peak_date = source$source_peak_date,
          source_depth_inches = source$source_depth_inches,
          source_valid_days = source$valid_days,
          source_matched = matched)
      }
      benchmarks[[i]] <- do.call(rbind, checks)
    }
    discovered <- snodas_relative_peak_candidates(
      terra::setValues(peak, values))
    if (nrow(discovered)) {
      discovered$water_year <- year
      discovered$documented_mask_benchmark <-
        if (is.null(benchmarks[[i]])) rep(FALSE, nrow(discovered)) else
          discovered$cell %in% benchmarks[[i]]$cell
      details[[i]] <- discovered
    }
    if (!is.null(benchmarks[[i]])) {
      benchmarks[[i]]$relative_detected <-
        benchmarks[[i]]$source_matched &
        benchmarks[[i]]$cell %in% discovered$cell
      summary$known_masks_detected[i] <-
        sum(benchmarks[[i]]$relative_detected)
    } else summary$known_masks_detected[i] <- 0L
    summary$relative_candidates[i] <- nrow(discovered)
    summary$relative_candidates_under_50in[i] <-
      sum(discovered$peak_swe_inches < 50)
    summary$relative_patches[i] <- length(unique(discovered$patch_id))
    message(sprintf("SNODAS relative QC: WY%d, %d candidates (%d under 50 in).",
                    year, nrow(discovered),
                    summary$relative_candidates_under_50in[i]))
  }
  candidates <- if (any(lengths(details))) {
    do.call(rbind, details[lengths(details) > 0L])
  } else data.frame()
  benchmark <- if (any(lengths(benchmarks))) {
    do.call(rbind, benchmarks[lengths(benchmarks) > 0L])
  } else data.frame()
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c(summary = file.path(output_dir, "year-summary.csv"),
             candidates = file.path(output_dir, "relative-candidates.csv"),
             benchmarks = file.path(output_dir, "known-mask-benchmarks.csv"))
  utils::write.csv(summary, paths[["summary"]], row.names = FALSE)
  utils::write.csv(candidates, paths[["candidates"]], row.names = FALSE)
  utils::write.csv(benchmark, paths[["benchmarks"]], row.names = FALSE)
  message("SNODAS relative QC pilot complete; no saved grid or QC status changed.")
  list(summary = summary, candidates = candidates,
       benchmarks = benchmark, paths = paths)
}
