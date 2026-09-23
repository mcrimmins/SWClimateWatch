# Calculate and map the share of recent precipitation supplied by very wet days.

prism_very_wet_contribution_cache_version <- 1L

prism_very_wet_contribution_values <- function(
    values,
    threshold,
    minimum_total_inches = 0.10) {
  if (length(values) == 0L || anyNA(values) || length(threshold) != 1L ||
      !is.finite(threshold)) {
    return(NA_real_)
  }
  total <- sum(values)
  if (!is.finite(total) || total < minimum_total_inches) return(NA_real_)
  100 * sum(values[values > threshold]) / total
}

validate_prism_minimum_precipitation_total <- function(minimum_total_inches) {
  if (length(minimum_total_inches) != 1L || !is.finite(minimum_total_inches) ||
      minimum_total_inches < 0) {
    stop("`minimum_total_inches` must be one non-negative number.", call. = FALSE)
  }
  as.numeric(minimum_total_inches)
}

prism_very_wet_threshold_path <- function(
    threshold_statistic = "wet_p95",
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  if (!threshold_statistic %in% c("wet_p90", "wet_p95", "wet_p99")) {
    stop("Very-wet contribution requires wet_p90, wet_p95, or wet_p99.", call. = FALSE)
  }
  prism_climatology_path(
    "pcpn", threshold_statistic, baseline_start, baseline_end,
    method = "annual-wet-days", aoi_id = aoi_id, processed_dir = processed_dir
  )
}

read_prism_very_wet_threshold <- function(
    threshold_statistic = "wet_p95",
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  path <- prism_very_wet_threshold_path(
    threshold_statistic, baseline_start, baseline_end, aoi_id, processed_dir
  )
  if (!file.exists(path)) {
    stop("Very-wet-day threshold does not exist: ", path, call. = FALSE)
  }
  raster <- terra::rast(path)
  if (terra::nlyr(raster) != 1L) {
    stop("The annual very-wet-day threshold must contain one layer.", call. = FALSE)
  }
  list(raster = raster, path = path)
}

prism_very_wet_contribution_from_raster <- function(
    raster,
    threshold_raster,
    end_date,
    duration_days = 90L,
    minimum_total_inches = 0.10) {
  duration_days <- validate_prism_wet_day_duration(duration_days)
  minimum_total_inches <- validate_prism_minimum_precipitation_total(
    minimum_total_inches
  )
  dates <- as.Date(terra::time(raster))
  if (terra::nlyr(raster) != duration_days || length(dates) != terra::nlyr(raster) ||
      anyNA(dates) || anyDuplicated(dates)) {
    stop(
      "The very-wet contribution input must have one unique valid date per window day.",
      call. = FALSE
    )
  }
  end_date <- as.Date(end_date)
  expected <- seq(end_date - duration_days + 1L, end_date, by = "day")
  if (any(dates != expected)) {
    stop("The very-wet contribution input must be complete and ordered by date.", call. = FALSE)
  }
  if (terra::nlyr(threshold_raster) != 1L) {
    stop("The very-wet-day threshold must contain exactly one layer.", call. = FALSE)
  }
  terra::compareGeom(raster, threshold_raster, stopOnError = TRUE)
  result <- terra::app(
    c(raster, threshold_raster),
    fun = function(x, ...) {
      prism_very_wet_contribution_values(
        x[seq_len(duration_days)], x[[duration_days + 1L]], minimum_total_inches
      )
    }
  )
  names(result) <- paste0(
    "pcpn_very_wet_contribution_", sprintf("%03d", duration_days), "day_", end_date
  )
  terra::time(result) <- end_date
  result
}

