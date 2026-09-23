# Cache and map rolling mean-temperature percentile ranks.

prism_rolling_temperature_cache_version <- 1L

validate_prism_rolling_temperature_days <- function(days, public_only = FALSE) {
  days <- sort(unique(as.integer(days)))
  if (length(days) == 0L || anyNA(days) || any(days < 1L)) {
    stop("`days` must contain one or more positive integers.", call. = FALSE)
  }
  if (isTRUE(public_only) && any(!days %in% c(7L, 30L, 90L))) {
    stop(
      "Public rolling mean-temperature percentile maps support 7, 30, and 90 days.",
      call. = FALSE
    )
  }
  days
}

prism_rolling_temperature_cache_manifest_path <- function(
    processed_dir = swc_paths$processed) {
  file.path(processed_dir, "prism", "rolling-temperature-cache-manifest.csv")
}

prism_rolling_temperature_cache_path <- function(
    days,
    target_date,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  days <- validate_prism_rolling_temperature_days(days)
  if (length(days) != 1L) stop("Exactly one rolling duration is required.", call. = FALSE)
  window_days <- validate_prism_window(window_days)
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
    "rolling-temperature-samples", "tmean",
    paste0(sprintf("%03d", days), "day"),
    sprintf("centered-%02dday", window_days),
    paste0(format(target_date, "%m-%d"), ".tif")
  )
}

prism_rolling_temperature_source_signature <- function(selection, processed_manifest) {
  paths <- unique(selection$path)
  manifest <- processed_manifest[
    !duplicated(processed_manifest$path, fromLast = TRUE), , drop = FALSE
  ]
  rows <- match(paths, manifest$path)
  if (anyNA(rows)) {
    stop(
      "One or more selected temperature sources are absent from the processed manifest.",
      call. = FALSE
    )
  }
  checksums <- manifest$md5[rows]
  missing <- is.na(checksums) | !nzchar(checksums)
  if (any(missing)) {
    if (any(!file.exists(paths[missing]))) {
      stop("Cannot checksum one or more missing temperature sources.", call. = FALSE)
    }
    checksums[missing] <- unname(tools::md5sum(paths[missing]))
  }
  digest::digest(sort(paste(paths, checksums, sep = "=")), algo = "sha256")
}

prism_rolling_temperature_mean_raster <- function(
    raster,
    days,
    end_date) {
  days <- validate_prism_rolling_temperature_days(days)
  if (length(days) != 1L) stop("Exactly one rolling duration is required.", call. = FALSE)
  dates <- as.Date(terra::time(raster))
  end_date <- as.Date(end_date)
  expected <- seq(end_date - days + 1L, end_date, by = "day")
  if (
    terra::nlyr(raster) != days || length(dates) != days || anyNA(dates) ||
      any(dates != expected)
  ) {
    stop(
      "Rolling mean-temperature input must be complete, ordered, and end on `end_date`.",
      call. = FALSE
    )
  }
  result <- if (days == 1L) raster[[1L]] else terra::app(raster, mean, na.rm = FALSE)
  names(result) <- paste0("tmean_mean_", sprintf("%03d", days), "day_", end_date)
  terra::time(result) <- end_date
  result
}

prism_rolling_temperature_means_for_end_dates <- function(
    raster,
    dates,
    end_dates,
    days,
    progress_every = 25L,
    quiet = FALSE) {
  dates <- as.Date(dates)
  end_dates <- sort(unique(as.Date(end_dates)))
  days <- validate_prism_rolling_temperature_days(days)
  if (length(days) != 1L) stop("Exactly one rolling duration is required.", call. = FALSE)
  progress_every <- validate_prism_progress_every(progress_every)
  if (terra::nlyr(raster) != length(dates) || anyNA(dates) || anyDuplicated(dates)) {
    stop("The source raster must have one unique valid date per layer.", call. = FALSE)
  }

  started <- proc.time()[["elapsed"]]
  layers <- vector("list", length(end_dates))
  for (index in seq_along(end_dates)) {
    needed <- seq(end_dates[[index]] - days + 1L, end_dates[[index]], by = "day")
    selected <- match(needed, dates)
    if (anyNA(selected)) {
      stop(
        "Rolling temperature reference input is incomplete; first missing date: ",
        format(needed[which(is.na(selected))[[1L]]]),
        call. = FALSE
      )
    }
    layers[[index]] <- if (days == 1L) {
      raster[[selected]]
    } else {
      terra::app(raster[[selected]], mean, na.rm = FALSE)
    }
    if (!quiet && (index %% progress_every == 0L || index == length(end_dates))) {
      message(
        "  ", days, "-day temperature reference means: ", index, "/",
        length(end_dates), " ending dates (",
        format_prism_elapsed(proc.time()[["elapsed"]] - started), ")."
      )
    }
  }
  result <- do.call(c, layers)
  terra::time(result) <- end_dates
  names(result) <- paste0(
    "tmean_mean_", sprintf("%03d", days), "day_", end_dates
  )
  result
}

