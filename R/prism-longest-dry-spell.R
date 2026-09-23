# Calculate and map the longest PRISM dry spell in a trailing window.

prism_longest_dry_spell_cache_version <- 1L

validate_prism_longest_dry_spell_duration <- function(duration_days) {
  duration_days <- as.integer(duration_days)
  if (length(duration_days) != 1L || is.na(duration_days) || duration_days < 1L) {
    stop("`duration_days` must be a positive integer.", call. = FALSE)
  }
  duration_days
}

prism_longest_dry_run <- function(values, wet_day_threshold) {
  if (length(values) == 0L || anyNA(values)) return(NA_real_)
  dry <- !prism_is_wet_day(values, wet_day_threshold)
  runs <- rle(dry)
  if (!any(runs$values)) return(0)
  max(runs$lengths[runs$values])
}

prism_longest_dry_runs_for_windows <- function(
    values,
    window_starts,
    duration_days,
    wet_day_threshold) {
  window_starts <- as.integer(window_starts)
  duration_days <- validate_prism_longest_dry_spell_duration(duration_days)
  vapply(window_starts, function(start) {
    selected <- start:(start + duration_days - 1L)
    prism_longest_dry_run(values[selected], wet_day_threshold)
  }, numeric(1))
}

prism_longest_dry_spell_from_raster <- function(
    raster,
    end_date,
    duration_days = 180L,
    wet_day_threshold = swc_prism$wet_day_threshold_inches) {
  duration_days <- validate_prism_longest_dry_spell_duration(duration_days)
  dates <- as.Date(terra::time(raster))
  if (terra::nlyr(raster) != duration_days || length(dates) != terra::nlyr(raster) ||
      anyNA(dates) || anyDuplicated(dates)) {
    stop(
      "The longest-dry-spell input must have one unique valid date per window day.",
      call. = FALSE
    )
  }
  expected <- seq(as.Date(end_date) - duration_days + 1L, as.Date(end_date), by = "day")
  if (any(dates != expected)) {
    stop("The longest-dry-spell input must be complete and ordered by date.", call. = FALSE)
  }
  if (length(wet_day_threshold) != 1L || !is.finite(wet_day_threshold) ||
      wet_day_threshold < 0) {
    stop("`wet_day_threshold` must be one non-negative number.", call. = FALSE)
  }
  result <- terra::app(
    raster,
    fun = prism_longest_dry_run,
    wet_day_threshold = wet_day_threshold
  )
  end_date <- as.Date(end_date)
  names(result) <- paste0(
    "pcpn_longest_dry_spell_", sprintf("%03d", duration_days), "day_", end_date
  )
  terra::time(result) <- end_date
  result
}

prism_longest_dry_spells_for_end_dates <- function(
    raster,
    dates,
    end_dates,
    duration_days = 180L,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    progress_every = 25L,
    quiet = FALSE) {
  dates <- as.Date(dates)
  end_dates <- sort(unique(as.Date(end_dates)))
  duration_days <- validate_prism_longest_dry_spell_duration(duration_days)
  progress_every <- validate_prism_progress_every(progress_every)
  if (terra::nlyr(raster) != length(dates) || anyNA(dates) || anyDuplicated(dates)) {
    stop("The longest-dry-spell source must have one unique valid date per layer.", call. = FALSE)
  }
  # Reference dates occur in short consecutive groups (normally five dates per
  # baseline year). Calculate every window in a group with one terra pass
  # instead of reopening a 180-layer calculation for each ending date.
  group_id <- cumsum(c(TRUE, diff(as.integer(end_dates)) != 1L))
  end_date_groups <- split(end_dates, group_id)
  started <- proc.time()[["elapsed"]]
  layers <- vector("list", length(end_date_groups))
  completed <- 0L
  for (index in seq_along(end_date_groups)) {
    group_dates <- end_date_groups[[index]]
    needed <- seq(
      min(group_dates) - duration_days + 1L,
      max(group_dates),
      by = "day"
    )
    selected <- match(needed, dates)
    if (anyNA(selected)) {
      stop(
        "Longest-dry-spell input is incomplete; first missing date: ",
        format(needed[which(is.na(selected))[[1L]]]),
        call. = FALSE
      )
    }
    window_starts <- as.integer(
      group_dates - duration_days + 1L - min(needed)
    ) + 1L
    layers[[index]] <- terra::app(
      raster[[selected]],
      fun = prism_longest_dry_runs_for_windows,
      window_starts = window_starts,
      duration_days = duration_days,
      wet_day_threshold = wet_day_threshold
    )
    terra::time(layers[[index]]) <- group_dates
    names(layers[[index]]) <- paste0(
      "pcpn_longest_dry_spell_", sprintf("%03d", duration_days),
      "day_", group_dates
    )
    completed <- completed + length(group_dates)
    if (!quiet && (completed %% progress_every == 0L ||
        index == length(end_date_groups))) {
      message(
        "  ", duration_days, "-day reference longest dry spells: ", completed, "/",
        length(end_dates), " ending dates (",
        format_prism_elapsed(proc.time()[["elapsed"]] - started), ")."
      )
    }
  }
  result <- do.call(c, layers)
  ordering <- order(as.Date(terra::time(result)))
  result <- result[[ordering]]
  terra::time(result) <- end_dates
  names(result) <- paste0(
    "pcpn_longest_dry_spell_", sprintf("%03d", duration_days), "day_", end_dates
  )
  result
}