prism_very_wet_contributions_for_end_dates <- function(
    raster,
    dates,
    end_dates,
    threshold_raster,
    duration_days = 90L,
    minimum_total_inches = 0.10,
    progress_every = 25L,
    quiet = FALSE) {
  dates <- as.Date(dates)
  end_dates <- sort(unique(as.Date(end_dates)))
  duration_days <- validate_prism_wet_day_duration(duration_days)
  minimum_total_inches <- validate_prism_minimum_precipitation_total(
    minimum_total_inches
  )
  progress_every <- validate_prism_progress_every(progress_every)
  if (terra::nlyr(raster) != length(dates) || anyNA(dates) || anyDuplicated(dates)) {
    stop("The very-wet contribution source must have one unique valid date per layer.", call. = FALSE)
  }
  terra::compareGeom(raster, threshold_raster, stopOnError = TRUE)
  started <- proc.time()[["elapsed"]]
  layers <- vector("list", length(end_dates))
  for (index in seq_along(end_dates)) {
    needed <- seq(end_dates[[index]] - duration_days + 1L, end_dates[[index]], by = "day")
    selected <- match(needed, dates)
    if (anyNA(selected)) {
      stop(
        "Very-wet contribution input is incomplete; first missing date: ",
        format(needed[which(is.na(selected))[[1L]]]),
        call. = FALSE
      )
    }
    layers[[index]] <- prism_very_wet_contribution_from_raster(
      raster[[selected]], threshold_raster, end_dates[[index]], duration_days,
      minimum_total_inches
    )
    if (!quiet && (index %% progress_every == 0L || index == length(end_dates))) {
      message(
        "  ", duration_days, "-day very-wet contribution samples: ", index,
        "/", length(end_dates), " ending dates (",
        format_prism_elapsed(proc.time()[["elapsed"]] - started), ")."
      )
    }
  }
  result <- do.call(c, layers)
  terra::time(result) <- end_dates
  names(result) <- paste0(
    "pcpn_very_wet_contribution_", sprintf("%03d", duration_days), "day_", end_dates
  )
  result
}

prism_very_wet_contribution_cache_manifest_path <- function(
    processed_dir = swc_paths$processed) {
  file.path(processed_dir, "prism", "very-wet-contribution-cache-manifest.csv")
}

prism_very_wet_contribution_cache_path <- function(
    target_date,
    duration_days = 90L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    threshold_statistic = "wet_p95",
    minimum_total_inches = 0.10,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  duration_days <- validate_prism_wet_day_duration(duration_days)
  window_days <- validate_prism_window(window_days)
  minimum_total_inches <- validate_prism_minimum_precipitation_total(
    minimum_total_inches
  )
  baseline_label <- paste0(
    format(as.Date(baseline_start), "%Y%m%d"), "-",
    format(as.Date(baseline_end), "%Y%m%d")
  )
  threshold_label <- gsub("_", "-", threshold_statistic, fixed = TRUE)
  minimum_label <- sprintf("minimum-total-%03din", round(minimum_total_inches * 100))
  file.path(
    processed_dir, "prism", aoi_id, "climatology", baseline_label,
    "very-wet-contribution-samples", "pcpn",
    paste0(sprintf("%03d", duration_days), "day"), threshold_label,
    minimum_label, sprintf("centered-%02dday", window_days),
    paste0(format(as.Date(target_date), "%m-%d"), ".tif")
  )
}

read_prism_very_wet_contribution_cache <- function(path, expected_end_dates = NULL) {
  if (!file.exists(path)) {
    stop("Very-wet contribution cache does not exist: ", path, call. = FALSE)
  }
  raster <- terra::rast(path)
  dates <- as.Date(terra::time(raster))
  if (length(dates) != terra::nlyr(raster) || anyNA(dates) || anyDuplicated(dates)) {
    stop("Very-wet contribution cache must have one unique date per layer.", call. = FALSE)
  }
  if (!is.null(expected_end_dates)) {
    expected_end_dates <- sort(unique(as.Date(expected_end_dates)))
    if (length(dates) != length(expected_end_dates) || any(dates != expected_end_dates)) {
      stop("Very-wet contribution cache dates do not match the requested sample.", call. = FALSE)
    }
  }
  raster
}

