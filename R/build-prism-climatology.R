# Build day-of-year climatologies from processed daily PRISM rasters.

prism_calendar_keys <- function(include_feb29 = TRUE) {
  year <- if (include_feb29) 2000L else 2001L
  format(
    seq(as.Date(sprintf("%d-01-01", year)), as.Date(sprintf("%d-12-31", year)), by = "day"),
    "%m-%d"
  )
}

prism_climatology_manifest_path <- function(processed_dir = swc_paths$processed) {
  file.path(processed_dir, "prism", "climatology", "manifest.csv")
}

read_prism_daily_collection <- function(
    variable,
    baseline_start,
    baseline_end,
    aoi_id = swc_prism$aoi_id,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    require_complete = TRUE) {
  variable <- validate_prism_variables(variable)
  if (length(variable) != 1L) {
    stop("Exactly one PRISM variable is required.", call. = FALSE)
  }
  baseline_start <- as.Date(baseline_start)
  baseline_end <- as.Date(baseline_end)
  if (is.na(baseline_start) || is.na(baseline_end) || baseline_start > baseline_end) {
    stop("The climatology baseline must be a valid inclusive date range.", call. = FALSE)
  }

  required <- c(
    "product", "aoi_id", "variable", "native_units", "start_date", "end_date",
    "md5", "path"
  )
  missing <- setdiff(required, names(processed_manifest))
  if (length(missing) > 0L) {
    stop("Processed manifest is missing column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }

  selected <- processed_manifest[
    processed_manifest$product == "daily" &
      !is.na(processed_manifest$aoi_id) & processed_manifest$aoi_id == aoi_id &
      processed_manifest$variable == variable &
      processed_manifest$end_date >= baseline_start &
      processed_manifest$start_date <= baseline_end,
    , drop = FALSE
  ]
  selected <- selected[!duplicated(selected$path, fromLast = TRUE), , drop = FALSE]
  selected <- selected[order(selected$start_date), , drop = FALSE]
  if (nrow(selected) == 0L) {
    stop("No processed PRISM files overlap the requested climatology baseline.", call. = FALSE)
  }
  if (any(!file.exists(selected$path))) {
    stop("The processed manifest references one or more missing rasters.", call. = FALSE)
  }
  expected_unit <- unname(swc_prism$native_units[[variable]])
  if (any(selected$native_units != expected_unit)) {
    stop("Processed files do not consistently use the expected native units.", call. = FALSE)
  }

  rasters <- lapply(selected$path, read_prism_daily_raster, variable = variable)
  reference <- rasters[[1L]]
  if (length(rasters) > 1L) {
    for (index in 2:length(rasters)) {
      terra::compareGeom(reference, rasters[[index]], stopOnError = TRUE)
    }
  }
  raster <- do.call(c, rasters)
  dates <- as.Date(terra::time(raster))
  keep <- dates >= baseline_start & dates <= baseline_end
  raster <- raster[[which(keep)]]
  dates <- dates[keep]
  ordering <- order(dates)
  raster <- raster[[ordering]]
  dates <- dates[ordering]
  terra::time(raster) <- dates

  if (anyDuplicated(dates)) {
    stop("Processed PRISM inputs contain duplicate dates.", call. = FALSE)
  }
  if (require_complete) {
    expected_dates <- seq(baseline_start, baseline_end, by = "day")
    missing_dates <- setdiff(expected_dates, dates)
    if (length(missing_dates) > 0L) {
      stop(
        "Climatology baseline is incomplete; first missing date: ",
        format(min(missing_dates), "%Y-%m-%d"),
        call. = FALSE
      )
    }
  }

  signature_values <- paste(selected$path, selected$md5, sep = "=")
  list(
    raster = raster,
    dates = dates,
    sources = selected,
    source_signature = digest::digest(sort(signature_values), algo = "sha256")
  )
}

validate_prism_window <- function(window_days) {
  window_days <- as.integer(window_days)
  if (length(window_days) != 1L || is.na(window_days) || window_days < 1L || window_days %% 2L == 0L) {
    stop("`window_days` must be a positive odd integer.", call. = FALSE)
  }
  window_days
}

validate_prism_progress_every <- function(progress_every) {
  progress_every <- as.integer(progress_every)
  if (length(progress_every) != 1L || is.na(progress_every) || progress_every < 1L) {
    stop("`progress_every` must be a positive integer.", call. = FALSE)
  }
  progress_every
}

format_prism_elapsed <- function(seconds) {
  seconds <- max(0, as.numeric(seconds))
  hours <- floor(seconds / 3600)
  minutes <- floor((seconds %% 3600) / 60)
  remaining_seconds <- round(seconds %% 60)
  if (hours > 0) {
    return(sprintf("%dh %02dm %02ds", hours, minutes, remaining_seconds))
  }
  if (minutes > 0) {
    return(sprintf("%dm %02ds", minutes, remaining_seconds))
  }
  sprintf("%ds", remaining_seconds)
}

prism_statistic_method <- function(statistic, window_days = swc_prism$centered_window_days) {
  if (grepl("^wet_p(90|95|99)$", statistic)) {
    return("annual-wet-days")
  }
  sprintf("centered-%02dday", validate_prism_window(window_days))
}

prism_apply_daily_statistic <- function(
    raster,
    variable,
    statistic,
    quantile_type = swc_prism$quantile_type,
    wet_day_threshold = swc_prism$wet_day_threshold_inches) {
  if (statistic %in% c("p10", "p90") && variable == "pcpn") {
    stop("Precipitation percentiles must use an explicit wet-day statistic such as `wet_p90`.", call. = FALSE)
  }
  if (statistic == "wet_frequency" && variable != "pcpn") {
    stop("`wet_frequency` is only valid for precipitation.", call. = FALSE)
  }

  fun <- switch(
    statistic,
    mean = "mean",
    sd = "sd",
    median = "median",
    p10 = function(x, ...) {
      valid <- x[!is.na(x)]
      if (length(valid) == 0L) return(NA_real_)
      stats::quantile(valid, probs = 0.10, names = FALSE, type = quantile_type)
    },
    p90 = function(x, ...) {
      valid <- x[!is.na(x)]
      if (length(valid) == 0L) return(NA_real_)
      stats::quantile(valid, probs = 0.90, names = FALSE, type = quantile_type)
    },
    wet_frequency = function(x, ...) {
      valid <- x[!is.na(x)]
      if (length(valid) == 0L) return(NA_real_)
      mean(valid >= wet_day_threshold)
    },
    stop("Unsupported centered climatology statistic: ", statistic, call. = FALSE)
  )
  terra::app(raster, fun = fun, na.rm = TRUE)
}

prism_insert_feb29 <- function(raster, variable, statistic, keys) {
  feb28 <- match("02-28", keys)
  mar01 <- match("03-01", keys)
  if (is.na(feb28) || is.na(mar01)) {
    return(list(raster = raster, keys = keys))
  }

  feb29 <- (raster[[feb28]] + raster[[mar01]]) / 2
  layers <- c(
    lapply(seq_len(feb28), function(index) raster[[index]]),
    list(feb29),
    lapply(seq.int(mar01, terra::nlyr(raster)), function(index) raster[[index]])
  )
  result <- do.call(c, layers)
  result_keys <- append(keys, "02-29", after = feb28)
  names(result) <- paste(variable, statistic, result_keys, sep = "_")
  terra::time(result) <- as.Date(paste0("2000-", result_keys))
  list(raster = result, keys = result_keys)
}

prism_centered_daily_statistic <- function(
    raster,
    variable,
    statistic,
    window_days = swc_prism$centered_window_days,
    quantile_type = swc_prism$quantile_type,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    progress_every = 25L,
    quiet = FALSE) {
  window_days <- validate_prism_window(window_days)
  progress_every <- validate_prism_progress_every(progress_every)
  calendar <- prism_calendar_keys(include_feb29 = FALSE)
  input_index <- match(format(as.Date(terra::time(raster)), "%m-%d"), calendar)
  target_index <- sort(unique(input_index[!is.na(input_index)]))
  if (length(target_index) == 0L) {
    stop("No non-leap calendar days are available for the daily climatology.", call. = FALSE)
  }
  half_window <- (window_days - 1L) / 2L

  layers <- vector("list", length(target_index))
  for (position in seq_along(target_index)) {
    target <- target_index[[position]]
    distance <- abs(input_index - target)
    circular_distance <- pmin(distance, length(calendar) - distance)
    selected <- which(!is.na(circular_distance) & circular_distance <= half_window)
    layers[[position]] <- prism_apply_daily_statistic(
      raster[[selected]], variable, statistic,
      quantile_type = quantile_type,
      wet_day_threshold = wet_day_threshold
    )
    if (!quiet && (position %% progress_every == 0L || position == length(target_index))) {
      message(
        "  ", variable, " ", statistic, ": calendar day ", position, "/",
        length(target_index), " (", calendar[[target]], ")."
      )
    }
  }
  result <- do.call(c, layers)
  keys <- calendar[target_index]
  names(result) <- paste(variable, statistic, keys, sep = "_")
  terra::time(result) <- as.Date(paste0("2000-", keys))
  prism_insert_feb29(result, variable, statistic, keys)$raster
}

prism_wet_day_percentile <- function(
    raster,
    statistic,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    quantile_type = swc_prism$quantile_type) {
  probability <- switch(statistic, wet_p90 = 0.90, wet_p95 = 0.95, wet_p99 = 0.99, NA_real_)
  if (is.na(probability)) {
    stop("Unsupported wet-day percentile: ", statistic, call. = FALSE)
  }
  result <- terra::app(raster, fun = function(x, ...) {
    wet <- x[!is.na(x) & x >= wet_day_threshold]
    if (length(wet) == 0L) return(NA_real_)
    stats::quantile(wet, probs = probability, names = FALSE, type = quantile_type)
  })
  names(result) <- paste("pcpn", statistic, sep = "_")
  terra::time(result) <- as.Date("2000-01-01")
  result
}

prism_climatology_statistic <- function(
    raster,
    variable,
    statistic = "mean",
    window_days = swc_prism$centered_window_days,
    quantile_type = swc_prism$quantile_type,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    progress_every = 25L,
    quiet = FALSE) {
  temperature_statistics <- c("mean", "sd", "median", "p10", "p90")
  precipitation_statistics <- c(
    "mean", "sd", "median", "wet_frequency", "wet_p90", "wet_p95", "wet_p99"
  )
  supported <- if (variable == "pcpn") precipitation_statistics else temperature_statistics
  if (!(length(statistic) == 1L && statistic %in% supported)) {
    stop("Unsupported ", variable, " climatology statistic: ", statistic, call. = FALSE)
  }
  if (grepl("^wet_p", statistic)) {
    return(prism_wet_day_percentile(
      raster, statistic,
      wet_day_threshold = wet_day_threshold,
      quantile_type = quantile_type
    ))
  }
  prism_centered_daily_statistic(
    raster, variable, statistic,
    window_days = window_days,
    quantile_type = quantile_type,
    wet_day_threshold = wet_day_threshold,
    progress_every = progress_every,
    quiet = quiet
  )
}

prism_climatology_units <- function(variable, statistic) {
  if (statistic == "wet_frequency") {
    return("fraction")
  }
  unname(swc_prism$native_units[[variable]])
}

prism_climatology_path <- function(
    variable,
    statistic,
    baseline_start,
    baseline_end,
    method = prism_statistic_method(statistic),
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  baseline_label <- paste0(format(as.Date(baseline_start), "%Y%m%d"), "-", format(as.Date(baseline_end), "%Y%m%d"))
  file.path(
    processed_dir, "prism", aoi_id, "climatology", baseline_label,
    "daily", variable, method, paste0(statistic, ".tif")
  )
}

build_prism_daily_climatology <- function(
    variable,
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end,
    statistics = "mean",
    window_days = swc_prism$centered_window_days,
    quantile_type = swc_prism$quantile_type,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    manifest_path = prism_climatology_manifest_path(processed_dir),
    require_complete = TRUE,
    overwrite = FALSE,
    progress_every = 25L,
    quiet = FALSE) {
  variable <- validate_prism_variables(variable)
  statistics <- unique(as.character(statistics))
  progress_every <- validate_prism_progress_every(progress_every)
  collection_started <- proc.time()[["elapsed"]]
  if (!quiet) {
    message(
      "Loading ", variable, " daily inputs for ", format(as.Date(baseline_start)),
      " through ", format(as.Date(baseline_end)), "."
    )
  }
  collection <- read_prism_daily_collection(
    variable = variable,
    baseline_start = baseline_start,
    baseline_end = baseline_end,
    aoi_id = aoi_id,
    processed_manifest = processed_manifest,
    require_complete = require_complete
  )
  if (!quiet) {
    message(
      "Loaded ", terra::nlyr(collection$raster), " daily layers in ",
      format_prism_elapsed(proc.time()[["elapsed"]] - collection_started), "."
    )
  }

  records <- vector("list", length(statistics))
  for (index in seq_along(statistics)) {
    statistic <- statistics[[index]]
    method <- prism_statistic_method(statistic, window_days)
    path <- prism_climatology_path(
      variable, statistic, baseline_start, baseline_end,
      method = method,
      aoi_id = aoi_id, processed_dir = processed_dir
    )
    if (file.exists(path) && !overwrite) {
      stop("Climatology output already exists; set `overwrite = TRUE`: ", path, call. = FALSE)
    }
    statistic_started <- proc.time()[["elapsed"]]
    if (!quiet) message("Building ", variable, " daily ", statistic, " climatology.")
    result <- prism_climatology_statistic(
      collection$raster, variable, statistic,
      window_days = window_days,
      quantile_type = quantile_type,
      wet_day_threshold = wet_day_threshold,
      progress_every = progress_every,
      quiet = quiet
    )
    write_prism_processed_raster(result, path)
    if (!quiet) {
      message(
        "Completed ", variable, " daily ", statistic, " in ",
        format_prism_elapsed(proc.time()[["elapsed"]] - statistic_started), "."
      )
    }

    records[[index]] <- data.frame(
      product = "daily_climatology",
      aoi_id = aoi_id,
      variable = variable,
      statistic = statistic,
      method = method,
      units = prism_climatology_units(variable, statistic),
      window_days = if (method == "annual-wet-days") NA_integer_ else as.integer(window_days),
      quantile_type = if (grepl("p(10|90|95|99)$", statistic)) as.integer(quantile_type) else NA_integer_,
      wet_day_threshold_inches = if (variable == "pcpn") wet_day_threshold else NA_real_,
      start_date = as.Date(baseline_start),
      end_date = as.Date(baseline_end),
      source_signature = collection$source_signature,
      built_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
      bytes = file.info(path)$size,
      md5 = unname(tools::md5sum(path)),
      path = path,
      stringsAsFactors = FALSE
    )
    write_prism_manifest(records[[index]], manifest_path)
  }

  invisible(do.call(rbind, records))
}
