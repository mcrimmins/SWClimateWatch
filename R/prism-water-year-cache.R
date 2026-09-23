# Cache historical PRISM water-year-to-date precipitation samples.

prism_water_year_cache_version <- 1L

prism_water_year <- function(date) {
  date <- as.Date(date)
  if (length(date) == 0L || anyNA(date)) {
    stop("`date` must contain valid dates.", call. = FALSE)
  }
  year <- as.integer(format(date, "%Y"))
  month <- as.integer(format(date, "%m"))
  year + as.integer(month >= 10L)
}

prism_water_year_start <- function(date) {
  water_year <- prism_water_year(date)
  as.Date(sprintf("%d-10-01", water_year - 1L))
}

prism_water_year_reference_periods <- function(
    target_date,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end) {
  target_date <- as.Date(target_date)
  baseline_start <- as.Date(baseline_start)
  baseline_end <- as.Date(baseline_end)
  if (length(target_date) != 1L || is.na(target_date)) {
    stop("`target_date` must be one valid date.", call. = FALSE)
  }
  if (length(baseline_start) != 1L || length(baseline_end) != 1L ||
      is.na(baseline_start) || is.na(baseline_end) || baseline_start > baseline_end) {
    stop("The water-year baseline must be a valid inclusive date range.", call. = FALSE)
  }

  water_years <- seq(
    as.integer(format(baseline_start, "%Y")),
    as.integer(format(baseline_end, "%Y"))
  )
  target_month <- as.integer(format(target_date, "%m"))
  target_key <- format(target_date, "%m-%d")
  calendar_years <- water_years - as.integer(target_month >= 10L)
  starts <- as.Date(sprintf("%d-10-01", water_years - 1L))

  if (target_key == "02-29") {
    # A 30-member sample is retained by interpolating each water year's
    # cumulative total halfway between February 28 and March 1. This matches
    # the project's leap-day climatology convention without discarding 22 of
    # the 30 standard-normal years.
    ends <- as.Date(sprintf("%d-02-28", calendar_years))
    interpolation_ends <- as.Date(sprintf("%d-03-01", calendar_years))
    cache_dates <- ends
    leap_method <- "interpolate-feb28-mar01"
  } else {
    ends <- as.Date(sprintf("%d-%s", calendar_years, target_key))
    interpolation_ends <- as.Date(rep(NA_character_, length(water_years)))
    cache_dates <- ends
    leap_method <- "calendar-day"
  }

  if (anyNA(ends) || any(ends < starts)) {
    stop("Could not construct valid water-year reference periods.", call. = FALSE)
  }
  data.frame(
    water_year = water_years,
    start_date = starts,
    end_date = ends,
    interpolation_end_date = interpolation_ends,
    cache_date = cache_dates,
    target_calendar_day = target_key,
    leap_day_method = leap_method,
    stringsAsFactors = FALSE
  )
}

prism_water_year_source_dates <- function(periods) {
  required <- c("start_date", "end_date", "interpolation_end_date")
  missing <- setdiff(required, names(periods))
  if (length(missing) > 0L || nrow(periods) == 0L) {
    stop("Water-year periods are missing required fields.", call. = FALSE)
  }
  dates <- lapply(seq_len(nrow(periods)), function(index) {
    final_date <- periods$interpolation_end_date[[index]]
    if (is.na(final_date)) final_date <- periods$end_date[[index]]
    seq(periods$start_date[[index]], final_date, by = "day")
  })
  sort(unique(as.Date(unlist(dates), origin = "1970-01-01")))
}

prism_water_year_cache_manifest_path <- function(processed_dir = swc_paths$processed) {
  file.path(processed_dir, "prism", "water-year-cache-manifest.csv")
}

prism_water_year_cache_path <- function(
    target_date,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  target_date <- as.Date(target_date)
  if (length(target_date) != 1L || is.na(target_date)) {
    stop("`target_date` must be one valid date.", call. = FALSE)
  }
  baseline_label <- paste0(
    format(as.Date(baseline_start), "%Y%m%d"), "-",
    format(as.Date(baseline_end), "%Y%m%d")
  )
  file.path(
    processed_dir, "prism", aoi_id, "climatology", baseline_label,
    "water-year-samples", "pcpn", "calendar-day",
    paste0(format(target_date, "%m-%d"), ".tif")
  )
}