prism_very_wet_contribution_source_signature <- function(
    selection,
    processed_manifest,
    threshold_path,
    threshold_statistic,
    minimum_total_inches) {
  if (!file.exists(threshold_path)) {
    stop("Very-wet threshold file is missing: ", threshold_path, call. = FALSE)
  }
  digest::digest(
    c(
      prism_accumulation_source_signature(selection, processed_manifest),
      paste0("threshold=", unname(tools::md5sum(threshold_path))),
      paste0("statistic=", threshold_statistic),
      paste0("minimum_total=", format(minimum_total_inches, digits = 15))
    ),
    algo = "sha256"
  )
}

build_prism_very_wet_contribution_cache <- function(
    target_date,
    duration_days = 90L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    threshold_statistic = "wet_p95",
    minimum_total_inches = 0.10,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    manifest_path = prism_very_wet_contribution_cache_manifest_path(processed_dir),
    overwrite = FALSE,
    allow_incremental = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  target_date <- as.Date(target_date)
  duration_days <- validate_prism_wet_day_duration(duration_days)
  window_days <- validate_prism_window(window_days)
  minimum_total_inches <- validate_prism_minimum_precipitation_total(
    minimum_total_inches
  )
  reference_groups <- prism_reference_window_dates(
    target_date, baseline_start, baseline_end, window_days
  )
  reference_end_dates <- sort(unique(do.call(c, reference_groups)))
  source_dates <- prism_rolling_source_dates(reference_end_dates, duration_days)
  selection <- select_prism_daily_sources("pcpn", source_dates, aoi_id, processed_manifest)
  threshold <- read_prism_very_wet_threshold(
    threshold_statistic, baseline_start, baseline_end, aoi_id, processed_dir
  )
  source_signature <- prism_very_wet_contribution_source_signature(
    selection, processed_manifest, threshold$path, threshold_statistic,
    minimum_total_inches
  )
  path <- prism_very_wet_contribution_cache_path(
    target_date, duration_days, baseline_start, baseline_end, window_days,
    threshold_statistic, minimum_total_inches, aoi_id, processed_dir
  )
  cache_manifest <- read_prism_manifest(manifest_path)
  existing <- if (nrow(cache_manifest) > 0L &&
      all(c("path", "source_signature", "cache_version", "md5") %in% names(cache_manifest))) {
    cache_manifest[cache_manifest$path == path, , drop = FALSE]
  } else {
    data.frame()
  }
  current <- nrow(existing) > 0L && file.exists(path) &&
    identical(
      as.integer(tail(existing$cache_version, 1L)),
      prism_very_wet_contribution_cache_version
    ) &&
    identical(tail(existing$source_signature, 1L), source_signature) &&
    identical(tail(existing$md5, 1L), unname(tools::md5sum(path)))
  if (current && !overwrite) {
    if (!quiet) {
      message(
        "Using current ", duration_days, "-day very-wet contribution cache for ",
        format(target_date, "%m-%d"), "."
      )
    }
    return(invisible(list(
      raster = read_prism_very_wet_contribution_cache(path, reference_end_dates),
      groups = reference_groups,
      threshold = threshold$raster,
      threshold_path = threshold$path,
      path = path,
      source_signature = source_signature,
      build_method = if ("build_method" %in% names(existing)) {
        tail(existing$build_method, 1L)
      } else {
        "direct"
      },
      refreshed = FALSE
    )))
  }

  samples <- NULL
  build_method <- "direct"
  parent_path <- NA_character_
  parent_md5 <- NA_character_
  previous_date <- target_date - 1L
  target_key <- format(target_date, "%m-%d")
  previous_key <- format(previous_date, "%m-%d")
  can_increment <- isTRUE(allow_incremental) && target_key != "02-29" &&
    previous_key != "02-29"

  if (can_increment) {
    previous_groups <- prism_reference_window_dates(
      previous_date, baseline_start, baseline_end, window_days
    )
    previous_end_dates <- sort(unique(do.call(c, previous_groups)))
    dates_advance_one_day <- length(previous_end_dates) == length(reference_end_dates) &&
      all(previous_end_dates + 1L == reference_end_dates)
    previous_path <- prism_very_wet_contribution_cache_path(
      previous_date, duration_days, baseline_start, baseline_end, window_days,
      threshold_statistic, minimum_total_inches, aoi_id, processed_dir
    )
    previous_record <- if (nrow(cache_manifest) > 0L &&
        all(c("path", "source_signature", "cache_version", "md5") %in% names(cache_manifest))) {
      cache_manifest[cache_manifest$path == previous_path, , drop = FALSE]
    } else {
      data.frame()
    }
    if (dates_advance_one_day && file.exists(previous_path) && nrow(previous_record) > 0L &&
        identical(as.integer(tail(previous_record$cache_version, 1L)),
                  prism_very_wet_contribution_cache_version)) {
      previous_source_dates <- prism_rolling_source_dates(
        previous_end_dates, duration_days
      )
      previous_selection <- select_prism_daily_sources(
        "pcpn", previous_source_dates, aoi_id, processed_manifest
      )
      previous_signature <- prism_very_wet_contribution_source_signature(
        previous_selection, processed_manifest, threshold$path,
        threshold_statistic, minimum_total_inches
      )
      actual_parent_md5 <- unname(tools::md5sum(previous_path))
      parent_current <- identical(
        tail(previous_record$source_signature, 1L), previous_signature
      ) && identical(tail(previous_record$md5, 1L), actual_parent_md5)
      if (parent_current) {
        previous_totals <- build_prism_accumulation_cache(
          accumulation_days = duration_days,
          target_date = previous_date,
          baseline_start = baseline_start,
          baseline_end = baseline_end,
          window_days = window_days,
          aoi_id = aoi_id,
          processed_dir = processed_dir,
          processed_manifest = processed_manifest,
          overwrite = FALSE,
          quiet = quiet
        )
        current_totals <- build_prism_accumulation_cache(
          accumulation_days = duration_days,
          target_date = target_date,
          baseline_start = baseline_start,
          baseline_end = baseline_end,
          window_days = window_days,
          aoi_id = aoi_id,
          processed_dir = processed_dir,
          processed_manifest = processed_manifest,
          overwrite = FALSE,
          quiet = quiet
        )
        if (!quiet) {
          message(
            "Incrementing ", duration_days,
            "-day very-wet contribution cache from ",
            previous_key, " to ", target_key, "."
          )
        }
        previous <- read_prism_very_wet_contribution_cache(
          previous_path, previous_end_dates
        )
        previous_total <- previous_totals$raster
        current_total <- current_totals$raster
        outgoing_dates <- previous_end_dates - duration_days + 1L
        incoming_dates <- reference_end_dates
        edge_dates <- sort(unique(c(outgoing_dates, incoming_dates)))
        edge <- read_prism_best_daily_range(
          "pcpn", edge_dates, aoi_id, processed_manifest
        )
        outgoing <- edge$raster[[match(outgoing_dates, edge$dates)]]
        incoming <- edge$raster[[match(incoming_dates, edge$dates)]]
        terra::compareGeom(previous, previous_total, stopOnError = TRUE)
        terra::compareGeom(previous, current_total, stopOnError = TRUE)
        terra::compareGeom(previous, outgoing, stopOnError = TRUE)
        terra::compareGeom(previous, incoming, stopOnError = TRUE)
        previous_very_wet <- terra::ifel(
          previous_total >= minimum_total_inches & !is.na(previous),
          previous / 100 * previous_total,
          0
        )
        outgoing_very_wet <- terra::ifel(
          outgoing > threshold$raster, outgoing, 0
        )
        incoming_very_wet <- terra::ifel(
          incoming > threshold$raster, incoming, 0
        )
        current_very_wet <- previous_very_wet - outgoing_very_wet +
          incoming_very_wet
        samples <- terra::ifel(
          current_total >= minimum_total_inches,
          100 * current_very_wet / current_total,
          NA
        )
        terra::time(samples) <- reference_end_dates
        names(samples) <- paste0(
          "pcpn_very_wet_contribution_", sprintf("%03d", duration_days),
          "day_", reference_end_dates
        )
        build_method <- "incremental"
        parent_path <- previous_path
        parent_md5 <- actual_parent_md5
      }
    }
  }

  if (is.null(samples)) {
    if (!quiet) {
      message(
        "Building ", duration_days, "-day very-wet contribution cache for ",
        format(target_date, "%m-%d"), " from ", length(source_dates),
        " daily layers."
      )
    }
    collection <- read_prism_best_daily_range(
      "pcpn", source_dates, aoi_id, processed_manifest
    )
    samples <- prism_very_wet_contributions_for_end_dates(
      collection$raster, collection$dates, reference_end_dates,
      threshold$raster, duration_days, minimum_total_inches,
      progress_every, quiet
    )
  }
  write_prism_processed_raster(samples, path, datatype = "FLT8S")
  record <- data.frame(
    product = "rolling_very_wet_contribution_sample",
    cache_version = prism_very_wet_contribution_cache_version,
    aoi_id = aoi_id,
    variable = "pcpn",
    native_units = "percent",
    storage_datatype = "FLT8S",
    duration_days = duration_days,
    threshold_statistic = threshold_statistic,
    threshold_path = threshold$path,
    minimum_total_inches = minimum_total_inches,
    target_calendar_day = format(target_date, "%m-%d"),
    method = sprintf("centered-%02dday", window_days),
    window_days = window_days,
    start_date = as.Date(baseline_start),
    end_date = as.Date(baseline_end),
    sample_layers = terra::nlyr(samples),
    build_method = build_method,
    parent_path = parent_path,
    parent_md5 = parent_md5,
    source_signature = source_signature,
    built_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    bytes = file.info(path)$size,
    md5 = unname(tools::md5sum(path)),
    path = path,
    stringsAsFactors = FALSE
  )
  write_prism_manifest(record, manifest_path)
  if (!quiet) message("Wrote very-wet contribution cache: ", path)
  invisible(list(
    raster = read_prism_very_wet_contribution_cache(path, reference_end_dates),
    groups = reference_groups,
    threshold = threshold$raster,
    threshold_path = threshold$path,
    path = path,
    source_signature = source_signature,
    build_method = build_method,
    refreshed = TRUE
  ))
}