prism_longest_dry_spell_cache_manifest_path <- function(
    processed_dir = swc_paths$processed) {
  file.path(processed_dir, "prism", "longest-dry-spell-cache-manifest.csv")
}

prism_longest_dry_spell_cache_path <- function(
    target_date,
    duration_days = 180L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  duration_days <- validate_prism_longest_dry_spell_duration(duration_days)
  window_days <- validate_prism_window(window_days)
  threshold_label <- sprintf("wet-%03din", round(wet_day_threshold * 100))
  baseline_label <- paste0(
    format(as.Date(baseline_start), "%Y%m%d"), "-",
    format(as.Date(baseline_end), "%Y%m%d")
  )
  file.path(
    processed_dir, "prism", aoi_id, "climatology", baseline_label,
    "longest-dry-spell-samples", "pcpn",
    paste0(sprintf("%03d", duration_days), "day"), threshold_label,
    sprintf("centered-%02dday", window_days),
    paste0(format(as.Date(target_date), "%m-%d"), ".tif")
  )
}

read_prism_longest_dry_spell_cache <- function(path, expected_end_dates = NULL) {
  if (!file.exists(path)) {
    stop("Longest-dry-spell cache does not exist: ", path, call. = FALSE)
  }
  raster <- terra::rast(path)
  dates <- as.Date(terra::time(raster))
  if (length(dates) != terra::nlyr(raster) || anyNA(dates) || anyDuplicated(dates)) {
    stop(
      "Longest-dry-spell cache must have one unique valid date per layer: ",
      path,
      call. = FALSE
    )
  }
  if (!is.null(expected_end_dates)) {
    expected_end_dates <- sort(unique(as.Date(expected_end_dates)))
    if (length(dates) != length(expected_end_dates) || any(dates != expected_end_dates)) {
      stop(
        "Longest-dry-spell cache dates do not match the requested seasonal sample.",
        call. = FALSE
      )
    }
  }
  raster
}

build_prism_longest_dry_spell_cache <- function(
    target_date,
    duration_days = 180L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    manifest_path = prism_longest_dry_spell_cache_manifest_path(processed_dir),
    overwrite = FALSE,
    progress_every = 25L,
    quiet = FALSE) {
  target_date <- as.Date(target_date)
  duration_days <- validate_prism_longest_dry_spell_duration(duration_days)
  window_days <- validate_prism_window(window_days)
  reference_groups <- prism_reference_window_dates(
    target_date, baseline_start, baseline_end, window_days
  )
  reference_end_dates <- sort(unique(do.call(c, reference_groups)))
  source_dates <- prism_rolling_source_dates(reference_end_dates, duration_days)
  selection <- select_prism_daily_sources("pcpn", source_dates, aoi_id, processed_manifest)
  source_signature <- prism_accumulation_source_signature(selection, processed_manifest)
  path <- prism_longest_dry_spell_cache_path(
    target_date, duration_days, baseline_start, baseline_end, window_days,
    wet_day_threshold, aoi_id, processed_dir
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
      prism_longest_dry_spell_cache_version
    ) &&
    identical(tail(existing$source_signature, 1L), source_signature) &&
    identical(tail(existing$md5, 1L), unname(tools::md5sum(path)))
  if (current && !overwrite) {
    if (!quiet) {
      message(
        "Using current ", duration_days, "-day longest-dry-spell cache for ",
        format(target_date, "%m-%d"), "."
      )
    }
    return(invisible(list(
      raster = read_prism_longest_dry_spell_cache(path, reference_end_dates),
      groups = reference_groups,
      path = path,
      source_signature = source_signature,
      refreshed = FALSE
    )))
  }

  if (!quiet) {
    message(
      "Building ", duration_days, "-day longest-dry-spell cache for ",
      format(target_date, "%m-%d"), " from ", length(source_dates),
      " daily layers."
    )
  }
  collection <- read_prism_best_daily_range(
    "pcpn", source_dates, aoi_id, processed_manifest
  )
  samples <- prism_longest_dry_spells_for_end_dates(
    collection$raster, collection$dates, reference_end_dates,
    duration_days, wet_day_threshold, progress_every, quiet
  )
  write_prism_processed_raster(samples, path, datatype = "FLT4S")
  record <- data.frame(
    product = "rolling_longest_dry_spell_sample",
    cache_version = prism_longest_dry_spell_cache_version,
    aoi_id = aoi_id,
    variable = "pcpn",
    native_units = "day",
    storage_datatype = "FLT4S",
    duration_days = duration_days,
    wet_day_threshold_inches = wet_day_threshold,
    target_calendar_day = format(target_date, "%m-%d"),
    method = sprintf("centered-%02dday", window_days),
    window_days = window_days,
    start_date = as.Date(baseline_start),
    end_date = as.Date(baseline_end),
    sample_layers = terra::nlyr(samples),
    source_signature = source_signature,
    built_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    bytes = file.info(path)$size,
    md5 = unname(tools::md5sum(path)),
    path = path,
    stringsAsFactors = FALSE
  )
  write_prism_manifest(record, manifest_path)
  if (!quiet) message("Wrote longest-dry-spell cache: ", path)
  invisible(list(
    raster = read_prism_longest_dry_spell_cache(path, reference_end_dates),
    groups = reference_groups,
    path = path,
    source_signature = source_signature,
    refreshed = TRUE
  ))
}

