# Calculate and map mean precipitation per wet day in a trailing window.

prism_wet_day_intensity_cache_version <- 1L

prism_mean_wet_day_intensity <- function(
    values,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    minimum_wet_days = 1L) {
  minimum_wet_days <- as.integer(minimum_wet_days)
  if (length(values) == 0L || anyNA(values)) return(NA_real_)
  wet <- prism_is_wet_day(values, wet_day_threshold)
  if (sum(wet) < minimum_wet_days) return(NA_real_)
  mean(values[wet])
}

validate_prism_minimum_wet_days <- function(minimum_wet_days, duration_days) {
  minimum_wet_days <- as.integer(minimum_wet_days)
  duration_days <- validate_prism_wet_day_duration(duration_days)
  if (length(minimum_wet_days) != 1L || is.na(minimum_wet_days) ||
      minimum_wet_days < 1L || minimum_wet_days > duration_days) {
    stop(
      "`minimum_wet_days` must be a positive integer no greater than `duration_days`.",
      call. = FALSE
    )
  }
  minimum_wet_days
}

prism_wet_day_intensity_from_raster <- function(
    raster,
    end_date,
    duration_days = 90L,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    minimum_wet_days = 1L) {
  duration_days <- validate_prism_wet_day_duration(duration_days)
  minimum_wet_days <- validate_prism_minimum_wet_days(
    minimum_wet_days, duration_days
  )
  dates <- as.Date(terra::time(raster))
  if (terra::nlyr(raster) != duration_days || length(dates) != terra::nlyr(raster) ||
      anyNA(dates) || anyDuplicated(dates)) {
    stop(
      "The wet-day-intensity input must have one unique valid date per window day.",
      call. = FALSE
    )
  }
  end_date <- as.Date(end_date)
  expected <- seq(end_date - duration_days + 1L, end_date, by = "day")
  if (any(dates != expected)) {
    stop("The wet-day-intensity input must be complete and ordered by date.", call. = FALSE)
  }
  result <- terra::app(
    raster,
    fun = prism_mean_wet_day_intensity,
    wet_day_threshold = wet_day_threshold,
    minimum_wet_days = minimum_wet_days
  )
  names(result) <- paste0(
    "pcpn_wet_day_intensity_", sprintf("%03d", duration_days), "day_", end_date
  )
  terra::time(result) <- end_date
  result
}

prism_wet_day_intensities_for_end_dates <- function(
    raster,
    dates,
    end_dates,
    duration_days = 90L,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    minimum_wet_days = 1L,
    progress_every = 25L,
    quiet = FALSE) {
  dates <- as.Date(dates)
  end_dates <- sort(unique(as.Date(end_dates)))
  duration_days <- validate_prism_wet_day_duration(duration_days)
  minimum_wet_days <- validate_prism_minimum_wet_days(
    minimum_wet_days, duration_days
  )
  progress_every <- validate_prism_progress_every(progress_every)
  if (terra::nlyr(raster) != length(dates) || anyNA(dates) || anyDuplicated(dates)) {
    stop("The wet-day-intensity source must have one unique valid date per layer.", call. = FALSE)
  }
  started <- proc.time()[["elapsed"]]
  layers <- vector("list", length(end_dates))
  for (index in seq_along(end_dates)) {
    needed <- seq(end_dates[[index]] - duration_days + 1L, end_dates[[index]], by = "day")
    selected <- match(needed, dates)
    if (anyNA(selected)) {
      stop(
        "Wet-day-intensity input is incomplete; first missing date: ",
        format(needed[which(is.na(selected))[[1L]]]),
        call. = FALSE
      )
    }
    layers[[index]] <- prism_wet_day_intensity_from_raster(
      raster[[selected]], end_dates[[index]], duration_days,
      wet_day_threshold, minimum_wet_days
    )
    if (!quiet && (index %% progress_every == 0L || index == length(end_dates))) {
      message(
        "  ", duration_days, "-day reference wet-day intensities: ", index,
        "/", length(end_dates), " ending dates (",
        format_prism_elapsed(proc.time()[["elapsed"]] - started), ")."
      )
    }
  }
  result <- do.call(c, layers)
  terra::time(result) <- end_dates
  names(result) <- paste0(
    "pcpn_wet_day_intensity_", sprintf("%03d", duration_days), "day_", end_dates
  )
  result
}