prism_very_wet_contribution_output_path <- function(
    product = c("contribution", "percentile-rank"),
    date,
    duration_days = 90L,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  product <- match.arg(product)
  file.path(
    processed_dir, "prism", aoi_id, "daily", "very-wet-contribution", "pcpn",
    paste0(sprintf("%03d", validate_prism_wet_day_duration(duration_days)), "day"),
    product, paste0(format(as.Date(date)), ".tif")
  )
}

prism_very_wet_contribution_map_path <- function(
    product = c("contribution", "percentile-rank"),
    date = NULL,
    duration_days = 90L,
    maps_dir = swc_paths$maps) {
  product <- match.arg(product)
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  product_label <- if (product == "contribution") "" else "percentile-rank-"
  file.path(
    maps_dir, "prism", "precipitation",
    paste0(
      "pcpn-very-wet-contribution-", product_label,
      sprintf("%03d", validate_prism_wet_day_duration(duration_days)),
      "day-", suffix, ".png"
    )
  )
}

prism_very_wet_contribution_percentile_rank_raster <- function(
    current_contribution,
    reference_contributions,
    duration_days,
    current_date) {
  if (terra::nlyr(current_contribution) != 1L) {
    stop("The current very-wet contribution must contain exactly one layer.", call. = FALSE)
  }
  terra::compareGeom(current_contribution, reference_contributions, stopOnError = TRUE)
  result <- terra::app(c(current_contribution, reference_contributions), fun = function(x, ...) {
    prism_type8_percentile_rank(x[[1L]], x[-1L])
  })
  current_date <- as.Date(current_date)
  names(result) <- paste0(
    "pcpn_very_wet_contribution_percentile_rank_",
    sprintf("%03d", validate_prism_wet_day_duration(duration_days)),
    "day_", current_date
  )
  terra::time(result) <- current_date
  result
}

