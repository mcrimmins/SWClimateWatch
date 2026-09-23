# Cache historical rolling temperature-threshold counts by calendar date.

prism_temperature_threshold_cache_version <- 1L

prism_temperature_threshold_cache_manifest_path <- function(
    processed_dir = swc_paths$processed) {
  file.path(processed_dir, "prism", "temperature-threshold-cache-manifest.csv")
}

prism_freeze_count_cache_path <- function(
    days,
    target_date,
    threshold_f = 32,
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  days <- as.integer(days)
  window_days <- validate_prism_window(window_days)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  target_date <- as.Date(target_date)
  threshold_label <- paste0(format(as.numeric(threshold_f), trim = TRUE), "F")
  baseline_label <- paste0(
    format(as.Date(baseline_start), "%Y%m%d"), "-",
    format(as.Date(baseline_end), "%Y%m%d")
  )
  file.path(
    processed_dir, "prism", aoi_id, "climatology", baseline_label,
    "rolling-samples", "mint", paste0("freeze-at-or-below-", threshold_label),
    paste0(sprintf("%03d", days), "day"),
    sprintf("centered-%02dday", window_days),
    paste0(format(target_date, "%m-%d"), ".tif")
  )
}

prism_temperature_threshold_source_signature <- function(
    selection,
    processed_manifest,
    threshold_f) {
  paths <- unique(selection$path)
  manifest <- processed_manifest[
    !duplicated(processed_manifest$path, fromLast = TRUE), , drop = FALSE
  ]
  rows <- match(paths, manifest$path)
  if (anyNA(rows)) {
    stop("One or more selected temperature sources are absent from the processed manifest.", call. = FALSE)
  }
  checksums <- manifest$md5[rows]
  missing <- is.na(checksums) | !nzchar(checksums)
  if (any(missing)) {
    if (any(!file.exists(paths[missing]))) {
      stop("Cannot checksum one or more missing temperature sources.", call. = FALSE)
    }
    checksums[missing] <- unname(tools::md5sum(paths[missing]))
  }
  digest::digest(
    c(
      paste0("threshold_f=", format(as.numeric(threshold_f), scientific = FALSE, trim = TRUE)),
      sort(paste(paths, checksums, sep = "="))
    ),
    algo = "sha256"
  )
}

read_prism_freeze_count_cache <- function(path, expected_end_dates = NULL) {
  if (!file.exists(path)) stop("Freeze-count cache does not exist: ", path, call. = FALSE)
  raster <- terra::rast(path)
  dates <- as.Date(terra::time(raster))
  if (length(dates) != terra::nlyr(raster) || anyNA(dates) || anyDuplicated(dates)) {
    stop("Freeze-count cache must have one unique valid date per layer: ", path, call. = FALSE)
  }
  if (!is.null(expected_end_dates)) {
    expected_end_dates <- sort(unique(as.Date(expected_end_dates)))
    if (length(dates) != length(expected_end_dates) || any(dates != expected_end_dates)) {
      stop("Freeze-count cache dates do not match the requested reference sample.", call. = FALSE)
    }
  }
  raster
}

prism_rolling_counts_for_end_dates <- function(
    indicator,
    dates,
    end_dates,
    days,
    progress_every = 25L,
    quiet = FALSE) {
  dates <- as.Date(dates)
  end_dates <- sort(unique(as.Date(end_dates)))
  days <- as.integer(days)
  progress_every <- validate_prism_progress_every(progress_every)
  if (terra::nlyr(indicator) != length(dates) || anyNA(dates) || anyDuplicated(dates)) {
    stop("The indicator raster must have one unique valid date per layer.", call. = FALSE)
  }
  started <- proc.time()[["elapsed"]]
  layers <- vector("list", length(end_dates))
  for (index in seq_along(end_dates)) {
    current_end <- end_dates[[index]]
    if (index > 1L && current_end == end_dates[[index - 1L]] + 1L) {
      outgoing <- match(current_end - days, dates)
      incoming <- match(current_end, dates)
      if (is.na(outgoing) || is.na(incoming)) {
        stop("Rolling threshold-count input is incomplete near ", current_end, ".", call. = FALSE)
      }
      layers[[index]] <- layers[[index - 1L]] - indicator[[outgoing]] + indicator[[incoming]]
    } else {
      needed <- seq(current_end - days + 1L, current_end, by = "day")
      selected <- match(needed, dates)
      if (anyNA(selected)) {
        stop(
          "Rolling threshold-count input is incomplete; first missing date: ",
          format(needed[which(is.na(selected))[[1L]]]),
          call. = FALSE
        )
      }
      layers[[index]] <- if (days == 1L) {
        indicator[[selected]]
      } else {
        terra::app(indicator[[selected]], sum, na.rm = FALSE)
      }
    }
    if (!quiet && (index %% progress_every == 0L || index == length(end_dates))) {
      message(
        "  Freeze-count reference periods: ", index, "/", length(end_dates),
        " (", format_prism_elapsed(proc.time()[["elapsed"]] - started), ")."
      )
    }
  }
  result <- do.call(c, layers)
  terra::time(result) <- end_dates
  names(result) <- paste0("mint_freeze_count_", sprintf("%03d", days), "day_", end_dates)
  result
}