read_prism_rolling_temperature_cache <- function(path, expected_end_dates = NULL) {
  if (!file.exists(path)) stop("Rolling temperature cache does not exist: ", path, call. = FALSE)
  raster <- terra::rast(path)
  dates <- as.Date(terra::time(raster))
  if (length(dates) != terra::nlyr(raster) || anyNA(dates) || anyDuplicated(dates)) {
    stop("Rolling temperature cache must have one unique valid date per layer: ", path, call. = FALSE)
  }
  if (!is.null(expected_end_dates)) {
    expected_end_dates <- sort(unique(as.Date(expected_end_dates)))
    if (length(dates) != length(expected_end_dates) || any(dates != expected_end_dates)) {
      stop("Rolling temperature cache dates do not match the requested sample.", call. = FALSE)
    }
  }
  raster
}

build_prism_rolling_temperature_cache <- function(
    days,
    target_date,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    manifest_path = prism_rolling_temperature_cache_manifest_path(processed_dir),
    overwrite = FALSE,
    allow_incremental = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  days <- validate_prism_rolling_temperature_days(days)
  if (length(days) != 1L) stop("Exactly one rolling duration is required.", call. = FALSE)
  target_date <- as.Date(target_date)
  window_days <- validate_prism_window(window_days)
  reference_groups <- prism_reference_window_dates(
    target_date, baseline_start, baseline_end, window_days
  )
  reference_end_dates <- sort(unique(do.call(c, reference_groups)))
  source_dates <- prism_rolling_source_dates(reference_end_dates, days)
  maxt_selection <- select_prism_daily_sources(
    "maxt", source_dates, aoi_id, processed_manifest
  )
  mint_selection <- select_prism_daily_sources(
    "mint", source_dates, aoi_id, processed_manifest
  )
  selection <- unique(rbind(maxt_selection, mint_selection))
  source_signature <- prism_rolling_temperature_source_signature(
    selection, processed_manifest
  )
  path <- prism_rolling_temperature_cache_path(
    days, target_date, baseline_start, baseline_end,
    window_days, aoi_id, processed_dir
  )

  cache_manifest <- read_prism_manifest(manifest_path)
  existing <- if (
    nrow(cache_manifest) > 0L &&
      all(c("path", "source_signature", "cache_version", "md5") %in% names(cache_manifest))
  ) {
    cache_manifest[cache_manifest$path == path, , drop = FALSE]
  } else {
    data.frame()
  }
  version_current <- nrow(existing) > 0L &&
    "cache_version" %in% names(existing) &&
    identical(
      as.integer(tail(existing$cache_version, 1L)),
      prism_rolling_temperature_cache_version
    )
  checksum_current <- file.exists(path) && nrow(existing) > 0L &&
    identical(tail(existing$md5, 1L), unname(tools::md5sum(path)))
  current <- file.exists(path) && version_current && checksum_current &&
    identical(tail(existing$source_signature, 1L), source_signature)
  if (current && !overwrite) {
    if (!quiet) {
      message(
        "Using current ", days, "-day rolling temperature cache for ",
        format(target_date, "%m-%d"), "."
      )
    }
    return(invisible(list(
      raster = read_prism_rolling_temperature_cache(path, reference_end_dates),
      groups = reference_groups,
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

  means <- NULL
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
    previous_path <- prism_rolling_temperature_cache_path(
      days, previous_date, baseline_start, baseline_end,
      window_days, aoi_id, processed_dir
    )
    previous_record <- if (nrow(cache_manifest) > 0L &&
        all(c("path", "source_signature", "cache_version", "md5") %in% names(cache_manifest))) {
      cache_manifest[cache_manifest$path == previous_path, , drop = FALSE]
    } else {
      data.frame()
    }
    if (dates_advance_one_day && file.exists(previous_path) && nrow(previous_record) > 0L &&
        identical(as.integer(tail(previous_record$cache_version, 1L)),
                  prism_rolling_temperature_cache_version)) {
      previous_source_dates <- prism_rolling_source_dates(previous_end_dates, days)
      previous_maxt_selection <- select_prism_daily_sources(
        "maxt", previous_source_dates, aoi_id, processed_manifest
      )
      previous_mint_selection <- select_prism_daily_sources(
        "mint", previous_source_dates, aoi_id, processed_manifest
      )
      previous_selection <- unique(rbind(
        previous_maxt_selection, previous_mint_selection
      ))
      previous_signature <- prism_rolling_temperature_source_signature(
        previous_selection, processed_manifest
      )
      actual_parent_md5 <- unname(tools::md5sum(previous_path))
      parent_current <- identical(
        tail(previous_record$source_signature, 1L), previous_signature
      ) && identical(tail(previous_record$md5, 1L), actual_parent_md5)
      if (parent_current) {
        if (!quiet) {
          message(
            "Incrementing ", days, "-day rolling temperature cache from ",
            previous_key, " to ", target_key, "."
          )
        }
        previous <- read_prism_rolling_temperature_cache(
          previous_path, previous_end_dates
        )
        outgoing_dates <- previous_end_dates - days + 1L
        incoming_dates <- reference_end_dates
        edge_dates <- sort(unique(c(outgoing_dates, incoming_dates)))
        edge_maxt <- read_prism_best_daily_range(
          "maxt", edge_dates, aoi_id, processed_manifest
        )
        edge_mint <- read_prism_best_daily_range(
          "mint", edge_dates, aoi_id, processed_manifest
        )
        if (!identical(edge_maxt$dates, edge_mint$dates)) {
          stop("Maximum and minimum temperature edge dates do not match.", call. = FALSE)
        }
        edge_tmean <- prism_mean_temperature_raster(
          edge_maxt$raster, edge_mint$raster, edge_maxt$dates
        )
        outgoing <- edge_tmean[[match(outgoing_dates, edge_maxt$dates)]]
        incoming <- edge_tmean[[match(incoming_dates, edge_maxt$dates)]]
        terra::compareGeom(previous, outgoing, stopOnError = TRUE)
        terra::compareGeom(previous, incoming, stopOnError = TRUE)
        means <- (previous * days - outgoing + incoming) / days
        terra::time(means) <- reference_end_dates
        names(means) <- paste0(
          "tmean_mean_", sprintf("%03d", days), "day_", reference_end_dates
        )
        build_method <- "incremental"
        parent_path <- previous_path
        parent_md5 <- actual_parent_md5
      }
    }
  }

  if (is.null(means)) {
    if (!quiet) {
      message(
        "Building ", days, "-day rolling temperature cache for ",
        format(target_date, "%m-%d"), " from ", length(source_dates),
        " daily maximum- and minimum-temperature layers."
      )
    }
    maxt <- read_prism_best_daily_range(
      "maxt", source_dates, aoi_id, processed_manifest
    )
    mint <- read_prism_best_daily_range(
      "mint", source_dates, aoi_id, processed_manifest
    )
    if (!identical(maxt$dates, mint$dates)) {
      stop("Maximum and minimum temperature dates do not match.", call. = FALSE)
    }
    tmean <- prism_mean_temperature_raster(maxt$raster, mint$raster, maxt$dates)
    means <- prism_rolling_temperature_means_for_end_dates(
      tmean, maxt$dates, reference_end_dates, days,
      progress_every = progress_every, quiet = quiet
    )
  }
  # Preserve close historical means so empirical ranks do not acquire
  # artificial ties from single-precision storage.
  write_prism_processed_raster(means, path, datatype = "FLT8S")

  record <- data.frame(
    product = "rolling_temperature_mean_sample",
    cache_version = prism_rolling_temperature_cache_version,
    aoi_id = aoi_id,
    variable = "tmean",
    native_units = "degreeF",
    storage_datatype = "FLT8S",
    days = days,
    target_calendar_day = format(target_date, "%m-%d"),
    method = sprintf("centered-%02dday", window_days),
    window_days = window_days,
    start_date = as.Date(baseline_start),
    end_date = as.Date(baseline_end),
    sample_layers = terra::nlyr(means),
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
  if (!quiet) message("Wrote rolling temperature cache: ", path)
  invisible(list(
    raster = read_prism_rolling_temperature_cache(path, reference_end_dates),
    groups = reference_groups,
    path = path,
    source_signature = source_signature,
    build_method = build_method,
    refreshed = TRUE
  ))
}

prism_rolling_temperature_percentile_rank_raster <- function(
    current_mean,
    reference_means,
    days,
    current_date) {
  if (terra::nlyr(current_mean) != 1L) {
    stop("The current rolling temperature mean must contain one layer.", call. = FALSE)
  }
  days <- validate_prism_rolling_temperature_days(days)
  if (length(days) != 1L) stop("Exactly one rolling duration is required.", call. = FALSE)
  terra::compareGeom(current_mean, reference_means, stopOnError = TRUE)
  result <- terra::app(c(current_mean, reference_means), fun = function(x, ...) {
    prism_type8_percentile_rank(x[[1L]], x[-1L])
  })
  current_date <- as.Date(current_date)
  names(result) <- paste0(
    "tmean_percentile_rank_", sprintf("%03d", days), "day_", current_date
  )
  terra::time(result) <- current_date
  result
}

prism_rolling_temperature_percentile_output_path <- function(
    days,
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  days <- validate_prism_rolling_temperature_days(days)
  if (length(days) != 1L) stop("Exactly one rolling duration is required.", call. = FALSE)
  file.path(
    processed_dir, "prism", aoi_id, "daily", "rolling-percentile-rank", "tmean",
    paste0(sprintf("%03d", days), "day"),
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_rolling_temperature_percentile_map_path <- function(
    days,
    date = NULL,
    maps_dir = swc_paths$maps) {
  days <- validate_prism_rolling_temperature_days(days)
  if (length(days) != 1L) stop("Exactly one rolling duration is required.", call. = FALSE)
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "temperature",
    paste0("tmean-percentile-rank-", sprintf("%02d", days), "day-", suffix, ".png")
  )
}

calculate_prism_rolling_temperature_percentile_rank <- function(
    days,
    date = NULL,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    use_cache = TRUE,
    cache_overwrite = FALSE,
    cache_manifest_path = prism_rolling_temperature_cache_manifest_path(processed_dir),
    output_path = NULL,
    overwrite = FALSE,
    progress_every = 25L,
    quiet = FALSE) {
  days <- validate_prism_rolling_temperature_days(days)
  if (length(days) != 1L) stop("Exactly one rolling duration is required.", call. = FALSE)
  if (is.null(date)) {
    date <- latest_common_prism_date(
      "tmean", aoi_id = aoi_id, processed_manifest = processed_manifest
    )
  }
  date <- as.Date(date)
  current_dates <- seq(date - days + 1L, date, by = "day")
  maxt <- read_prism_best_daily_range(
    "maxt", current_dates, aoi_id, processed_manifest
  )
  mint <- read_prism_best_daily_range(
    "mint", current_dates, aoi_id, processed_manifest
  )
  if (!identical(maxt$dates, mint$dates)) {
    stop("Maximum and minimum temperature dates do not match.", call. = FALSE)
  }
  current_tmean <- prism_mean_temperature_raster(
    maxt$raster, mint$raster, maxt$dates
  )
  current_mean <- prism_rolling_temperature_mean_raster(
    current_tmean, days, date
  )

  reference_groups <- prism_reference_window_dates(
    date, baseline_start, baseline_end, window_days
  )
  reference_end_dates <- sort(unique(do.call(c, reference_groups)))
  if (isTRUE(use_cache)) {
    cache <- build_prism_rolling_temperature_cache(
      days = days,
      target_date = date,
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
    reference_means <- cache$raster
    reference_groups <- cache$groups
  } else {
    source_dates <- prism_rolling_source_dates(reference_end_dates, days)
    historical <- read_prism_temperature_subset(
      "tmean", source_dates, aoi_id, processed_manifest
    )
    reference_means <- prism_rolling_temperature_means_for_end_dates(
      historical$raster, historical$dates, reference_end_dates, days,
      progress_every = progress_every, quiet = quiet
    )
  }

  ranks <- lapply(reference_groups, function(group_dates) {
    selected <- which(as.Date(terra::time(reference_means)) %in% group_dates)
    prism_rolling_temperature_percentile_rank_raster(
      current_mean, reference_means[[selected]], days, date
    )
  })
  result <- if (length(ranks) == 1L) ranks[[1L]] else Reduce(`+`, ranks) / length(ranks)
  names(result) <- paste0(
    "tmean_percentile_rank_", sprintf("%03d", days), "day_", date
  )
  terra::time(result) <- date

  if (is.null(output_path)) {
    output_path <- prism_rolling_temperature_percentile_output_path(
      days, date, aoi_id, processed_dir
    )
  }
  if (file.exists(output_path) && !overwrite) {
    stop(
      "Rolling temperature percentile output already exists; set `overwrite = TRUE`: ",
      output_path,
      call. = FALSE
    )
  }
  write_prism_processed_raster(result, output_path)
  if (!quiet) message("Wrote rolling temperature percentile-rank raster: ", output_path)
  result
}

build_prism_rolling_temperature_percentile_map <- function(
    rank_raster,
    days,
    date = as.Date(terra::time(rank_raster)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities()) {
  days <- validate_prism_rolling_temperature_days(days, public_only = TRUE)
  if (length(days) != 1L) stop("Exactly one rolling duration is required.", call. = FALSE)
  date <- as.Date(date)
  start_date <- date - days + 1L
  southwest_raster_map(
    raster = rank_raster,
    states = states,
    title = paste0(days, "-day mean-temperature percentile rank"),
    subtitle = paste0(
      format_prism_map_period(start_date, date),
      " relative to 1991-2020 | centered 5-day baseline"
    ),
    caption = NULL,
    fill_label = "Percentile rank",
    palette = c(
      "#313695", "#4575b4", "#91bfdb", "#f7f7f7",
      "#fdae61", "#d73027", "#7f0000"
    ),
    palette_values = c(0, 10, 25, 50, 75, 90, 100),
    limits = c(0, 100),
    breaks = c(0, 10, 25, 50, 75, 90, 100),
    labels = c("0", "10", "25", "50", "75", "90", "100"),
    counties = counties,
    countries = countries,
    cities = cities,
    product_id = paste0("tmean_percentile_", sprintf("%02d", days), "day"),
    mask_to_states = FALSE
  )
}

build_current_prism_rolling_temperature_percentile_maps <- function(
    date = NULL,
    days = c(7L, 30L, 90L),
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    cache_overwrite = FALSE,
    progress_every = 25L,
    quiet = FALSE) {
  days <- validate_prism_rolling_temperature_days(days, public_only = TRUE)
  if (is.null(date)) {
    date <- latest_common_prism_date(
      "tmean", aoi_id = aoi_id, processed_manifest = processed_manifest
    )
  }
  date <- as.Date(date)
  states <- southwest_state_boundaries()
  counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries()
  cities <- southwest_reference_cities()
  records <- vector("list", length(days))

  for (index in seq_along(days)) {
    duration <- days[[index]]
    if (!quiet) {
      message(
        "Calculating ", duration,
        "-day mean-temperature percentile rank through ", date, "."
      )
    }
    rank_path <- prism_rolling_temperature_percentile_output_path(
      duration, date, aoi_id, processed_dir
    )
    rank <- calculate_prism_rolling_temperature_percentile_rank(
      days = duration,
      date = date,
      baseline_start = baseline_start,
      baseline_end = baseline_end,
      window_days = window_days,
      aoi_id = aoi_id,
      processed_dir = processed_dir,
      processed_manifest = processed_manifest,
      cache_overwrite = cache_overwrite,
      output_path = rank_path,
      overwrite = overwrite,
      progress_every = progress_every,
      quiet = quiet
    )
    plot <- build_prism_rolling_temperature_percentile_map(
      rank, duration, date,
      states = states,
      counties = counties,
      countries = countries,
      cities = cities
    )
    dated_map <- prism_rolling_temperature_percentile_map_path(
      duration, date, maps_dir
    )
    latest_map <- prism_rolling_temperature_percentile_map_path(
      duration, maps_dir = maps_dir
    )
    save_southwest_map(
      plot,
      dated_map,
      logo_path = logo_path,
      footer_text = prism_map_footer_text(baseline_start, baseline_end)
    )
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest rolling temperature percentile map: ", latest_map, call. = FALSE)
    }
    value_range <- range(terra::values(rank), na.rm = TRUE)
    records[[index]] <- data.frame(
      date = date,
      variable = "tmean",
      days = duration,
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