calculate_prism_very_wet_contribution_products <- function(
    date = NULL,
    duration_days = 90L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    threshold_statistic = "wet_p95",
    minimum_total_inches = 0.10,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    cache_overwrite = FALSE,
    overwrite = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  duration_days <- validate_prism_wet_day_duration(duration_days)
  minimum_total_inches <- validate_prism_minimum_precipitation_total(
    minimum_total_inches
  )
  if (is.null(date)) {
    date <- latest_common_prism_date(
      "pcpn", aoi_id = aoi_id, processed_manifest = processed_manifest
    )
  }
  date <- as.Date(date)
  current_dates <- seq(date - duration_days + 1L, date, by = "day")
  collection <- read_prism_best_daily_range(
    "pcpn", current_dates, aoi_id, processed_manifest
  )
  threshold <- read_prism_very_wet_threshold(
    threshold_statistic, baseline_start, baseline_end, aoi_id, processed_dir
  )
  current <- prism_very_wet_contribution_from_raster(
    collection$raster, threshold$raster, date, duration_days,
    minimum_total_inches
  )
  cache <- build_prism_very_wet_contribution_cache(
    target_date = date,
    duration_days = duration_days,
    baseline_start = baseline_start,
    baseline_end = baseline_end,
    window_days = window_days,
    threshold_statistic = threshold_statistic,
    minimum_total_inches = minimum_total_inches,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    processed_manifest = processed_manifest,
    overwrite = cache_overwrite,
    progress_every = progress_every,
    quiet = quiet
  )
  ranks <- lapply(cache$groups, function(group_dates) {
    selected <- which(as.Date(terra::time(cache$raster)) %in% group_dates)
    prism_very_wet_contribution_percentile_rank_raster(
      current, cache$raster[[selected]], duration_days, date
    )
  })
  rank <- if (length(ranks) == 1L) ranks[[1L]] else Reduce(`+`, ranks) / length(ranks)
  names(rank) <- paste0(
    "pcpn_very_wet_contribution_percentile_rank_", sprintf("%03d", duration_days),
    "day_", date
  )
  terra::time(rank) <- date
  paths <- c(
    contribution = prism_very_wet_contribution_output_path(
      "contribution", date, duration_days, aoi_id, processed_dir
    ),
    `percentile-rank` = prism_very_wet_contribution_output_path(
      "percentile-rank", date, duration_days, aoi_id, processed_dir
    )
  )
  rasters <- list(contribution = current, `percentile-rank` = rank)
  for (product in names(rasters)) {
    if (file.exists(paths[[product]]) && !overwrite) {
      stop(
        "Very-wet contribution output already exists; set `overwrite = TRUE`: ",
        paths[[product]], call. = FALSE
      )
    }
    write_prism_processed_raster(rasters[[product]], paths[[product]])
  }
  list(
    date = date,
    start_date = min(current_dates),
    duration_days = duration_days,
    threshold_statistic = threshold_statistic,
    threshold_path = threshold$path,
    minimum_total_inches = minimum_total_inches,
    contribution = current,
    percentile_rank = rank,
    paths = paths,
    cache = cache
  )
}