read_prism_water_year_cache <- function(path, expected_dates = NULL) {
  if (!file.exists(path)) stop("Water-year cache does not exist: ", path, call. = FALSE)
  raster <- terra::rast(path)
  dates <- as.Date(terra::time(raster))
  if (length(dates) != terra::nlyr(raster) || anyNA(dates) || anyDuplicated(dates)) {
    stop("Water-year cache must have one unique valid date per layer: ", path, call. = FALSE)
  }
  if (!is.null(expected_dates)) {
    expected_dates <- as.Date(expected_dates)
    if (length(dates) != length(expected_dates) || any(dates != expected_dates)) {
      stop("Water-year cache dates do not match the requested reference sample.", call. = FALSE)
    }
  }
  raster
}

prism_water_year_totals_for_periods <- function(
    raster,
    dates,
    periods,
    progress_every = 5L,
    quiet = FALSE) {
  dates <- as.Date(dates)
  progress_every <- validate_prism_progress_every(progress_every)
  if (terra::nlyr(raster) != length(dates) || anyNA(dates) || anyDuplicated(dates)) {
    stop("The source raster must have one unique valid date per layer.", call. = FALSE)
  }

  sum_period <- function(start_date, end_date) {
    needed <- seq(start_date, end_date, by = "day")
    selected <- match(needed, dates)
    if (anyNA(selected)) {
      stop(
        "Water-year reference input is incomplete; first missing date: ",
        format(needed[which(is.na(selected))[[1L]]]),
        call. = FALSE
      )
    }
    if (length(selected) == 1L) raster[[selected]] else terra::app(raster[[selected]], sum, na.rm = FALSE)
  }

  started <- proc.time()[["elapsed"]]
  layers <- vector("list", nrow(periods))
  for (index in seq_len(nrow(periods))) {
    primary <- sum_period(periods$start_date[[index]], periods$end_date[[index]])
    alternate_end <- periods$interpolation_end_date[[index]]
    layers[[index]] <- if (is.na(alternate_end)) {
      primary
    } else {
      (primary + sum_period(periods$start_date[[index]], alternate_end)) / 2
    }
    if (!quiet && (index %% progress_every == 0L || index == nrow(periods))) {
      message(
        "  Water-year reference totals: ", index, "/", nrow(periods),
        " water years (", format_prism_elapsed(proc.time()[["elapsed"]] - started), ")."
      )
    }
  }
  result <- do.call(c, layers)
  terra::time(result) <- periods$cache_date
  names(result) <- paste0(
    "pcpn_wytd_wy", periods$water_year, "_", periods$target_calendar_day
  )
  result
}

prism_increment_water_year_totals <- function(
    previous,
    previous_periods,
    periods,
    aoi_id,
    processed_manifest) {
  if (!identical(previous_periods$water_year, periods$water_year)) {
    stop("Previous and current water-year samples do not have matching years.", call. = FALSE)
  }
  additions <- lapply(seq_len(nrow(periods)), function(index) {
    seq(
      previous_periods$end_date[[index]] + 1L,
      periods$end_date[[index]],
      by = "day"
    )
  })
  addition_dates <- sort(unique(as.Date(unlist(additions), origin = "1970-01-01")))
  collection <- read_prism_best_daily_range(
    "pcpn", addition_dates, aoi_id, processed_manifest
  )
  layers <- lapply(seq_len(nrow(periods)), function(index) {
    selected <- match(additions[[index]], collection$dates)
    increment <- if (length(selected) == 1L) {
      collection$raster[[selected]]
    } else {
      terra::app(collection$raster[[selected]], sum, na.rm = FALSE)
    }
    previous[[index]] + increment
  })
  result <- do.call(c, layers)
  terra::time(result) <- periods$cache_date
  names(result) <- paste0(
    "pcpn_wytd_wy", periods$water_year, "_", periods$target_calendar_day
  )
  result
}