prism_wet_day_intensity_cache_manifest_path <- function(
    processed_dir = swc_paths$processed) {
  file.path(processed_dir, "prism", "wet-day-intensity-cache-manifest.csv")
}

prism_wet_day_intensity_cache_path <- function(
    target_date,
    duration_days = 90L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    minimum_wet_days = 1L,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  duration_days <- validate_prism_wet_day_duration(duration_days)
  minimum_wet_days <- validate_prism_minimum_wet_days(
    minimum_wet_days, duration_days
  )
  window_days <- validate_prism_window(window_days)
  threshold_label <- sprintf("wet-%03din", round(wet_day_threshold * 100))
  baseline_label <- paste0(
    format(as.Date(baseline_start), "%Y%m%d"), "-",
    format(as.Date(baseline_end), "%Y%m%d")
  )
  file.path(
    processed_dir, "prism", aoi_id, "climatology", baseline_label,
    "wet-day-intensity-samples", "pcpn",
    paste0(sprintf("%03d", duration_days), "day"), threshold_label,
    paste0("minimum-", sprintf("%02d", minimum_wet_days), "-wet-days"),
    sprintf("centered-%02dday", window_days),
    paste0(format(as.Date(target_date), "%m-%d"), ".tif")
  )
}

read_prism_wet_day_intensity_cache <- function(path, expected_end_dates = NULL) {
  if (!file.exists(path)) {
    stop("Wet-day-intensity cache does not exist: ", path, call. = FALSE)
  }
  raster <- terra::rast(path)
  dates <- as.Date(terra::time(raster))
  if (length(dates) != terra::nlyr(raster) || anyNA(dates) || anyDuplicated(dates)) {
    stop(
      "Wet-day-intensity cache must have one unique valid date per layer: ",
      path,
      call. = FALSE
    )
  }
  if (!is.null(expected_end_dates)) {
    expected_end_dates <- sort(unique(as.Date(expected_end_dates)))
    if (length(dates) != length(expected_end_dates) || any(dates != expected_end_dates)) {
      stop(
        "Wet-day-intensity cache dates do not match the requested seasonal sample.",
        call. = FALSE
      )
    }
  }
  raster
}