build_prism_very_wet_contribution_map <- function(
    raster,
    product = c("contribution", "percentile-rank"),
    date = as.Date(terra::time(raster)),
    duration_days = 90L,
    threshold_statistic = "wet_p95",
    minimum_total_inches = 0.10,
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),
    rivers = southwest_major_rivers()) {
  product <- match.arg(product)
  duration_days <- validate_prism_wet_day_duration(duration_days)
  minimum_total_inches <- validate_prism_minimum_precipitation_total(
    minimum_total_inches
  )
  date <- as.Date(date)
  start_date <- date - duration_days + 1L
  percentile_label <- sub("wet_p", "", threshold_statistic, fixed = TRUE)
  if (product == "contribution") {
    title <- paste0("Precipitation from very wet days in the past ", duration_days, " days")
    subtitle <- paste0(
      format_prism_map_period(start_date, date),
      " | days above local wet-day p", percentile_label,
      " | totals below ", format(minimum_total_inches, nsmall = 2), " inch omitted"
    )
    fill_label <- "Percent of total"
    palette <- c("#d9eef7", "#b3d8ea", "#6baed6", "#41ab5d", "#fdae61", "#d73027", "#7a0177")
    values <- c(0, 10, 25, 50, 75, 90, 100)
    limits <- c(0, 100)
    breaks <- values
    labels <- c("0", "10", "25", "50", "75", "90", "100")
  } else {
    title <- "Very-wet-day contribution percentile rank"
    subtitle <- paste0(
      duration_days, "-day period: ", format_prism_map_period(start_date, date),
      " relative to 1991-2020 | centered 5-day baseline"
    )
    fill_label <- "Percentile rank"
    palette <- c("#7f3b08", "#b35806", "#f1a340", "#f7f7f7", "#998ec3", "#542788", "#2d004b")
    values <- c(0, 10, 25, 50, 75, 90, 100)
    limits <- c(0, 100)
    breaks <- values
    labels <- as.character(values)
  }
  southwest_raster_map(
    raster = raster,
    states = states,
    title = title,
    subtitle = subtitle,
    caption = NULL,
    fill_label = fill_label,
    palette = palette,
    palette_values = values,
    limits = limits,
    breaks = breaks,
    labels = labels,
    counties = counties,
    countries = countries,
    rivers = rivers,
    cities = cities,
    product_id = switch(
      product,
      contribution = "pcpn_very_wet_contribution_90day",
      `percentile-rank` = "pcpn_very_wet_contribution_percentile_90day"
    ),
    mask_to_states = FALSE
  )
}

