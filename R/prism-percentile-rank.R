# Calculate current temperature percentile ranks from a local PRISM baseline.

prism_reference_window_dates <- function(
    current_date,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days) {
  current_date <- as.Date(current_date)
  baseline_start <- as.Date(baseline_start)
  baseline_end <- as.Date(baseline_end)
  window_days <- validate_prism_window(window_days)
  if (length(current_date) != 1L || is.na(current_date)) {
    stop("`current_date` must be one valid date.", call. = FALSE)
  }
  if (is.na(baseline_start) || is.na(baseline_end) || baseline_start > baseline_end) {
    stop("The percentile baseline must be a valid inclusive date range.", call. = FALSE)
  }

  calendar <- prism_calendar_keys(include_feb29 = FALSE)
  current_key <- format(current_date, "%m-%d")
  targets <- if (current_key == "02-29") {
    match(c("02-28", "03-01"), calendar)
  } else {
    match(current_key, calendar)
  }
  if (anyNA(targets)) {
    stop("Could not map the current date to the reference calendar.", call. = FALSE)
  }

  dates <- seq(baseline_start, baseline_end, by = "day")
  input_index <- match(format(dates, "%m-%d"), calendar)
  half_window <- (window_days - 1L) / 2L
  lapply(targets, function(target) {
    distance <- abs(input_index - target)
    circular_distance <- pmin(distance, length(calendar) - distance)
    dates[!is.na(circular_distance) & circular_distance <= half_window]
  })
}

