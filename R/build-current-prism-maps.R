# Build current PRISM temperature value, departure, and percentile-rank maps.

latest_common_prism_date <- function(
    variables = swc_prism$temperature_variables,
    aoi_id = swc_prism$aoi_id,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path())) {
  variables <- validate_prism_analysis_variables(variables)
  source_variables <- unique(unlist(lapply(variables, function(variable) {
    if (variable == "tmean") c("maxt", "mint") else variable
  })))
  required <- c("product", "aoi_id", "variable", "start_date", "end_date", "path")
  missing <- setdiff(required, names(processed_manifest))
  if (length(missing) > 0L) {
    stop("Processed manifest is missing column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
  recent <- processed_manifest[
    processed_manifest$product == "daily" &
      !is.na(processed_manifest$aoi_id) & processed_manifest$aoi_id == aoi_id &
      processed_manifest$variable %in% source_variables &
      processed_manifest$start_date == processed_manifest$end_date &
      grepl("[\\\\/]daily[\\\\/]recent[\\\\/]", processed_manifest$path),
    , drop = FALSE
  ]
  dates_by_variable <- lapply(source_variables, function(variable) {
    as.integer(unique(recent$end_date[recent$variable == variable]))
  })
  if (any(lengths(dates_by_variable) == 0L)) {
    stop("No common recent PRISM date is available for all requested variables.", call. = FALSE)
  }
  common <- Reduce(intersect, dates_by_variable)
  if (length(common) == 0L) {
    stop("No common recent PRISM date is available for all requested variables.", call. = FALSE)
  }
  as.Date(max(common), origin = "1970-01-01")
}

prism_recent_processed_path <- function(
    variable,
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  variable <- validate_prism_variables(variable)
  if (length(variable) != 1L) stop("Exactly one PRISM variable is required.", call. = FALSE)
  file.path(
    processed_dir, "prism", aoi_id, "daily", "recent", variable,
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_current_temperature_raster <- function(
    variable,
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  variable <- validate_prism_temperature_variables(variable)
  if (length(variable) != 1L) stop("Exactly one temperature variable is required.", call. = FALSE)
  date <- as.Date(date)
  if (variable == "tmean") {
    maxt <- prism_current_temperature_raster("maxt", date, aoi_id, processed_dir)
    mint <- prism_current_temperature_raster("mint", date, aoi_id, processed_dir)
    return(prism_mean_temperature_raster(maxt, mint, date))
  }
  path <- prism_recent_processed_path(variable, date, aoi_id, processed_dir)
  if (!file.exists(path)) {
    stop("Current processed PRISM raster is missing: ", path, call. = FALSE)
  }
  read_prism_daily_raster(path, variable)
}

prism_temperature_derived_output_path <- function(
    variable,
    product = c("value", "departure"),
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  variable <- validate_prism_temperature_variables(variable)
  product <- match.arg(product)
  if (length(variable) != 1L) stop("Exactly one temperature variable is required.", call. = FALSE)
  file.path(
    processed_dir, "prism", aoi_id, "daily", product, variable,
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_temperature_map_path <- function(
    variable,
    product = c("value", "departure"),
    date = NULL,
    maps_dir = swc_paths$maps) {
  variable <- validate_prism_temperature_variables(variable)
  product <- match.arg(product)
  if (length(variable) != 1L) stop("Exactly one temperature variable is required.", call. = FALSE)
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "temperature",
    paste(variable, product, suffix, sep = "-") |> paste0(".png")
  )
}

prism_temperature_rolling_departure_output_path <- function(
    variable,
    days,
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  variable <- validate_prism_temperature_variables(variable)
  days <- as.integer(days)
  if (length(variable) != 1L) stop("Exactly one temperature variable is required.", call. = FALSE)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  file.path(
    processed_dir, "prism", aoi_id, "daily", "rolling-departure", variable,
    paste0(sprintf("%03d", days), "day"),
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_temperature_rolling_departure_map_path <- function(
    variable,
    days,
    date = NULL,
    maps_dir = swc_paths$maps) {
  variable <- validate_prism_temperature_variables(variable)
  days <- as.integer(days)
  if (length(variable) != 1L) stop("Exactly one temperature variable is required.", call. = FALSE)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "temperature",
    paste0(variable, "-departure-", days, "day-", suffix, ".png")
  )
}

prism_temperature_extreme_frequency_output_path <- function(
    variable,
    statistic,
    days,
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    comparison = c("above", "below")) {
  variable <- validate_prism_temperature_variables(variable)
  statistic <- match.arg(statistic, c("p10", "p90"))
  comparison <- match.arg(comparison)
  days <- as.integer(days)
  if (length(variable) != 1L || variable == "tmean") {
    stop("Extreme-frequency thresholds require one downloaded temperature variable: `maxt` or `mint`.", call. = FALSE)
  }
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  file.path(
    processed_dir, "prism", aoi_id, "daily", "extreme-frequency", variable,
    paste0(comparison, "-", statistic), paste0(sprintf("%03d", days), "day"),
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_temperature_extreme_frequency_map_path <- function(
    variable,
    statistic,
    days,
    date = NULL,
    maps_dir = swc_paths$maps,
    comparison = c("above", "below")) {
  variable <- validate_prism_temperature_variables(variable)
  statistic <- match.arg(statistic, c("p10", "p90"))
  comparison <- match.arg(comparison)
  days <- as.integer(days)
  if (length(variable) != 1L || variable == "tmean") {
    stop("Extreme-frequency thresholds require one downloaded temperature variable: `maxt` or `mint`.", call. = FALSE)
  }
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "temperature",
    paste0(variable, "-", comparison, "-", statistic, "-count-", days, "day-", suffix, ".png")
  )
}

prism_freeze_day_count_output_path <- function(
    days,
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  days <- as.integer(days)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  file.path(
    processed_dir, "prism", aoi_id, "daily", "threshold-count", "mint",
    "at-or-below-32F", paste0(sprintf("%03d", days), "day"),
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_freeze_day_count_map_path <- function(
    days,
    date = NULL,
    maps_dir = swc_paths$maps) {
  days <- as.integer(days)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "temperature",
    paste0("mint-freeze-day-count-", days, "day-", suffix, ".png")
  )
}

prism_freeze_day_anomaly_output_path <- function(
    days,
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  days <- as.integer(days)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  file.path(
    processed_dir, "prism", aoi_id, "daily", "freeze-count-anomaly", "mint",
    paste0(sprintf("%03d", days), "day"), paste0(format(as.Date(date)), ".tif")
  )
}

prism_freeze_day_anomaly_map_path <- function(
    days,
    date = NULL,
    maps_dir = swc_paths$maps) {
  days <- as.integer(days)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "temperature",
    paste0("mint-freeze-day-anomaly-", days, "day-", suffix, ".png")
  )
}

prism_temperature_threshold_raster <- function(
    variable,
    statistic,
    dates,
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  variable <- validate_prism_temperature_variables(variable)
  statistic <- match.arg(statistic, c("p10", "p90"))
  if (length(variable) != 1L || variable == "tmean") {
    stop("Threshold layers require one downloaded temperature variable: `maxt` or `mint`.", call. = FALSE)
  }
  dates <- as.Date(dates)
  if (length(dates) == 0L || anyNA(dates)) {
    stop("`dates` must contain at least one valid date.", call. = FALSE)
  }
  path <- prism_climatology_path(
    variable, statistic, baseline_start, baseline_end,
    method = prism_statistic_method(statistic, window_days),
    aoi_id = aoi_id, processed_dir = processed_dir
  )
  if (!file.exists(path)) {
    stop("Temperature threshold climatology is missing: ", path, call. = FALSE)
  }
  climatology <- terra::rast(path)
  layer_dates <- as.Date(terra::time(climatology))
  layer_keys <- if (length(layer_dates) == terra::nlyr(climatology) && !anyNA(layer_dates)) {
    format(layer_dates, "%m-%d")
  } else {
    sub("^.*_", "", names(climatology))
  }
  keys <- format(dates, "%m-%d")
  selected <- match(keys, layer_keys)
  if (anyNA(selected) || anyDuplicated(layer_keys)) {
    problem <- if (anyNA(selected)) keys[which(is.na(selected))[[1L]]] else layer_keys[duplicated(layer_keys)][[1L]]
    stop("Temperature threshold climatology does not contain exactly one layer for ", problem, ".", call. = FALSE)
  }
  result <- climatology[[selected]]
  names(result) <- paste(variable, statistic, keys, sep = "_")
  terra::time(result) <- as.Date(paste0("2000-", keys))
  result
}

prism_temperature_normal_raster <- function(
    variable,
    dates,
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  variable <- validate_prism_temperature_variables(variable)
  if (length(variable) != 1L) stop("Exactly one temperature variable is required.", call. = FALSE)
  dates <- as.Date(dates)
  if (length(dates) == 0L || anyNA(dates)) {
    stop("`dates` must contain at least one valid date.", call. = FALSE)
  }
  reference_dates <- as.Date(paste0("2000-", format(dates, "%m-%d")))
  if (variable == "tmean") {
    maxt <- prism_temperature_normal_raster(
      "maxt", dates, baseline_start, baseline_end, window_days, aoi_id, processed_dir
    )
    mint <- prism_temperature_normal_raster(
      "mint", dates, baseline_start, baseline_end, window_days, aoi_id, processed_dir
    )
    return(prism_mean_temperature_raster(maxt, mint, reference_dates))
  }
  path <- prism_climatology_path(
    variable, "mean", baseline_start, baseline_end,
    method = prism_statistic_method("mean", window_days),
    aoi_id = aoi_id, processed_dir = processed_dir
  )
  if (!file.exists(path)) {
    stop("Temperature mean climatology is missing: ", path, call. = FALSE)
  }
  climatology <- terra::rast(path)
  layer_dates <- as.Date(terra::time(climatology))
  layer_keys <- if (length(layer_dates) == terra::nlyr(climatology) && !anyNA(layer_dates)) {
    format(layer_dates, "%m-%d")
  } else {
    sub("^.*_", "", names(climatology))
  }
  keys <- format(dates, "%m-%d")
  selected <- match(keys, layer_keys)
  if (anyNA(selected) || anyDuplicated(layer_keys)) {
    problem <- if (anyNA(selected)) keys[which(is.na(selected))[[1L]]] else layer_keys[duplicated(layer_keys)][[1L]]
    stop("Mean climatology does not contain exactly one layer for ", problem, ".", call. = FALSE)
  }
  result <- climatology[[selected]]
  names(result) <- paste(variable, "mean", keys, sep = "_")
  terra::time(result) <- reference_dates
  result
}

prism_temperature_normal_layer <- function(
    variable,
    date,
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  variable <- validate_prism_temperature_variables(variable)
  if (length(variable) != 1L) stop("Exactly one temperature variable is required.", call. = FALSE)
  if (length(date) != 1L) stop("Exactly one date is required.", call. = FALSE)
  prism_temperature_normal_raster(
    variable, date, baseline_start, baseline_end, window_days, aoi_id, processed_dir
  )
}

prism_temperature_departure_raster <- function(current, normal, variable, date) {
  variable <- validate_prism_temperature_variables(variable)
  if (length(variable) != 1L) stop("Exactly one temperature variable is required.", call. = FALSE)
  if (terra::nlyr(current) != 1L || terra::nlyr(normal) != 1L) {
    stop("Current temperature and normal must each contain one layer.", call. = FALSE)
  }
  terra::compareGeom(current, normal, stopOnError = TRUE)
  result <- current - normal
  date <- as.Date(date)
  names(result) <- paste(variable, "departure", format(date), sep = "_")
  terra::time(result) <- date
  result
}

prism_rolling_temperature_departure_raster <- function(
    observed,
    normal,
    variable,
    days,
    end_date) {
  variable <- validate_prism_temperature_variables(variable)
  days <- as.integer(days)
  if (length(variable) != 1L) stop("Exactly one temperature variable is required.", call. = FALSE)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  if (terra::nlyr(observed) != days || terra::nlyr(normal) != days) {
    stop("Observed and normal temperature rasters must each contain `days` layers.", call. = FALSE)
  }
  terra::compareGeom(observed, normal, stopOnError = TRUE)
  observed_dates <- as.Date(terra::time(observed))
  end_date <- as.Date(end_date)
  expected_dates <- seq(end_date - days + 1L, end_date, by = "day")
  if (length(observed_dates) != length(expected_dates) || anyNA(observed_dates) ||
      any(observed_dates != expected_dates)) {
    stop("Observed temperature layers must be complete, ordered, and end on `end_date`.", call. = FALSE)
  }
  observed_mean <- if (days == 1L) observed[[1L]] else terra::app(observed, mean, na.rm = FALSE)
  normal_mean <- if (days == 1L) normal[[1L]] else terra::app(normal, mean, na.rm = FALSE)
  result <- observed_mean - normal_mean
  names(result) <- paste0(variable, "_departure_", sprintf("%03d", days), "day_", end_date)
  terra::time(result) <- end_date
  result
}

calculate_prism_rolling_temperature_departure <- function(
    variable = "tmean",
    days = 30L,
    date = NULL,
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    output_path = NULL,
    overwrite = TRUE,
    quiet = FALSE) {
  variable <- validate_prism_temperature_variables(variable)
  days <- as.integer(days)
  if (length(variable) != 1L) stop("Exactly one temperature variable is required.", call. = FALSE)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  source_variables <- if (variable == "tmean") c("maxt", "mint") else variable
  if (is.null(date)) {
    date <- latest_common_prism_date(source_variables, aoi_id, processed_manifest)
  }
  date <- as.Date(date)
  dates <- seq(date - days + 1L, date, by = "day")
  if (!quiet) {
    message("Calculating ", days, "-day ", variable, " departure through ", date, ".")
  }
  if (variable == "tmean") {
    maxt <- read_prism_best_daily_range("maxt", dates, aoi_id, processed_manifest)
    mint <- read_prism_best_daily_range("mint", dates, aoi_id, processed_manifest)
    if (length(maxt$dates) != length(mint$dates) || any(maxt$dates != mint$dates)) {
      stop("Maximum and minimum temperature dates do not match.", call. = FALSE)
    }
    observed <- prism_mean_temperature_raster(maxt$raster, mint$raster, dates)
  } else {
    observed <- read_prism_best_daily_range(variable, dates, aoi_id, processed_manifest)$raster
  }
  normal <- prism_temperature_normal_raster(
    variable, dates, baseline_start, baseline_end, window_days, aoi_id, processed_dir
  )
  result <- prism_rolling_temperature_departure_raster(
    observed, normal, variable, days, date
  )
  if (is.null(output_path)) {
    output_path <- prism_temperature_rolling_departure_output_path(
      variable, days, date, aoi_id, processed_dir
    )
  }
  if (file.exists(output_path) && !overwrite) {
    stop("Rolling temperature departure output already exists; set `overwrite = TRUE`: ", output_path, call. = FALSE)
  }
  write_prism_processed_raster(result, output_path)
  if (!quiet) message("Wrote rolling temperature departure raster: ", output_path)
  result
}

prism_temperature_exceedance_count_raster <- function(
    observed,
    threshold,
    variable,
    statistic,
    days,
    end_date,
    comparison = c("above", "below")) {
  variable <- validate_prism_temperature_variables(variable)
  statistic <- match.arg(statistic, c("p10", "p90"))
  comparison <- match.arg(comparison)
  days <- as.integer(days)
  if (length(variable) != 1L || variable == "tmean") {
    stop("Extreme-frequency counts require one downloaded temperature variable: `maxt` or `mint`.", call. = FALSE)
  }
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  if (terra::nlyr(observed) != days || terra::nlyr(threshold) != days) {
    stop("Observed and threshold rasters must each contain `days` layers.", call. = FALSE)
  }
  terra::compareGeom(observed, threshold, stopOnError = TRUE)
  end_date <- as.Date(end_date)
  observed_dates <- as.Date(terra::time(observed))
  expected_dates <- seq(end_date - days + 1L, end_date, by = "day")
  if (length(observed_dates) != length(expected_dates) || anyNA(observed_dates) ||
      any(observed_dates != expected_dates)) {
    stop("Observed temperature layers must be complete, ordered, and end on `end_date`.", call. = FALSE)
  }
  exceedance <- if (comparison == "above") observed > threshold else observed < threshold
  result <- if (days == 1L) exceedance[[1L]] else terra::app(exceedance, sum, na.rm = FALSE)
  names(result) <- paste0(variable, "_", comparison, "_", statistic, "_count_", sprintf("%03d", days), "day_", end_date)
  terra::time(result) <- end_date
  result
}

calculate_prism_temperature_extreme_frequency <- function(
    variable = "maxt",
    statistic = "p90",
    days = 30L,
    date = NULL,
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    output_path = NULL,
    overwrite = TRUE,
    quiet = FALSE,
    comparison = c("above", "below")) {
  variable <- validate_prism_temperature_variables(variable)
  statistic <- match.arg(statistic, c("p10", "p90"))
  comparison <- match.arg(comparison)
  days <- as.integer(days)
  if (length(variable) != 1L || variable == "tmean") {
    stop("Extreme-frequency counts require one downloaded temperature variable: `maxt` or `mint`.", call. = FALSE)
  }
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  if (is.null(date)) date <- latest_common_prism_date(variable, aoi_id, processed_manifest)
  date <- as.Date(date)
  dates <- seq(date - days + 1L, date, by = "day")
  if (!quiet) {
    verb <- if (comparison == "above") "exceeded" else "fell below"
    message("Counting ", days, " days when ", variable, " ", verb, " its ", statistic, " threshold through ", date, ".")
  }
  observed <- read_prism_best_daily_range(
    variable, dates, aoi_id, processed_manifest
  )$raster
  threshold <- prism_temperature_threshold_raster(
    variable, statistic, dates, baseline_start, baseline_end,
    window_days, aoi_id, processed_dir
  )
  result <- prism_temperature_exceedance_count_raster(
    observed, threshold, variable, statistic, days, date, comparison
  )
  if (is.null(output_path)) {
    output_path <- prism_temperature_extreme_frequency_output_path(
      variable, statistic, days, date, aoi_id, processed_dir, comparison
    )
  }
  if (file.exists(output_path) && !overwrite) {
    stop("Extreme-temperature frequency output already exists; set `overwrite = TRUE`: ", output_path, call. = FALSE)
  }
  write_prism_processed_raster(result, output_path)
  if (!quiet) message("Wrote extreme-temperature frequency raster: ", output_path)
  result
}

prism_freeze_day_count_raster <- function(
    observed,
    days,
    end_date,
    threshold_f = 32) {
  days <- as.integer(days)
  threshold_f <- as.numeric(threshold_f)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  if (length(threshold_f) != 1L || !is.finite(threshold_f)) {
    stop("`threshold_f` must be one finite Fahrenheit value.", call. = FALSE)
  }
  if (terra::nlyr(observed) != days) {
    stop("Observed minimum-temperature raster must contain `days` layers.", call. = FALSE)
  }
  end_date <- as.Date(end_date)
  observed_dates <- as.Date(terra::time(observed))
  expected_dates <- seq(end_date - days + 1L, end_date, by = "day")
  if (length(observed_dates) != length(expected_dates) || anyNA(observed_dates) ||
      any(observed_dates != expected_dates)) {
    stop("Observed minimum-temperature layers must be complete, ordered, and end on `end_date`.", call. = FALSE)
  }
  freezes <- observed <= threshold_f
  result <- if (days == 1L) freezes[[1L]] else terra::app(freezes, sum, na.rm = FALSE)
  names(result) <- paste0("mint_at_or_below_", format(threshold_f, trim = TRUE), "F_count_", sprintf("%03d", days), "day_", end_date)
  terra::time(result) <- end_date
  result
}

calculate_prism_freeze_day_count <- function(
    days = 30L,
    date = NULL,
    threshold_f = 32,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    output_path = NULL,
    overwrite = TRUE,
    quiet = FALSE) {
  days <- as.integer(days)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  if (is.null(date)) date <- latest_common_prism_date("mint", aoi_id, processed_manifest)
  date <- as.Date(date)
  dates <- seq(date - days + 1L, date, by = "day")
  if (!quiet) {
    message("Counting ", days, " days with minimum temperature at or below ", threshold_f, " degrees F through ", date, ".")
  }
  observed <- read_prism_best_daily_range(
    "mint", dates, aoi_id, processed_manifest
  )$raster
  result <- prism_freeze_day_count_raster(observed, days, date, threshold_f)
  if (is.null(output_path)) {
    output_path <- prism_freeze_day_count_output_path(
      days, date, aoi_id, processed_dir
    )
  }
  if (file.exists(output_path) && !overwrite) {
    stop("Freeze-day count output already exists; set `overwrite = TRUE`: ", output_path, call. = FALSE)
  }
  write_prism_processed_raster(result, output_path)
  if (!quiet) message("Wrote freeze-day count raster: ", output_path)
  result
}

prism_freeze_day_anomaly_raster <- function(
    current_count,
    reference_counts,
    reference_groups,
    days,
    current_date) {
  days <- as.integer(days)
  current_date <- as.Date(current_date)
  if (terra::nlyr(current_count) != 1L) {
    stop("The current freeze-day count must contain exactly one layer.", call. = FALSE)
  }
  terra::compareGeom(current_count, reference_counts, stopOnError = TRUE)
  reference_dates <- as.Date(terra::time(reference_counts))
  group_means <- lapply(reference_groups, function(group_dates) {
    selected <- which(reference_dates %in% as.Date(group_dates))
    if (length(selected) == 0L) {
      stop("A freeze-count reference group has no matching cache layers.", call. = FALSE)
    }
    terra::app(reference_counts[[selected]], mean, na.rm = FALSE)
  })
  normal_count <- if (length(group_means) == 1L) {
    group_means[[1L]]
  } else {
    Reduce(`+`, group_means) / length(group_means)
  }
  result <- current_count - normal_count
  names(result) <- paste0("mint_freeze_count_anomaly_", sprintf("%03d", days), "day_", current_date)
  terra::time(result) <- current_date
  result
}

calculate_prism_freeze_day_anomaly <- function(
    current_count,
    days = 30L,
    current_date = as.Date(terra::time(current_count)),
    threshold_f = 32,
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    cache_overwrite = FALSE,
    cache_manifest_path = prism_temperature_threshold_cache_manifest_path(processed_dir),
    output_path = NULL,
    overwrite = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  if (!exists("build_prism_freeze_count_cache", mode = "function")) {
    stop("Source `R/prism-temperature-threshold-cache.R` before calculating freeze-day anomalies.", call. = FALSE)
  }
  days <- as.integer(days)
  current_date <- as.Date(current_date)
  cache <- build_prism_freeze_count_cache(
    days = days,
    target_date = current_date,
    threshold_f = threshold_f,
    baseline_start = baseline_start,
    baseline_end = baseline_end,
    window_days = window_days,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    processed_manifest = processed_manifest,
    manifest_path = cache_manifest_path,
    overwrite = cache_overwrite,
    progress_every = progress_every,
    quiet = quiet
  )
  result <- prism_freeze_day_anomaly_raster(
    current_count, cache$raster, cache$groups, days, current_date
  )
  if (is.null(output_path)) {
    output_path <- prism_freeze_day_anomaly_output_path(
      days, current_date, aoi_id, processed_dir
    )
  }
  if (file.exists(output_path) && !overwrite) {
    stop("Freeze-day anomaly output already exists; set `overwrite = TRUE`: ", output_path, call. = FALSE)
  }
  write_prism_processed_raster(result, output_path)
  if (!quiet) message("Wrote freeze-day anomaly raster: ", output_path)
  result
}

prism_percentile_rank_output_path <- function(
    variable,
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  variable <- validate_prism_temperature_variables(variable)
  if (length(variable) != 1L) stop("Exactly one PRISM variable is required.", call. = FALSE)
  file.path(
    processed_dir, "prism", aoi_id, "daily", "percentile-rank", variable,
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_percentile_map_path <- function(
    variable,
    date = NULL,
    maps_dir = swc_paths$maps) {
  variable <- validate_prism_temperature_variables(variable)
  if (length(variable) != 1L) stop("Exactly one PRISM variable is required.", call. = FALSE)
  filename <- if (is.null(date)) {
    paste0(variable, "-percentile-rank-latest.png")
  } else {
    paste0(variable, "-percentile-rank-", format(as.Date(date)), ".png")
  }
  file.path(maps_dir, "prism", "temperature", filename)
}

prism_temperature_label <- function(variable) {
  switch(
    validate_prism_temperature_variables(variable),
    maxt = "Maximum temperature",
    mint = "Minimum temperature",
    tmean = "Mean temperature"
  )
}

prism_temperature_value_scale <- function(variable) {
  variable <- validate_prism_temperature_variables(variable)
  limits <- switch(variable, maxt = c(-20, 120), mint = c(-40, 100), tmean = c(-30, 110))
  list(limits = limits, breaks = seq(limits[[1L]], limits[[2L]], by = 20))
}

format_prism_map_date <- function(date) {
  sub(" 0", " ", format(as.Date(date), "%B %d, %Y"), fixed = TRUE)
}

build_prism_temperature_value_map <- function(
    raster,
    variable,
    date = as.Date(terra::time(raster)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities()) {
  variable <- validate_prism_temperature_variables(variable)
  scale <- prism_temperature_value_scale(variable)
  southwest_raster_map(
    raster = raster,
    states = states,
    title = paste(prism_temperature_label(variable), "(degrees F)"),
    subtitle = format_prism_map_date(date),
    caption = NULL,
    fill_label = "degrees F",
    palette = c("#313695", "#4575b4", "#91bfdb", "#ffffbf", "#fdae61", "#d73027", "#7f0000"),
    limits = scale$limits,
    breaks = scale$breaks,
    labels = as.character(scale$breaks),
    counties = counties,
    countries = countries,
    cities = cities,
    product_id = paste0(variable, "_value"),
    mask_to_states = FALSE
  )
}

build_prism_temperature_departure_map <- function(
    raster,
    variable,
    date = as.Date(terra::time(raster)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities()) {
  variable <- validate_prism_temperature_variables(variable)
  southwest_raster_map(
    raster = raster,
    states = states,
    title = paste(prism_temperature_label(variable), "departure"),
    subtitle = paste0(
      format_prism_map_date(date), " relative to 1991-2020 | degrees F"
    ),
    caption = NULL,
    fill_label = "Departure (degrees F)",
    palette = c("#313695", "#4575b4", "#abd9e9", "#f7f7f7", "#fdae61", "#d73027", "#7f0000"),
    palette_values = c(-30, -15, -5, 0, 5, 15, 30),
    limits = c(-30, 30),
    breaks = c(-30, -20, -10, 0, 10, 20, 30),
    labels = c("-30", "-20", "-10", "0", "10", "20", "30"),
    counties = counties,
    countries = countries,
    cities = cities,
    product_id = paste0(variable, "_departure_daily"),
    mask_to_states = FALSE
  )
}

build_prism_rolling_temperature_departure_map <- function(
    raster,
    variable,
    days,
    date = as.Date(terra::time(raster)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities()) {
  variable <- validate_prism_temperature_variables(variable)
  days <- as.integer(days)
  date <- as.Date(date)
  start_date <- date - days + 1L
  southwest_raster_map(
    raster = raster,
    states = states,
    title = paste0(days, "-day ", tolower(prism_temperature_label(variable)), " departure"),
    subtitle = paste0(
      format_prism_map_period(start_date, date),
      " relative to 1991-2020 | degrees F"
    ),
    caption = NULL,
    fill_label = "Departure (degrees F)",
    palette = c("#313695", "#4575b4", "#abd9e9", "#f7f7f7", "#fdae61", "#d73027", "#7f0000"),
    palette_values = c(-15, -8, -3, 0, 3, 8, 15),
    limits = c(-15, 15),
    breaks = c(-15, -10, -5, 0, 5, 10, 15),
    labels = c("-15", "-10", "-5", "0", "5", "10", "15"),
    counties = counties,
    countries = countries,
    cities = cities,
    product_id = paste0(variable, "_departure_", sprintf("%02d", days), "day"),
    mask_to_states = FALSE
  )
}

build_prism_extreme_warm_day_frequency_map <- function(
    raster,
    days = 30L,
    date = as.Date(terra::time(raster)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities()) {
  days <- as.integer(days)
  date <- as.Date(date)
  start_date <- date - days + 1L
  southwest_raster_map(
    raster = raster,
    states = states,
    title = paste0("Extreme warm days in the past ", days, " days"),
    subtitle = paste0(
      format_prism_map_period(start_date, date),
      " | maximum temperature above local 1991-2020 90th percentile"
    ),
    caption = NULL,
    fill_label = "Number of days",
    palette = c("#f7f7f7", "#fff7bc", "#fec44f", "#fe9929", "#e34a33", "#b30000", "#67000d"),
    palette_values = c(0, 1, 3, 5, 10, 20, 30),
    limits = c(0, days),
    breaks = unique(pmin(days, c(0, 3, 5, 10, 15, 20, 30))),
    labels = as.character(unique(pmin(days, c(0, 3, 5, 10, 15, 20, 30)))),
    counties = counties,
    countries = countries,
    cities = cities,
    product_id = "maxt_extreme_warm_count_30day",
    mask_to_states = FALSE
  )
}

build_prism_extreme_cold_night_frequency_map <- function(
    raster,
    days = 30L,
    date = as.Date(terra::time(raster)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities()) {
  days <- as.integer(days)
  date <- as.Date(date)
  start_date <- date - days + 1L
  southwest_raster_map(
    raster = raster,
    states = states,
    title = paste0("Extreme cold nights in the past ", days, " days"),
    subtitle = paste0(
      format_prism_map_period(start_date, date),
      " | minimum temperature below local 1991-2020 10th percentile"
    ),
    caption = NULL,
    fill_label = "Number of nights",
    palette = c("#f7f7f7", "#e0f3f8", "#abd9e9", "#74add1", "#4575b4", "#313695", "#1f1c5c"),
    palette_values = c(0, 1, 3, 5, 10, 20, 30),
    limits = c(0, days),
    breaks = unique(pmin(days, c(0, 3, 5, 10, 15, 20, 30))),
    labels = as.character(unique(pmin(days, c(0, 3, 5, 10, 15, 20, 30)))),
    counties = counties,
    countries = countries,
    cities = cities,
    product_id = "mint_extreme_cold_count_30day",
    mask_to_states = FALSE
  )
}

build_prism_freeze_day_count_map <- function(
    raster,
    days = 30L,
    date = as.Date(terra::time(raster)),
    threshold_f = 32,
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities()) {
  days <- as.integer(days)
  date <- as.Date(date)
  start_date <- date - days + 1L
  plot <- southwest_raster_map(
    raster = raster,
    states = states,
    title = paste0("Nights at or below freezing in the past ", days, " days"),
    subtitle = paste0(
      format_prism_map_period(start_date, date),
      " | minimum temperature at or below ", threshold_f, " degrees F"
    ),
    caption = NULL,
    fill_label = "Number of nights",
    palette = c("#f7f7f7", "#e0f3db", "#a8ddb5", "#7bccc4", "#43a2ca", "#0868ac", "#084081"),
    palette_values = c(0, 1, 3, 5, 10, 20, 30),
    limits = c(0, days),
    breaks = unique(pmin(days, c(0, 1, 3, 5, 10, 20, 30))),
    labels = as.character(unique(pmin(days, c(0, 1, 3, 5, 10, 20, 30)))),
    counties = counties,
    countries = countries,
    cities = cities,
    product_id = "mint_freeze_count_30day",
    mask_to_states = FALSE
  )
  value_range <- range(terra::values(raster), na.rm = TRUE)
  if (all(is.finite(value_range)) && all(value_range == 0)) {
    raster_extent <- terra::ext(raster)
    plot <- plot + ggplot2::annotate(
      "label",
      x = mean(c(raster_extent$xmin, raster_extent$xmax)),
      y = raster_extent$ymax - 0.45,
      label = paste0("No nights at or below ", threshold_f, " degrees F\nobserved during this period"),
      color = "#27323a",
      fill = scales::alpha("white", 0.88),
      linewidth = 0.25,
      size = 4.1,
      fontface = "bold"
    )
  }
  plot
}

build_prism_freeze_day_anomaly_map <- function(
    raster,
    days = 30L,
    date = as.Date(terra::time(raster)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities()) {
  days <- as.integer(days)
  date <- as.Date(date)
  start_date <- date - days + 1L
  southwest_raster_map(
    raster = raster,
    states = states,
    title = paste0(days, "-day freeze-night anomaly"),
    subtitle = paste0(
      format_prism_map_period(start_date, date),
      " | current count minus centered 5-day 1991-2020 average"
    ),
    caption = NULL,
    fill_label = "Difference (nights)",
    palette = c("#b2182b", "#ef8a62", "#fddbc7", "#f7f7f7", "#d1e5f0", "#67a9cf", "#2166ac"),
    palette_values = c(-10, -5, -2, 0, 2, 5, 10),
    limits = c(-10, 10),
    breaks = c(-10, -5, -2, 0, 2, 5, 10),
    labels = c("-10", "-5", "-2", "0", "2", "5", "10"),
    counties = counties,
    countries = countries,
    cities = cities,
    product_id = "mint_freeze_anomaly_30day",
    mask_to_states = FALSE
  )
}

build_current_temperature_value_maps <- function(
    date = NULL,
    variables = swc_prism$temperature_variables,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    logo_path = southwest_brand_logo_path(),
    quiet = FALSE) {
  variables <- validate_prism_temperature_variables(variables)
  if (is.null(date)) date <- latest_common_prism_date(variables, aoi_id = aoi_id)
  date <- as.Date(date)
  states <- southwest_state_boundaries()
  counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries()
  cities <- southwest_reference_cities()
  records <- vector("list", length(variables))
  for (index in seq_along(variables)) {
    variable <- variables[[index]]
    if (!quiet) message("Building ", variable, " current-value map for ", date, ".")
    raster <- prism_current_temperature_raster(variable, date, aoi_id, processed_dir)
    raster_path <- if (variable == "tmean") {
      path <- prism_temperature_derived_output_path(variable, "value", date, aoi_id, processed_dir)
      write_prism_processed_raster(raster, path)
      path
    } else {
      prism_recent_processed_path(variable, date, aoi_id, processed_dir)
    }
    plot <- build_prism_temperature_value_map(
      raster, variable, date, states, counties, countries, cities
    )
    dated_map <- prism_temperature_map_path(variable, "value", date, maps_dir)
    latest_map <- prism_temperature_map_path(variable, "value", maps_dir = maps_dir)
    save_southwest_map(
      plot, dated_map, logo_path = logo_path,
      footer_text = "Data source: PRISM Climate Group via RCC-ACIS"
    )
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest temperature map: ", latest_map, call. = FALSE)
    }
    value_range <- range(terra::values(raster), na.rm = TRUE)
    records[[index]] <- data.frame(
      date = date, variable = variable, minimum = value_range[[1L]], maximum = value_range[[2L]],
      raster_path = raster_path, map_path = dated_map, latest_map_path = latest_map,
      stringsAsFactors = FALSE
    )
  }
  invisible(do.call(rbind, records))
}

build_current_temperature_departure_maps <- function(
    date = NULL,
    variables = swc_prism$temperature_variables,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    quiet = FALSE) {
  variables <- validate_prism_temperature_variables(variables)
  if (is.null(date)) date <- latest_common_prism_date(variables, aoi_id = aoi_id)
  date <- as.Date(date)
  states <- southwest_state_boundaries()
  counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries()
  cities <- southwest_reference_cities()
  records <- vector("list", length(variables))
  for (index in seq_along(variables)) {
    variable <- variables[[index]]
    if (!quiet) message("Building ", variable, " departure map for ", date, ".")
    current <- prism_current_temperature_raster(variable, date, aoi_id, processed_dir)
    normal <- prism_temperature_normal_layer(
      variable, date, aoi_id = aoi_id, processed_dir = processed_dir
    )
    departure <- prism_temperature_departure_raster(current, normal, variable, date)
    raster_path <- prism_temperature_derived_output_path(
      variable, "departure", date, aoi_id, processed_dir
    )
    if (file.exists(raster_path) && !overwrite) {
      stop("Temperature departure output already exists; set `overwrite = TRUE`: ", raster_path, call. = FALSE)
    }
    write_prism_processed_raster(departure, raster_path)
    plot <- build_prism_temperature_departure_map(
      departure, variable, date, states, counties, countries, cities
    )
    dated_map <- prism_temperature_map_path(variable, "departure", date, maps_dir)
    latest_map <- prism_temperature_map_path(variable, "departure", maps_dir = maps_dir)
    save_southwest_map(
      plot, dated_map, logo_path = logo_path,
      footer_text = prism_map_footer_text()
    )
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest departure map: ", latest_map, call. = FALSE)
    }
    value_range <- range(terra::values(departure), na.rm = TRUE)
    records[[index]] <- data.frame(
      date = date, variable = variable,
      minimum_departure = value_range[[1L]], maximum_departure = value_range[[2L]],
      raster_path = raster_path, map_path = dated_map, latest_map_path = latest_map,
      stringsAsFactors = FALSE
    )
  }
  invisible(do.call(rbind, records))
}

build_current_temperature_rolling_departure_map <- function(
    variable = "tmean",
    days = 30L,
    date = NULL,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    quiet = FALSE) {
  variable <- validate_prism_temperature_variables(variable)
  days <- as.integer(days)
  if (length(variable) != 1L) stop("Exactly one temperature variable is required.", call. = FALSE)
  if (is.null(date)) date <- latest_common_prism_date(variable, aoi_id, processed_manifest)
  date <- as.Date(date)
  departure <- calculate_prism_rolling_temperature_departure(
    variable = variable,
    days = days,
    date = date,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    processed_manifest = processed_manifest,
    overwrite = overwrite,
    quiet = quiet
  )
  plot <- build_prism_rolling_temperature_departure_map(
    departure, variable, days, date
  )
  dated_map <- prism_temperature_rolling_departure_map_path(
    variable, days, date, maps_dir
  )
  latest_map <- prism_temperature_rolling_departure_map_path(
    variable, days, maps_dir = maps_dir
  )
  save_southwest_map(
    plot, dated_map, logo_path = logo_path,
    footer_text = prism_map_footer_text()
  )
  dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
    stop("Could not update latest rolling temperature departure map: ", latest_map, call. = FALSE)
  }
  value_range <- range(terra::values(departure), na.rm = TRUE)
  invisible(data.frame(
    date = date,
    variable = variable,
    days = days,
    minimum_departure = value_range[[1L]],
    maximum_departure = value_range[[2L]],
    raster_path = prism_temperature_rolling_departure_output_path(
      variable, days, date, aoi_id, processed_dir
    ),
    map_path = dated_map,
    latest_map_path = latest_map,
    stringsAsFactors = FALSE
  ))
}

build_current_temperature_rolling_departure_maps <- function(
    variables = c("maxt", "mint", "tmean"),
    days = 30L,
    date = NULL,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    quiet = FALSE) {
  variables <- validate_prism_temperature_variables(variables)
  if (length(variables) == 0L || anyDuplicated(variables)) {
    stop("`variables` must contain one or more unique temperature variables.", call. = FALSE)
  }
  days <- as.integer(days)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  if (is.null(date)) {
    date <- latest_common_prism_date(variables, aoi_id, processed_manifest)
  }
  date <- as.Date(date)
  records <- lapply(variables, function(variable) {
    build_current_temperature_rolling_departure_map(
      variable = variable,
      days = days,
      date = date,
      aoi_id = aoi_id,
      processed_dir = processed_dir,
      maps_dir = maps_dir,
      processed_manifest = processed_manifest,
      logo_path = logo_path,
      overwrite = overwrite,
      quiet = quiet
    )
  })
  invisible(do.call(rbind, records))
}

build_current_extreme_warm_day_frequency_map <- function(
    days = 30L,
    date = NULL,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    quiet = FALSE) {
  days <- as.integer(days)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  if (is.null(date)) date <- latest_common_prism_date("maxt", aoi_id, processed_manifest)
  date <- as.Date(date)
  count <- calculate_prism_temperature_extreme_frequency(
    variable = "maxt",
    statistic = "p90",
    days = days,
    date = date,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    processed_manifest = processed_manifest,
    overwrite = overwrite,
    quiet = quiet
  )
  plot <- build_prism_extreme_warm_day_frequency_map(count, days, date)
  dated_map <- prism_temperature_extreme_frequency_map_path(
    "maxt", "p90", days, date, maps_dir
  )
  latest_map <- prism_temperature_extreme_frequency_map_path(
    "maxt", "p90", days, maps_dir = maps_dir
  )
  save_southwest_map(
    plot, dated_map, logo_path = logo_path,
    footer_text = prism_map_footer_text()
  )
  dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
    stop("Could not update latest extreme warm-day frequency map: ", latest_map, call. = FALSE)
  }
  value_range <- range(terra::values(count), na.rm = TRUE)
  invisible(data.frame(
    date = date,
    days = days,
    minimum_count = value_range[[1L]],
    maximum_count = value_range[[2L]],
    raster_path = prism_temperature_extreme_frequency_output_path(
      "maxt", "p90", days, date, aoi_id, processed_dir
    ),
    map_path = dated_map,
    latest_map_path = latest_map,
    stringsAsFactors = FALSE
  ))
}

build_current_extreme_cold_night_frequency_map <- function(
    days = 30L,
    date = NULL,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    quiet = FALSE) {
  days <- as.integer(days)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  if (is.null(date)) date <- latest_common_prism_date("mint", aoi_id, processed_manifest)
  date <- as.Date(date)
  count <- calculate_prism_temperature_extreme_frequency(
    variable = "mint",
    statistic = "p10",
    days = days,
    date = date,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    processed_manifest = processed_manifest,
    overwrite = overwrite,
    quiet = quiet,
    comparison = "below"
  )
  plot <- build_prism_extreme_cold_night_frequency_map(count, days, date)
  dated_map <- prism_temperature_extreme_frequency_map_path(
    "mint", "p10", days, date, maps_dir, comparison = "below"
  )
  latest_map <- prism_temperature_extreme_frequency_map_path(
    "mint", "p10", days, maps_dir = maps_dir, comparison = "below"
  )
  save_southwest_map(
    plot, dated_map, logo_path = logo_path,
    footer_text = prism_map_footer_text()
  )
  dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
    stop("Could not update latest extreme cold-night frequency map: ", latest_map, call. = FALSE)
  }
  value_range <- range(terra::values(count), na.rm = TRUE)
  invisible(data.frame(
    date = date,
    days = days,
    minimum_count = value_range[[1L]],
    maximum_count = value_range[[2L]],
    raster_path = prism_temperature_extreme_frequency_output_path(
      "mint", "p10", days, date, aoi_id, processed_dir, comparison = "below"
    ),
    map_path = dated_map,
    latest_map_path = latest_map,
    stringsAsFactors = FALSE
  ))
}

build_current_freeze_day_count_map <- function(
    days = 30L,
    date = NULL,
    threshold_f = 32,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    quiet = FALSE) {
  days <- as.integer(days)
  if (length(days) != 1L || is.na(days) || days < 1L) {
    stop("`days` must be one positive integer.", call. = FALSE)
  }
  if (is.null(date)) date <- latest_common_prism_date("mint", aoi_id, processed_manifest)
  date <- as.Date(date)
  count <- calculate_prism_freeze_day_count(
    days = days,
    date = date,
    threshold_f = threshold_f,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    processed_manifest = processed_manifest,
    overwrite = overwrite,
    quiet = quiet
  )
  plot <- build_prism_freeze_day_count_map(count, days, date, threshold_f)
  dated_map <- prism_freeze_day_count_map_path(days, date, maps_dir)
  latest_map <- prism_freeze_day_count_map_path(days, maps_dir = maps_dir)
  save_southwest_map(
    plot, dated_map, logo_path = logo_path,
    footer_text = "Data source: PRISM Climate Group via RCC-ACIS"
  )
  dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
    stop("Could not update latest freeze-day count map: ", latest_map, call. = FALSE)
  }
  value_range <- range(terra::values(count), na.rm = TRUE)
  invisible(data.frame(
    date = date,
    days = days,
    threshold_f = threshold_f,
    minimum_count = value_range[[1L]],
    maximum_count = value_range[[2L]],
    raster_path = prism_freeze_day_count_output_path(
      days, date, aoi_id, processed_dir
    ),
    map_path = dated_map,
    latest_map_path = latest_map,
    stringsAsFactors = FALSE
  ))
}

build_current_freeze_day_anomaly_map <- function(
    days = 30L,
    date = NULL,
    threshold_f = 32,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    logo_path = southwest_brand_logo_path(),
    cache_overwrite = FALSE,
    overwrite = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  days <- as.integer(days)
  if (is.null(date)) date <- latest_common_prism_date("mint", aoi_id, processed_manifest)
  date <- as.Date(date)
  current_count <- calculate_prism_freeze_day_count(
    days = days,
    date = date,
    threshold_f = threshold_f,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    processed_manifest = processed_manifest,
    overwrite = overwrite,
    quiet = TRUE
  )
  anomaly <- calculate_prism_freeze_day_anomaly(
    current_count = current_count,
    days = days,
    current_date = date,
    threshold_f = threshold_f,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    processed_manifest = processed_manifest,
    cache_overwrite = cache_overwrite,
    overwrite = overwrite,
    progress_every = progress_every,
    quiet = quiet
  )
  plot <- build_prism_freeze_day_anomaly_map(anomaly, days, date)
  dated_map <- prism_freeze_day_anomaly_map_path(days, date, maps_dir)
  latest_map <- prism_freeze_day_anomaly_map_path(days, maps_dir = maps_dir)
  save_southwest_map(
    plot, dated_map, logo_path = logo_path,
    footer_text = prism_map_footer_text()
  )
  dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
    stop("Could not update latest freeze-day anomaly map: ", latest_map, call. = FALSE)
  }
  value_range <- range(terra::values(anomaly), na.rm = TRUE)
  invisible(data.frame(
    date = date,
    days = days,
    threshold_f = threshold_f,
    minimum_anomaly = value_range[[1L]],
    maximum_anomaly = value_range[[2L]],
    raster_path = prism_freeze_day_anomaly_output_path(
      days, date, aoi_id, processed_dir
    ),
    map_path = dated_map,
    latest_map_path = latest_map,
    stringsAsFactors = FALSE
  ))
}

prism_map_footer_text <- function(
    reference_start = swc_prism$percentile_start,
    reference_end = swc_prism$percentile_end) {
  paste(
    "Data source: PRISM Climate Group via RCC-ACIS",
    paste0(
      "Reference period: ",
      format(as.Date(reference_start), "%Y"),
      "-",
      format(as.Date(reference_end), "%Y")
    ),
    sep = "\n"
  )
}

build_prism_percentile_rank_map <- function(
    rank_raster,
    variable,
    date = as.Date(terra::time(rank_raster)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities()) {
  variable <- validate_prism_temperature_variables(variable)
  if (length(variable) != 1L) stop("Exactly one temperature variable is required.", call. = FALSE)
  date <- as.Date(date)
  title <- switch(
    variable,
    maxt = "Maximum temperature percentile rank",
    mint = "Minimum temperature percentile rank",
    tmean = "Mean temperature percentile rank"
  )
  southwest_raster_map(
    raster = rank_raster,
    states = states,
    title = title,
    subtitle = paste0(
      format_prism_map_date(date),
      " relative to 1991-2020 | centered 5-day baseline"
    ),
    caption = NULL,
    fill_label = "Percentile rank",
    palette = c("#313695", "#4575b4", "#91bfdb", "#f7f7f7", "#fdae61", "#d73027", "#7f0000"),
    palette_values = c(0, 10, 25, 50, 75, 90, 100),
    limits = c(0, 100),
    breaks = c(0, 10, 25, 50, 75, 90, 100),
    labels = c("0", "10", "25", "50", "75", "90", "100"),
    counties = counties,
    countries = countries,
    cities = cities,
    product_id = paste0(variable, "_percentile_daily"),
    mask_to_states = FALSE
  )
}

build_current_temperature_percentile_maps <- function(
    date = NULL,
    variables = swc_prism$temperature_variables,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    quiet = FALSE) {
  variables <- validate_prism_temperature_variables(variables)
  if (is.null(date)) {
    date <- latest_common_prism_date(variables, aoi_id = aoi_id)
  }
  date <- as.Date(date)
  states <- southwest_state_boundaries()
  counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries()
  cities <- southwest_reference_cities()
  records <- vector("list", length(variables))

  for (index in seq_along(variables)) {
    variable <- variables[[index]]
    current <- prism_current_temperature_raster(variable, date, aoi_id, processed_dir)
    rank_path <- prism_percentile_rank_output_path(variable, date, aoi_id, processed_dir)
    if (!quiet) message("Calculating ", variable, " percentile rank for ", date, ".")
    rank <- calculate_prism_percentile_rank(
      current = current,
      variable = variable,
      current_date = date,
      aoi_id = aoi_id,
      processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
      output_path = rank_path,
      overwrite = overwrite,
      quiet = quiet
    )
    plot <- build_prism_percentile_rank_map(
      rank,
      variable,
      date,
      states = states,
      counties = counties,
      countries = countries,
      cities = cities
    )
    dated_map <- prism_percentile_map_path(variable, date, maps_dir)
    latest_map <- prism_percentile_map_path(variable, maps_dir = maps_dir)
    save_southwest_map(
      plot,
      dated_map,
      logo_path = logo_path,
      footer_text = prism_map_footer_text()
    )
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest percentile map: ", latest_map, call. = FALSE)
    }
    value_range <- range(terra::values(rank), na.rm = TRUE)
    records[[index]] <- data.frame(
      date = date,
      variable = variable,
      minimum_rank = value_range[[1L]],
      maximum_rank = value_range[[2L]],
      rank_path = rank_path,
      map_path = dated_map,
      latest_map_path = latest_map,
      stringsAsFactors = FALSE
    )
  }
  invisible(do.call(rbind, records))
}