build_current_prism_very_wet_contribution_maps <- function(
    date = NULL,
    duration_days = 90L,
    threshold_statistic = "wet_p95",
    minimum_total_inches = 0.10,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    progress_every = 25L,
    quiet = FALSE,
    map_products = c("contribution", "percentile-rank")) {
  map_products <- validate_southwest_map_products(
    map_products, c("contribution", "percentile-rank")
  )
  products <- calculate_prism_very_wet_contribution_products(
    date = date,
    duration_days = duration_days,
    threshold_statistic = threshold_statistic,
    minimum_total_inches = minimum_total_inches,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    overwrite = overwrite,
    progress_every = progress_every,
    quiet = quiet
  )
  states <- southwest_state_boundaries()
  counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries()
  cities <- southwest_reference_cities()
  rasters <- list(
    contribution = products$contribution,
    `percentile-rank` = products$percentile_rank
  )
  rasters <- rasters[map_products]
  records <- vector("list", length(rasters))
  for (index in seq_along(rasters)) {
    product <- names(rasters)[[index]]
    if (!quiet) {
      message("Building ", duration_days, "-day very-wet contribution ", product, " map.")
    }
    plot <- build_prism_very_wet_contribution_map(
      rasters[[product]], product, products$date, duration_days,
      products$threshold_statistic, products$minimum_total_inches,
      states, counties, countries, cities
    )
    dated_map <- prism_very_wet_contribution_map_path(
      product, products$date, duration_days, maps_dir
    )
    latest_map <- prism_very_wet_contribution_map_path(
      product, duration_days = duration_days, maps_dir = maps_dir
    )
    footer <- if (product == "contribution") {
      prism_precipitation_footer_text(products$start_date, products$date)
    } else {
      prism_map_footer_text()
    }
    save_southwest_map(plot, dated_map, logo_path = logo_path, footer_text = footer)
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest very-wet contribution map: ", latest_map, call. = FALSE)
    }
    value_range <- range(terra::values(rasters[[product]]), na.rm = TRUE)
    records[[index]] <- data.frame(
      date = products$date,
      duration_days = duration_days,
      product = product,
      minimum = value_range[[1L]],
      maximum = value_range[[2L]],
      raster_path = unname(products$paths[[product]]),
      map_path = dated_map,
      latest_map_path = latest_map,
      stringsAsFactors = FALSE
    )
  }
  invisible(do.call(rbind, records))
}