build_prism_wet_day_intensity_cache <- function(
    target_date,
    duration_days = 90L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    minimum_wet_days = 1L,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    manifest_path = prism_wet_day_intensity_cache_manifest_path(processed_dir),
    overwrite = FALSE,
    allow_incremental = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  target_date <- as.Date(target_date)
  duration_days <- validate_prism_wet_day_duration(duration_days)
  minimum_wet_days <- validate_prism_minimum_wet_days(
    minimum_wet_days, duration_days
  )
  window_days <- validate_prism_window(window_days)
  reference_groups <- prism_reference_window_dates(
    target_date, baseline_start, baseline_end, window_days
  )
  reference_end_dates <- sort(unique(do.call(c, reference_groups)))
  source_dates <- prism_rolling_source_dates(reference_end_dates, duration_days)
  selection <- select_prism_daily_sources("pcpn", source_dates, aoi_id, processed_manifest)
  source_signature <- prism_accumulation_source_signature(selection, processed_manifest)
  path <- prism_wet_day_intensity_cache_path(
    target_date, duration_days, baseline_start, baseline_end, window_days,
    wet_day_threshold, minimum_wet_days, aoi_id, processed_dir
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
      prism_wet_day_intensity_cache_version
    ) &&
    identical(tail(existing$source_signature, 1L), source_signature) &&
    identical(tail(existing$md5, 1L), unname(tools::md5sum(path)))
  if (current && !overwrite) {
    if (!quiet) {
      message(
        "Using current ", duration_days, "-day wet-day-intensity cache for ",
        format(target_date, "%m-%d"), "."
      )
    }
    return(invisible(list(
      raster = read_prism_wet_day_intensity_cache(path, reference_end_dates),
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

  samples <- NULL
  build_method <- "direct"
  parent_path <- NA_character_
  parent_md5 <- NA_character_
  previous_date <- target_date - 1L
  target_key <- format(target_date, "%m-%d")
  previous_key <- format(previous_date, "%m-%d")
  can_increment <- isTRUE(allow_incremental) && minimum_wet_days == 1L &&
    target_key != "02-29" && previous_key != "02-29"

  if (can_increment) {
    previous_groups <- prism_reference_window_dates(
      previous_date, baseline_start, baseline_end, window_days
    )
    previous_end_dates <- sort(unique(do.call(c, previous_groups)))
    dates_advance_one_day <- length(previous_end_dates) == length(reference_end_dates) &&
      all(previous_end_dates + 1L == reference_end_dates)
    previous_path <- prism_wet_day_intensity_cache_path(
      previous_date, duration_days, baseline_start, baseline_end, window_days,
      wet_day_threshold, minimum_wet_days, aoi_id, processed_dir
    )
    previous_record <- if (nrow(cache_manifest) > 0L &&
        all(c("path", "source_signature", "cache_version", "md5") %in% names(cache_manifest))) {
      cache_manifest[cache_manifest$path == previous_path, , drop = FALSE]
    } else {
      data.frame()
    }
    if (dates_advance_one_day && file.exists(previous_path) && nrow(previous_record) > 0L &&
        identical(as.integer(tail(previous_record$cache_version, 1L)),
                  prism_wet_day_intensity_cache_version)) {
      previous_source_dates <- prism_rolling_source_dates(
        previous_end_dates, duration_days
      )
      previous_selection <- select_prism_daily_sources(
        "pcpn", previous_source_dates, aoi_id, processed_manifest
      )
      previous_signature <- prism_accumulation_source_signature(
        previous_selection, processed_manifest
      )
      actual_parent_md5 <- unname(tools::md5sum(previous_path))
      parent_current <- identical(
        tail(previous_record$source_signature, 1L), previous_signature
      ) && identical(tail(previous_record$md5, 1L), actual_parent_md5)
      if (parent_current) {
        previous_counts <- build_prism_wet_day_count_cache(
          target_date = previous_date,
          duration_days = duration_days,
          baseline_start = baseline_start,
          baseline_end = baseline_end,
          window_days = window_days,
          wet_day_threshold = wet_day_threshold,
          aoi_id = aoi_id,
          processed_dir = processed_dir,
          processed_manifest = processed_manifest,
          overwrite = FALSE,
          quiet = quiet
        )
        current_counts <- build_prism_wet_day_count_cache(
          target_date = target_date,
          duration_days = duration_days,
          baseline_start = baseline_start,
          baseline_end = baseline_end,
          window_days = window_days,
          wet_day_threshold = wet_day_threshold,
          aoi_id = aoi_id,
          processed_dir = processed_dir,
          processed_manifest = processed_manifest,
          overwrite = FALSE,
          quiet = quiet
        )
        if (!quiet) {
          message(
            "Incrementing ", duration_days, "-day wet-day-intensity cache from ",
            previous_key, " to ", target_key, "."
          )
        }
        previous <- read_prism_wet_day_intensity_cache(
          previous_path, previous_end_dates
        )
        previous_count <- previous_counts$raster
        current_count <- current_counts$raster
        outgoing_dates <- previous_end_dates - duration_days + 1L
        incoming_dates <- reference_end_dates
        edge_dates <- sort(unique(c(outgoing_dates, incoming_dates)))
        edge <- read_prism_best_daily_range(
          "pcpn", edge_dates, aoi_id, processed_manifest
        )
        outgoing <- edge$raster[[match(outgoing_dates, edge$dates)]]
        incoming <- edge$raster[[match(incoming_dates, edge$dates)]]
        terra::compareGeom(previous, previous_count, stopOnError = TRUE)
        terra::compareGeom(previous, current_count, stopOnError = TRUE)
        terra::compareGeom(previous, outgoing, stopOnError = TRUE)
        terra::compareGeom(previous, incoming, stopOnError = TRUE)
        previous_sum <- terra::ifel(
          previous_count > 0 & !is.na(previous), previous * previous_count, 0
        )
        outgoing_wet <- terra::ifel(
          prism_is_wet_day(outgoing, wet_day_threshold), outgoing, 0
        )
        incoming_wet <- terra::ifel(
          prism_is_wet_day(incoming, wet_day_threshold), incoming, 0
        )
        current_sum <- previous_sum - outgoing_wet + incoming_wet
        samples <- terra::ifel(
          current_count >= minimum_wet_days,
          current_sum / current_count,
          NA
        )
        terra::time(samples) <- reference_end_dates
        names(samples) <- paste0(
          "pcpn_wet_day_intensity_", sprintf("%03d", duration_days),
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
        "Building ", duration_days, "-day wet-day-intensity cache for ",
        format(target_date, "%m-%d"), " from ", length(source_dates),
        " daily layers."
      )
    }
    collection <- read_prism_best_daily_range(
      "pcpn", source_dates, aoi_id, processed_manifest
    )
    samples <- prism_wet_day_intensities_for_end_dates(
      collection$raster, collection$dates, reference_end_dates,
      duration_days, wet_day_threshold, minimum_wet_days,
      progress_every, quiet
    )
  }
  write_prism_processed_raster(samples, path, datatype = "FLT8S")
  record <- data.frame(
    product = "rolling_wet_day_intensity_sample",
    cache_version = prism_wet_day_intensity_cache_version,
    aoi_id = aoi_id,
    variable = "pcpn",
    native_units = "inch_per_wet_day",
    storage_datatype = "FLT8S",
    duration_days = duration_days,
    wet_day_threshold_inches = wet_day_threshold,
    minimum_wet_days = minimum_wet_days,
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
  if (!quiet) message("Wrote wet-day-intensity cache: ", path)
  invisible(list(
    raster = read_prism_wet_day_intensity_cache(path, reference_end_dates),
    groups = reference_groups,
    path = path,
    source_signature = source_signature,
    build_method = build_method,
    refreshed = TRUE
  ))
}

prism_wet_day_intensity_output_path <- function(
    product = c("intensity", "percentile-rank"),
    date,
    duration_days = 90L,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  product <- match.arg(product)
  file.path(
    processed_dir, "prism", aoi_id, "daily", "wet-day-intensity", "pcpn",
    paste0(sprintf("%03d", validate_prism_wet_day_duration(duration_days)), "day"),
    product, paste0(format(as.Date(date)), ".tif")
  )
}

prism_wet_day_intensity_map_path <- function(
    product = c("intensity", "percentile-rank"),
    date = NULL,
    duration_days = 90L,
    maps_dir = swc_paths$maps) {
  product <- match.arg(product)
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  product_label <- if (product == "intensity") "" else "percentile-rank-"
  file.path(
    maps_dir, "prism", "precipitation",
    paste0(
      "pcpn-wet-day-intensity-", product_label,
      sprintf("%03d", validate_prism_wet_day_duration(duration_days)),
      "day-", suffix, ".png"
    )
  )
}

prism_wet_day_intensity_percentile_rank_raster <- function(
    current_intensity,
    reference_intensities,
    duration_days,
    current_date) {
  if (terra::nlyr(current_intensity) != 1L) {
    stop("The current wet-day intensity must contain exactly one layer.", call. = FALSE)
  }
  terra::compareGeom(current_intensity, reference_intensities, stopOnError = TRUE)
  result <- terra::app(c(current_intensity, reference_intensities), fun = function(x, ...) {
    prism_type8_percentile_rank(x[[1L]], x[-1L])
  })
  current_date <- as.Date(current_date)
  names(result) <- paste0(
    "pcpn_wet_day_intensity_percentile_rank_",
    sprintf("%03d", validate_prism_wet_day_duration(duration_days)),
    "day_", current_date
  )
  terra::time(result) <- current_date
  result
}

calculate_prism_wet_day_intensity_products <- function(
    date = NULL,
    duration_days = 90L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    minimum_wet_days = 1L,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    cache_overwrite = FALSE,
    overwrite = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  duration_days <- validate_prism_wet_day_duration(duration_days)
  minimum_wet_days <- validate_prism_minimum_wet_days(
    minimum_wet_days, duration_days
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
  current <- prism_wet_day_intensity_from_raster(
    collection$raster, date, duration_days, wet_day_threshold, minimum_wet_days
  )
  cache <- build_prism_wet_day_intensity_cache(
    target_date = date,
    duration_days = duration_days,
    baseline_start = baseline_start,
    baseline_end = baseline_end,
    window_days = window_days,
    wet_day_threshold = wet_day_threshold,
    minimum_wet_days = minimum_wet_days,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    processed_manifest = processed_manifest,
    overwrite = cache_overwrite,
    progress_every = progress_every,
    quiet = quiet
  )
  ranks <- lapply(cache$groups, function(group_dates) {
    selected <- which(as.Date(terra::time(cache$raster)) %in% group_dates)
    prism_wet_day_intensity_percentile_rank_raster(
      current, cache$raster[[selected]], duration_days, date
    )
  })
  rank <- if (length(ranks) == 1L) ranks[[1L]] else Reduce(`+`, ranks) / length(ranks)
  names(rank) <- paste0(
    "pcpn_wet_day_intensity_percentile_rank_", sprintf("%03d", duration_days),
    "day_", date
  )
  terra::time(rank) <- date
  paths <- c(
    intensity = prism_wet_day_intensity_output_path(
      "intensity", date, duration_days, aoi_id, processed_dir
    ),
    `percentile-rank` = prism_wet_day_intensity_output_path(
      "percentile-rank", date, duration_days, aoi_id, processed_dir
    )
  )
  rasters <- list(intensity = current, `percentile-rank` = rank)
  for (product in names(rasters)) {
    if (file.exists(paths[[product]]) && !overwrite) {
      stop(
        "Wet-day-intensity output already exists; set `overwrite = TRUE`: ",
        paths[[product]],
        call. = FALSE
      )
    }
    write_prism_processed_raster(rasters[[product]], paths[[product]])
  }
  list(
    date = date,
    start_date = min(current_dates),
    duration_days = duration_days,
    wet_day_threshold = wet_day_threshold,
    minimum_wet_days = minimum_wet_days,
    intensity = current,
    percentile_rank = rank,
    paths = paths,
    cache = cache
  )
}

build_prism_wet_day_intensity_map <- function(
    raster,
    product = c("intensity", "percentile-rank"),
    date = as.Date(terra::time(raster)),
    duration_days = 90L,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    minimum_wet_days = 1L,
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),
    rivers = southwest_major_rivers()) {
  product <- match.arg(product)
  duration_days <- validate_prism_wet_day_duration(duration_days)
  minimum_wet_days <- validate_prism_minimum_wet_days(
    minimum_wet_days, duration_days
  )
  date <- as.Date(date)
  start_date <- date - duration_days + 1L
  if (product == "intensity") {
    title <- paste0("Mean precipitation per wet day in the past ", duration_days, " days")
    subtitle <- paste0(
      format_prism_map_period(start_date, date),
      " | wet day threshold: ", format(wet_day_threshold, trim = TRUE), " inch"
    )
    fill_label <- "Inches per wet day"
    palette <- c(
      "#d9f0ff", "#92c5de", "#4eb3d3", "#41ab5d",
      "#addd8e", "#fee08b", "#f46d43", "#9e0142"
    )
    values <- c(0.04, 0.1, 0.2, 0.35, 0.5, 0.75, 1, 1.5)
    limits <- c(0.04, 1.5)
    breaks <- c(0.04, 0.25, 0.5, 0.75, 1, 1.5)
    labels <- c("0.04", "0.25", "0.50", "0.75", "1.00", "1.50+")
  } else {
    title <- "Wet-day intensity percentile rank"
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
      intensity = "pcpn_wet_day_intensity_90day",
      `percentile-rank` = "pcpn_wet_day_intensity_percentile_90day"
    ),
    mask_to_states = FALSE
  )
}

build_current_prism_wet_day_intensity_maps <- function(
    date = NULL,
    duration_days = 90L,
    minimum_wet_days = 1L,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    progress_every = 25L,
    quiet = FALSE,
    map_products = c("intensity", "percentile-rank")) {
  map_products <- validate_southwest_map_products(
    map_products, c("intensity", "percentile-rank")
  )
  products <- calculate_prism_wet_day_intensity_products(
    date = date,
    duration_days = duration_days,
    minimum_wet_days = minimum_wet_days,
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
    intensity = products$intensity,
    `percentile-rank` = products$percentile_rank
  )
  rasters <- rasters[map_products]
  records <- vector("list", length(rasters))
  for (index in seq_along(rasters)) {
    product <- names(rasters)[[index]]
    if (!quiet) {
      message("Building ", duration_days, "-day wet-day-intensity ", product, " map.")
    }
    plot <- build_prism_wet_day_intensity_map(
      rasters[[product]], product, products$date, duration_days,
      products$wet_day_threshold, products$minimum_wet_days,
      states, counties, countries, cities
    )
    dated_map <- prism_wet_day_intensity_map_path(
      product, products$date, duration_days, maps_dir
    )
    latest_map <- prism_wet_day_intensity_map_path(
      product, duration_days = duration_days, maps_dir = maps_dir
    )
    footer <- if (product == "intensity") {
      prism_precipitation_footer_text(products$start_date, products$date)
    } else {
      prism_map_footer_text()
    }
    save_southwest_map(plot, dated_map, logo_path = logo_path, footer_text = footer)
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest wet-day-intensity map: ", latest_map, call. = FALSE)
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