build_prism_freeze_count_cache <- function(
    days = 30L,
    target_date,
    threshold_f = 32,
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    manifest_path = prism_temperature_threshold_cache_manifest_path(processed_dir),
    overwrite = FALSE,
    progress_every = 25L,
    quiet = FALSE) {
  days <- as.integer(days)
  target_date <- as.Date(target_date)
  window_days <- validate_prism_window(window_days)
  reference_groups <- prism_reference_window_dates(
    target_date, baseline_start, baseline_end, window_days
  )
  reference_end_dates <- sort(unique(do.call(c, reference_groups)))
  source_dates <- prism_rolling_source_dates(reference_end_dates, days)
  selection <- select_prism_daily_sources(
    "mint", source_dates, aoi_id, processed_manifest
  )
  source_signature <- prism_temperature_threshold_source_signature(
    selection, processed_manifest, threshold_f
  )
  path <- prism_freeze_count_cache_path(
    days, target_date, threshold_f, baseline_start, baseline_end,
    window_days, aoi_id, processed_dir
  )

  cache_manifest <- read_prism_manifest(manifest_path)
  existing <- if (nrow(cache_manifest) > 0L &&
      all(c("path", "source_signature") %in% names(cache_manifest))) {
    cache_manifest[cache_manifest$path == path, , drop = FALSE]
  } else {
    data.frame()
  }
  version_current <- nrow(existing) > 0L &&
    "cache_version" %in% names(existing) &&
    identical(
      as.integer(tail(existing$cache_version, 1L)),
      prism_temperature_threshold_cache_version
    )
  current <- file.exists(path) && version_current &&
    identical(tail(existing$source_signature, 1L), source_signature)
  if (current && !overwrite) {
    if (!quiet) message("Using current freeze-count cache for ", format(target_date, "%m-%d"), ".")
    return(invisible(list(
      raster = read_prism_freeze_count_cache(path, reference_end_dates),
      groups = reference_groups,
      path = path,
      source_signature = source_signature,
      refreshed = FALSE
    )))
  }

  if (!quiet) {
    message(
      "Building ", days, "-day freeze-count cache for ",
      format(target_date, "%m-%d"), " from ", length(source_dates),
      " daily minimum-temperature layers."
    )
  }
  collection <- read_prism_best_daily_range(
    "mint", source_dates, aoi_id, processed_manifest
  )
  indicator <- collection$raster <= threshold_f
  counts <- prism_rolling_counts_for_end_dates(
    indicator, collection$dates, reference_end_dates, days,
    progress_every, quiet
  )
  write_prism_processed_raster(counts, path, datatype = "FLT4S")

  record <- data.frame(
    product = "rolling_temperature_threshold_count_sample",
    cache_version = prism_temperature_threshold_cache_version,
    aoi_id = aoi_id,
    variable = "mint",
    native_units = "day_count",
    storage_datatype = "FLT4S",
    threshold_f = threshold_f,
    comparison = "at_or_below",
    rolling_days = days,
    target_calendar_day = format(target_date, "%m-%d"),
    method = sprintf("centered-%02dday", window_days),
    window_days = window_days,
    start_date = as.Date(baseline_start),
    end_date = as.Date(baseline_end),
    sample_layers = terra::nlyr(counts),
    source_signature = source_signature,
    built_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    bytes = file.info(path)$size,
    md5 = unname(tools::md5sum(path)),
    path = path,
    stringsAsFactors = FALSE
  )
  write_prism_manifest(record, manifest_path)
  if (!quiet) message("Wrote freeze-count cache: ", path)
  invisible(list(
    raster = read_prism_freeze_count_cache(path, reference_end_dates),
    groups = reference_groups,
    path = path,
    source_signature = source_signature,
    refreshed = TRUE
  ))
}