prism_longest_dry_spell_output_path <- function(
    product = c("length", "percentile-rank"),
    date,
    duration_days = 180L,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  product <- match.arg(product)
  file.path(
    processed_dir, "prism", aoi_id, "daily", "longest-dry-spell", "pcpn",
    paste0(sprintf("%03d", validate_prism_longest_dry_spell_duration(duration_days)), "day"),
    product, paste0(format(as.Date(date)), ".tif")
  )
}

prism_longest_dry_spell_map_path <- function(
    product = c("length", "percentile-rank"),
    date = NULL,
    duration_days = 180L,
    maps_dir = swc_paths$maps) {
  product <- match.arg(product)
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  product_label <- if (product == "length") "" else "percentile-rank-"
  file.path(
    maps_dir, "prism", "precipitation",
    paste0(
      "pcpn-longest-dry-spell-", product_label,
      sprintf("%03d", validate_prism_longest_dry_spell_duration(duration_days)),
      "day-", suffix, ".png"
    )
  )
}

prism_longest_dry_spell_percentile_rank_raster <- function(
    current_length,
    reference_lengths,
    duration_days,
    current_date) {
  if (terra::nlyr(current_length) != 1L) {
    stop("The current longest dry spell must contain exactly one layer.", call. = FALSE)
  }
  terra::compareGeom(current_length, reference_lengths, stopOnError = TRUE)
  result <- terra::app(c(current_length, reference_lengths), fun = function(x, ...) {
    prism_type8_percentile_rank(x[[1L]], x[-1L])
  })
  current_date <- as.Date(current_date)
  names(result) <- paste0(
    "pcpn_longest_dry_spell_percentile_rank_",
    sprintf("%03d", validate_prism_longest_dry_spell_duration(duration_days)),
    "day_", current_date
  )
  terra::time(result) <- current_date
  result
}