build_prism_water_year_cache <- function(
    target_date,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    manifest_path = prism_water_year_cache_manifest_path(processed_dir),
    overwrite = FALSE,
    allow_incremental = TRUE,
    progress_every = 5L,
    quiet = FALSE) {
  target_date <- as.Date(target_date)
  periods <- prism_water_year_reference_periods(target_date, baseline_start, baseline_end)
  source_dates <- prism_water_year_source_dates(periods)
  selection <- select_prism_daily_sources("pcpn", source_dates, aoi_id, processed_manifest)
  source_signature <- prism_accumulation_source_signature(selection, processed_manifest)
  path <- prism_water_year_cache_path(
    target_date, baseline_start, baseline_end, aoi_id, processed_dir
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
    identical(as.integer(tail(existing$cache_version, 1L)), prism_water_year_cache_version)
  checksum_current <- file.exists(path) && nrow(existing) > 0L &&
    "md5" %in% names(existing) &&
    identical(tail(existing$md5, 1L), unname(tools::md5sum(path)))
  current <- file.exists(path) && version_current && checksum_current &&
    identical(tail(existing$source_signature, 1L), source_signature)
  if (current && !overwrite) {
    if (!quiet) message("Using current water-year cache for ", format(target_date, "%m-%d"), ".")
    return(invisible(list(
      raster = read_prism_water_year_cache(path, periods$cache_date),
      periods = periods,
      path = path,
      source_signature = source_signature,
      build_method = "reuse",
      refreshed = FALSE
    )))
  }

  target_key <- format(target_date, "%m-%d")
  previous_date <- target_date - 1L
  previous_key <- format(previous_date, "%m-%d")
  can_increment <- isTRUE(allow_incremental) && target_key != "10-01" &&
    target_key != "02-29" && previous_key != "02-29"
  totals <- NULL
  build_method <- "direct"
  parent_path <- NA_character_
  parent_md5 <- NA_character_

  if (can_increment) {
    previous_periods <- prism_water_year_reference_periods(
      previous_date, baseline_start, baseline_end
    )
    previous_path <- prism_water_year_cache_path(
      previous_date, baseline_start, baseline_end, aoi_id, processed_dir
    )
    previous_record <- if (nrow(cache_manifest) > 0L &&
        all(c("path", "source_signature", "cache_version", "md5") %in% names(cache_manifest))) {
      cache_manifest[cache_manifest$path == previous_path, , drop = FALSE]
    } else {
      data.frame()
    }
    if (file.exists(previous_path) && nrow(previous_record) > 0L &&
        identical(as.integer(tail(previous_record$cache_version, 1L)), prism_water_year_cache_version)) {
      previous_dates <- prism_water_year_source_dates(previous_periods)
      previous_selection <- select_prism_daily_sources(
        "pcpn", previous_dates, aoi_id, processed_manifest
      )
      previous_signature <- prism_accumulation_source_signature(
        previous_selection, processed_manifest
      )
      recorded_md5 <- tail(previous_record$md5, 1L)
      actual_md5 <- unname(tools::md5sum(previous_path))
      parent_current <- identical(
        tail(previous_record$source_signature, 1L), previous_signature
      ) && identical(recorded_md5, actual_md5)
      if (parent_current) {
        if (!quiet) {
          message(
            "Incrementing water-year cache from ", previous_key,
            " to ", target_key, "."
          )
        }
        previous <- read_prism_water_year_cache(
          previous_path, previous_periods$cache_date
        )
        totals <- prism_increment_water_year_totals(
          previous, previous_periods, periods, aoi_id, processed_manifest
        )
        build_method <- "incremental"
        parent_path <- previous_path
        parent_md5 <- actual_md5
      }
    }
  }

  if (is.null(totals)) {
    if (!quiet) {
      message(
        "Building water-year cache for ", target_key, " from ",
        length(source_dates), " daily layers."
      )
    }
    collection <- read_prism_best_daily_range(
      "pcpn", source_dates, aoi_id, processed_manifest
    )
    totals <- prism_water_year_totals_for_periods(
      collection$raster, collection$dates, periods, progress_every, quiet
    )
  }

  # Empirical ranks require preservation of near-ties, as with rolling caches.
  write_prism_processed_raster(totals, path, datatype = "FLT8S")
  record <- data.frame(
    product = "water_year_to_date_sample",
    cache_version = prism_water_year_cache_version,
    aoi_id = aoi_id,
    variable = "pcpn",
    native_units = "inch",
    storage_datatype = "FLT8S",
    target_calendar_day = target_key,
    method = unique(periods$leap_day_method),
    start_date = as.Date(baseline_start),
    end_date = as.Date(baseline_end),
    first_water_year = min(periods$water_year),
    last_water_year = max(periods$water_year),
    sample_layers = terra::nlyr(totals),
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
  if (!quiet) message("Wrote water-year cache: ", path)
  invisible(list(
    raster = read_prism_water_year_cache(path, periods$cache_date),
    periods = periods,
    path = path,
    source_signature = source_signature,
    build_method = build_method,
    refreshed = TRUE
  ))
}