read_prism_daily_subset <- function(
    variable,
    dates,
    aoi_id = swc_prism$aoi_id,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    require_complete = TRUE) {
  variable <- validate_prism_variables(variable)
  if (length(variable) != 1L) {
    stop("Exactly one PRISM variable is required.", call. = FALSE)
  }
  dates <- sort(unique(as.Date(dates)))
  if (length(dates) == 0L || anyNA(dates)) {
    stop("`dates` must contain at least one valid date.", call. = FALSE)
  }

  required <- c(
    "product", "aoi_id", "variable", "native_units", "start_date", "end_date",
    "md5", "path"
  )
  missing <- setdiff(required, names(processed_manifest))
  if (length(missing) > 0L) {
    stop("Processed manifest is missing column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
  eligible <- processed_manifest[
    processed_manifest$product == "daily" &
      !is.na(processed_manifest$aoi_id) & processed_manifest$aoi_id == aoi_id &
      processed_manifest$variable == variable,
    , drop = FALSE
  ]
  needed <- vapply(seq_len(nrow(eligible)), function(index) {
    any(dates >= eligible$start_date[[index]] & dates <= eligible$end_date[[index]])
  }, logical(1))
  selected <- eligible[needed, , drop = FALSE]
  selected <- selected[!duplicated(selected$path, fromLast = TRUE), , drop = FALSE]
  selected <- selected[order(selected$start_date), , drop = FALSE]
  if (nrow(selected) == 0L) {
    stop("No processed PRISM files contain the requested reference dates.", call. = FALSE)
  }
  if (any(!file.exists(selected$path))) {
    stop("The processed manifest references one or more missing rasters.", call. = FALSE)
  }
  expected_unit <- unname(swc_prism$native_units[[variable]])
  if (any(selected$native_units != expected_unit)) {
    stop("Processed files do not consistently use the expected native units.", call. = FALSE)
  }

  rasters <- lapply(selected$path, function(path) {
    source <- read_prism_daily_raster(path, variable, validate_values = FALSE)
    source_dates <- as.Date(terra::time(source))
    source[[which(source_dates %in% dates)]]
  })
  rasters <- rasters[vapply(rasters, terra::nlyr, numeric(1)) > 0L]
  reference <- rasters[[1L]]
  if (length(rasters) > 1L) {
    for (index in 2:length(rasters)) {
      terra::compareGeom(reference, rasters[[index]], stopOnError = TRUE)
    }
  }
  raster <- do.call(c, rasters)
  raster_dates <- as.Date(terra::time(raster))
  ordering <- order(raster_dates)
  raster <- raster[[ordering]]
  raster_dates <- raster_dates[ordering]
  terra::time(raster) <- raster_dates
  if (anyDuplicated(raster_dates)) {
    stop("Processed PRISM reference inputs contain duplicate dates.", call. = FALSE)
  }
  if (require_complete) {
    missing_dates <- setdiff(dates, raster_dates)
    if (length(missing_dates) > 0L) {
      stop(
        "Percentile reference window is incomplete; first missing date: ",
        format(min(missing_dates), "%Y-%m-%d"),
        call. = FALSE
      )
    }
  }

  list(raster = raster, dates = raster_dates, sources = selected)
}

prism_mean_temperature_raster <- function(maxt, mint, dates = NULL) {
  terra::compareGeom(maxt, mint, stopOnError = TRUE)
  if (terra::nlyr(maxt) != terra::nlyr(mint)) {
    stop("Maximum and minimum temperature rasters must have the same number of layers.", call. = FALSE)
  }
  maxt_dates <- as.Date(terra::time(maxt))
  mint_dates <- as.Date(terra::time(mint))
  if (length(maxt_dates) != terra::nlyr(maxt) || anyNA(maxt_dates) ||
      length(mint_dates) != length(maxt_dates) || anyNA(mint_dates) ||
      any(maxt_dates != mint_dates)) {
    stop("Maximum and minimum temperature rasters must have identical valid dates.", call. = FALSE)
  }
  if (is.null(dates)) dates <- maxt_dates
  dates <- as.Date(dates)
  if (length(dates) != length(maxt_dates) || anyNA(dates) ||
      any(dates != maxt_dates)) {
    stop("Supplied mean-temperature dates do not match the raster layers.", call. = FALSE)
  }
  result <- (maxt + mint) / 2
  names(result) <- paste("tmean", format(dates), sep = "_")
  terra::time(result) <- dates
  validate_prism_native_values(result, "tmean")
  result
}

read_prism_temperature_subset <- function(
    variable,
    dates,
    aoi_id = swc_prism$aoi_id,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    require_complete = TRUE) {
  variable <- validate_prism_temperature_variables(variable)
  if (length(variable) != 1L) {
    stop("Exactly one PRISM temperature variable is required.", call. = FALSE)
  }
  if (variable != "tmean") {
    return(read_prism_daily_subset(
      variable, dates, aoi_id, processed_manifest, require_complete
    ))
  }
  maxt <- read_prism_daily_subset(
    "maxt", dates, aoi_id, processed_manifest, require_complete
  )
  mint <- read_prism_daily_subset(
    "mint", dates, aoi_id, processed_manifest, require_complete
  )
  if (!identical(maxt$dates, mint$dates)) {
    stop("Maximum and minimum temperature reference dates do not match.", call. = FALSE)
  }
  list(
    raster = prism_mean_temperature_raster(maxt$raster, mint$raster, maxt$dates),
    dates = maxt$dates,
    sources = rbind(maxt$sources, mint$sources)
  )
}

prism_type8_percentile_rank <- function(current, baseline) {
  if (length(current) != 1L || is.na(current)) return(NA_real_)
  baseline <- sort(baseline[!is.na(baseline)])
  n <- length(baseline)
  if (n == 0L) return(NA_real_)
  if (current < baseline[[1L]]) return(0)
  if (current > baseline[[n]]) return(100)

  equal <- which(baseline == current)
  if (length(equal) > 0L) {
    h <- mean(equal)
  } else {
    lower <- max(which(baseline < current))
    fraction <- (current - baseline[[lower]]) /
      (baseline[[lower + 1L]] - baseline[[lower]])
    h <- lower + fraction
  }
  probability <- (h - 1 / 3) / (n + 1 / 3)
  100 * min(1, max(0, probability))
}

prism_percentile_rank_raster <- function(current_raster, baseline_raster, variable, current_date) {
  if (length(variable) == 1L && identical(as.character(variable), "pcpn")) {
    stop(
      "Daily precipitation ranks use accumulation-based percentile methods.",
      call. = FALSE
    )
  }
  variable <- validate_prism_temperature_variables(variable)
  if (length(variable) != 1L) {
    stop("Exactly one PRISM variable is required.", call. = FALSE)
  }
  if (terra::nlyr(current_raster) != 1L) {
    stop("The current raster must contain exactly one layer.", call. = FALSE)
  }
  terra::compareGeom(current_raster, baseline_raster, stopOnError = TRUE)
  result <- terra::app(c(current_raster, baseline_raster), fun = function(x, ...) {
    prism_type8_percentile_rank(x[[1L]], x[-1L])
  })
  current_date <- as.Date(current_date)
  names(result) <- paste(variable, "percentile_rank", format(current_date), sep = "_")
  terra::time(result) <- current_date
  result
}

select_prism_current_layer <- function(current, variable, current_date = NULL) {
  variable <- validate_prism_temperature_variables(variable)
  raster <- if (is.character(current) && length(current) == 1L && variable != "tmean") {
    read_prism_daily_raster(current, variable)
  } else if (is.character(current) && length(current) == 1L) {
    if (!file.exists(current)) stop("PRISM raster does not exist: ", current, call. = FALSE)
    terra::rast(current)
  } else if (inherits(current, "SpatRaster")) {
    current
  } else {
    stop("`current` must be a PRISM raster path or SpatRaster.", call. = FALSE)
  }
  dates <- tryCatch(as.Date(terra::time(raster)), error = function(error) as.Date(character()))
  if (is.null(current_date)) {
    if (terra::nlyr(raster) != 1L || length(dates) != 1L || is.na(dates)) {
      stop("Supply `current_date` when the current raster is not one dated layer.", call. = FALSE)
    }
    current_date <- dates
  } else {
    current_date <- as.Date(current_date)
    if (length(current_date) != 1L || is.na(current_date)) {
      stop("`current_date` must be one valid date.", call. = FALSE)
    }
  }
  if (terra::nlyr(raster) > 1L) {
    selected <- which(dates == current_date)
    if (length(selected) != 1L) {
      stop("The current raster does not contain exactly one layer for `current_date`.", call. = FALSE)
    }
    raster <- raster[[selected]]
  }
  validate_prism_native_values(raster, variable)
  terra::time(raster) <- current_date
  list(raster = raster, date = current_date)
}

calculate_prism_percentile_rank <- function(
    current,
    variable,
    current_date = NULL,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    output_path = NULL,
    overwrite = FALSE,
    quiet = FALSE) {
  variable <- validate_prism_temperature_variables(variable)
  if (length(variable) != 1L) {
    stop("Exactly one PRISM variable is required.", call. = FALSE)
  }
  selected_current <- select_prism_current_layer(current, variable, current_date)
  reference_dates <- prism_reference_window_dates(
    selected_current$date, baseline_start, baseline_end, window_days
  )
  requested_dates <- sort(unique(do.call(c, reference_dates)))
  if (!quiet) {
    message(
      "Loading ", length(requested_dates), " ", variable,
      " baseline days for percentile rank."
    )
  }
  collection <- read_prism_temperature_subset(
    variable = variable,
    dates = requested_dates,
    aoi_id = aoi_id,
    processed_manifest = processed_manifest,
    require_complete = TRUE
  )

  ranks <- lapply(reference_dates, function(dates) {
    selected <- which(collection$dates %in% dates)
    prism_percentile_rank_raster(
      selected_current$raster,
      collection$raster[[selected]],
      variable,
      selected_current$date
    )
  })
  result <- if (length(ranks) == 1L) {
    ranks[[1L]]
  } else {
    Reduce(`+`, ranks) / length(ranks)
  }
  names(result) <- paste(variable, "percentile_rank", format(selected_current$date), sep = "_")
  terra::time(result) <- selected_current$date

  if (!is.null(output_path)) {
    if (file.exists(output_path) && !overwrite) {
      stop("Percentile-rank output already exists; set `overwrite = TRUE`: ", output_path, call. = FALSE)
    }
    write_prism_processed_raster(result, output_path)
    if (!quiet) message("Wrote percentile-rank raster: ", output_path)
  }
  result
}