calculate_prism_longest_dry_spell_products <- function(
    date = NULL,
    duration_days = 180L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    cache_overwrite = FALSE,
    overwrite = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  duration_days <- validate_prism_longest_dry_spell_duration(duration_days)
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
  current <- prism_longest_dry_spell_from_raster(
    collection$raster, date, duration_days, wet_day_threshold
  )
  cache <- build_prism_longest_dry_spell_cache(
    target_date = date,
    duration_days = duration_days,
    baseline_start = baseline_start,
    baseline_end = baseline_end,
    window_days = window_days,
    wet_day_threshold = wet_day_threshold,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    processed_manifest = processed_manifest,
    overwrite = cache_overwrite,
    progress_every = progress_every,
    quiet = quiet
  )
  ranks <- lapply(cache$groups, function(group_dates) {
    selected <- which(as.Date(terra::time(cache$raster)) %in% group_dates)
    prism_longest_dry_spell_percentile_rank_raster(
      current, cache$raster[[selected]], duration_days, date
    )
  })
  rank <- if (length(ranks) == 1L) ranks[[1L]] else Reduce(`+`, ranks) / length(ranks)
  names(rank) <- paste0(
    "pcpn_longest_dry_spell_percentile_rank_", sprintf("%03d", duration_days),
    "day_", date
  )
  terra::time(rank) <- date
  paths <- c(
    length = prism_longest_dry_spell_output_path(
      "length", date, duration_days, aoi_id, processed_dir
    ),
    `percentile-rank` = prism_longest_dry_spell_output_path(
      "percentile-rank", date, duration_days, aoi_id, processed_dir
    )
  )
  rasters <- list(length = current, `percentile-rank` = rank)
  for (product in names(rasters)) {
    if (file.exists(paths[[product]]) && !overwrite) {
      stop(
        "Longest-dry-spell output already exists; set `overwrite = TRUE`: ",
        paths[[product]],
        call. = FALSE
      )
    }
    write_prism_processed_raster(rasters[[product]], paths[[product]])
  }
  list(
    date = date,
    start_date = date - duration_days + 1L,
    duration_days = duration_days,
    wet_day_threshold = wet_day_threshold,
    length = current,
    percentile_rank = rank,
    paths = paths,
    cache = cache
  )
}

build_prism_longest_dry_spell_map <- function(
    raster,
    product = c("length", "percentile-rank"),
    date = as.Date(terra::time(raster)),
    duration_days = 180L,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),
    rivers = southwest_major_rivers()) {
  product <- match.arg(product)
  duration_days <- validate_prism_longest_dry_spell_duration(duration_days)
  date <- as.Date(date)
  start_date <- date - duration_days + 1L
  if (product == "length") {
    title <- paste0("Longest dry spell in the past ", duration_days, " days")
    subtitle <- paste0(
      format_prism_map_period(start_date, date),
      " | wet day threshold: ", format(wet_day_threshold, trim = TRUE), " inch"
    )
    fill_label <- "Longest dry spell (days)"
    palette <- c(
      "#1a9850", "#91cf60", "#d9ef8b", "#fee08b",
      "#fdae61", "#f46d43", "#d73027", "#7f0000"
    )
    values <- c(0, 7, 14, 30, 60, 90, 120, 180)
    limits <- c(0, 180)
    breaks <- c(0, 14, 30, 60, 90, 120, 180)
    labels <- c("0", "14", "30", "60", "90", "120", "180")
  } else {
    title <- "Longest recent dry-spell percentile rank"
    subtitle <- paste0(
      duration_days, "-day period ending ", format_prism_map_date(date),
      " relative to 1991-2020 | centered 5-day baseline"
    )
    fill_label <- "Percentile rank"
    palette <- c("#2166ac", "#67a9cf", "#d1e5f0", "#f7f7f7", "#fddbc7", "#ef8a62", "#b2182b")
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
      length = "pcpn_longest_dry_spell_180day",
      `percentile-rank` = "pcpn_longest_dry_spell_percentile_180day"
    ),
    mask_to_states = FALSE
  )
}

build_current_prism_longest_dry_spell_maps <- function(
    date = NULL,
    duration_days = 180L,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    progress_every = 25L,
    quiet = FALSE,
    map_products = c("length", "percentile-rank")) {
  map_products <- validate_southwest_map_products(
    map_products, c("length", "percentile-rank")
  )
  products <- calculate_prism_longest_dry_spell_products(
    date = date,
    duration_days = duration_days,
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
  rasters <- list(length = products$length, `percentile-rank` = products$percentile_rank)
  rasters <- rasters[map_products]
  records <- vector("list", length(rasters))
  for (index in seq_along(rasters)) {
    product <- names(rasters)[[index]]
    if (!quiet) {
      message(
        "Building ", duration_days, "-day longest-dry-spell ", product, " map."
      )
    }
    plot <- build_prism_longest_dry_spell_map(
      rasters[[product]], product, products$date, duration_days,
      products$wet_day_threshold, states, counties, countries, cities
    )
    dated_map <- prism_longest_dry_spell_map_path(
      product, products$date, duration_days, maps_dir
    )
    latest_map <- prism_longest_dry_spell_map_path(
      product, duration_days = duration_days, maps_dir = maps_dir
    )
    footer <- if (product == "length") {
      prism_precipitation_footer_text(products$start_date, products$date)
    } else {
      prism_map_footer_text()
    }
    save_southwest_map(plot, dated_map, logo_path = logo_path, footer_text = footer)
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest longest-dry-spell map: ", latest_map, call. = FALSE)
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
