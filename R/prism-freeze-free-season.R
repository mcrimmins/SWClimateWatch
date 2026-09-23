# Calculate and map freeze-free season length from daily minimum temperature.

prism_freeze_free_cache_version <- 1L

prism_freeze_free_publishable <- function(
    date,
    observed_length = NULL,
    normal_length = NULL,
    publication_month_day = "09-01",
    minimum_observed_coverage = 0.05) {
  date <- as.Date(date)
  year <- as.integer(format(date, "%Y"))
  publication_date <- as.Date(paste0(year, "-", publication_month_day))
  if (date < publication_date) return(FALSE)
  if (is.null(observed_length) || is.null(normal_length)) return(TRUE)
  if (length(minimum_observed_coverage) != 1L ||
      !is.finite(minimum_observed_coverage) || minimum_observed_coverage < 0 ||
      minimum_observed_coverage > 1) {
    stop("`minimum_observed_coverage` must be between zero and one.", call. = FALSE)
  }
  terra::compareGeom(observed_length, normal_length, stopOnError = TRUE)
  eligible <- !is.na(normal_length)
  eligible_count <- terra::global(eligible, "sum", na.rm = TRUE)[[1L, 1L]]
  if (!is.finite(eligible_count) || eligible_count == 0) return(FALSE)
  observed_count <- terra::global(
    eligible & !is.na(observed_length), "sum", na.rm = TRUE
  )[[1L, 1L]]
  observed_count / eligible_count >= minimum_observed_coverage
}

prism_freeze_free_periods <- function(
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end) {
  years <- seq(
    as.integer(format(as.Date(baseline_start), "%Y")),
    as.integer(format(as.Date(baseline_end), "%Y"))
  )
  data.frame(
    year = years,
    start_date = as.Date(sprintf("%d-01-01", years)),
    end_date = as.Date(sprintf("%d-12-31", years)),
    stringsAsFactors = FALSE
  )
}

prism_freeze_free_length_index <- function(
    values,
    spring_indices,
    fall_indices,
    threshold_f = 32) {
  if (length(values) == 0L || anyNA(values) ||
      length(spring_indices) == 0L || length(fall_indices) == 0L) {
    return(NA_real_)
  }
  spring_freezes <- spring_indices[values[spring_indices] <= threshold_f]
  fall_freezes <- fall_indices[values[fall_indices] <= threshold_f]
  if (length(spring_freezes) == 0L || length(fall_freezes) == 0L) return(NA_real_)
  fall_freezes[[1L]] - spring_freezes[[length(spring_freezes)]]
}

prism_freeze_free_length_from_raster <- function(
    raster,
    year,
    threshold_f = 32,
    observation_end = max(as.Date(terra::time(raster)))) {
  year <- as.integer(year)
  year_start <- as.Date(sprintf("%d-01-01", year))
  observation_end <- as.Date(observation_end)
  dates <- as.Date(terra::time(raster))
  expected <- seq(year_start, observation_end, by = "day")
  if (terra::nlyr(raster) != length(expected) || length(dates) != terra::nlyr(raster) ||
      anyNA(dates) || anyDuplicated(dates) || any(dates != expected)) {
    stop(
      "The freeze-free input must be complete and ordered from January 1 through observation end.",
      call. = FALSE
    )
  }
  if (length(threshold_f) != 1L || !is.finite(threshold_f)) {
    stop("`threshold_f` must be one finite number.", call. = FALSE)
  }
  spring_end <- as.Date(sprintf("%d-07-31", year))
  fall_start <- as.Date(sprintf("%d-08-01", year))
  spring_indices <- which(dates <= spring_end)
  fall_indices <- which(dates >= fall_start)
  result <- terra::app(
    raster,
    fun = prism_freeze_free_length_index,
    spring_indices = spring_indices,
    fall_indices = fall_indices,
    threshold_f = threshold_f
  )
  names(result) <- paste0("mint_freeze_free_length_", year, "_through_", observation_end)
  terra::time(result) <- observation_end
  result
}

prism_freeze_free_cache_manifest_path <- function(processed_dir = swc_paths$processed) {
  file.path(processed_dir, "prism", "freeze-free-cache-manifest.csv")
}

prism_freeze_free_cache_path <- function(
    threshold_f = 32,
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  baseline_label <- paste0(
    format(as.Date(baseline_start), "%Y%m%d"), "-",
    format(as.Date(baseline_end), "%Y%m%d")
  )
  threshold_label <- sprintf("%02dF", round(threshold_f))
  file.path(
    processed_dir, "prism", aoi_id, "climatology", baseline_label,
    "freeze-free-samples", "mint", paste0("at-or-below-", threshold_label),
    "calendar-years.tif"
  )
}

read_prism_freeze_free_cache <- function(path, expected_years = NULL) {
  if (!file.exists(path)) stop("Freeze-free cache does not exist: ", path, call. = FALSE)
  raster <- terra::rast(path)
  dates <- as.Date(terra::time(raster))
  if (length(dates) != terra::nlyr(raster) || anyNA(dates) || anyDuplicated(dates)) {
    stop("Freeze-free cache must have one unique calendar-year date per layer.", call. = FALSE)
  }
  if (!is.null(expected_years)) {
    expected_dates <- as.Date(sprintf("%d-01-01", as.integer(expected_years)))
    if (length(dates) != length(expected_dates) || any(dates != expected_dates)) {
      stop("Freeze-free cache years do not match the requested baseline.", call. = FALSE)
    }
  }
  raster
}

build_prism_freeze_free_cache <- function(
    threshold_f = 32,
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    manifest_path = prism_freeze_free_cache_manifest_path(processed_dir),
    overwrite = FALSE,
    progress_every = 5L,
    quiet = FALSE) {
  progress_every <- validate_prism_progress_every(progress_every)
  periods <- prism_freeze_free_periods(baseline_start, baseline_end)
  source_dates <- seq(min(periods$start_date), max(periods$end_date), by = "day")
  selection <- select_prism_daily_sources("mint", source_dates, aoi_id, processed_manifest)
  source_signature <- prism_temperature_threshold_source_signature(
    selection, processed_manifest, threshold_f
  )
  path <- prism_freeze_free_cache_path(
    threshold_f, baseline_start, baseline_end, aoi_id, processed_dir
  )
  cache_manifest <- read_prism_manifest(manifest_path)
  existing <- if (nrow(cache_manifest) > 0L &&
      all(c("path", "source_signature", "cache_version", "md5") %in% names(cache_manifest))) {
    cache_manifest[cache_manifest$path == path, , drop = FALSE]
  } else {
    data.frame()
  }
  current <- nrow(existing) > 0L && file.exists(path) &&
    identical(as.integer(tail(existing$cache_version, 1L)), prism_freeze_free_cache_version) &&
    identical(tail(existing$source_signature, 1L), source_signature) &&
    identical(tail(existing$md5, 1L), unname(tools::md5sum(path)))
  if (current && !overwrite) {
    if (!quiet) message("Using current freeze-free climatology cache.")
    return(invisible(list(
      raster = read_prism_freeze_free_cache(path, periods$year),
      periods = periods,
      path = path,
      source_signature = source_signature,
      refreshed = FALSE
    )))
  }

  if (!quiet) {
    message(
      "Building freeze-free cache from ", nrow(periods),
      " calendar years and ", length(source_dates), " daily layers."
    )
  }
  started <- proc.time()[["elapsed"]]
  layers <- vector("list", nrow(periods))
  for (index in seq_len(nrow(periods))) {
    dates <- seq(periods$start_date[[index]], periods$end_date[[index]], by = "day")
    collection <- read_prism_best_daily_range(
      "mint", dates, aoi_id, processed_manifest
    )
    layers[[index]] <- prism_freeze_free_length_from_raster(
      collection$raster,
      periods$year[[index]],
      threshold_f,
      periods$end_date[[index]]
    )
    if (!quiet && (index %% progress_every == 0L || index == nrow(periods))) {
      message(
        "  Freeze-free years: ", index, "/", nrow(periods), " (",
        format_prism_elapsed(proc.time()[["elapsed"]] - started), ")."
      )
    }
  }
  samples <- do.call(c, layers)
  terra::time(samples) <- periods$start_date
  names(samples) <- paste0("mint_freeze_free_length_", periods$year)
  write_prism_processed_raster(samples, path, datatype = "FLT4S")
  record <- data.frame(
    product = "freeze_free_calendar_year_sample",
    cache_version = prism_freeze_free_cache_version,
    aoi_id = aoi_id,
    variable = "mint",
    native_units = "days",
    threshold_f = threshold_f,
    spring_period = "01-01/07-31",
    fall_period = "08-01/12-31",
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
  if (!quiet) message("Wrote freeze-free cache: ", path)
  invisible(list(
    raster = read_prism_freeze_free_cache(path, periods$year),
    periods = periods,
    path = path,
    source_signature = source_signature,
    refreshed = TRUE
  ))
}

prism_freeze_free_climatology <- function(samples, minimum_frequency = 0.8) {
  climatology <- prism_first_freeze_climatology(samples, minimum_frequency)
  names(climatology$frequency) <- "mint_freeze_free_frequency"
  names(climatology$median_day) <- "mint_freeze_free_median_length"
  list(median_length = climatology$median_day, frequency = climatology$frequency)
}

prism_freeze_free_departure_raster <- function(observed_length, normal_length, date) {
  if (terra::nlyr(observed_length) != 1L || terra::nlyr(normal_length) != 1L) {
    stop("Observed and normal freeze-free rasters must each contain one layer.", call. = FALSE)
  }
  terra::compareGeom(observed_length, normal_length, stopOnError = TRUE)
  result <- observed_length - normal_length
  date <- as.Date(date)
  names(result) <- paste0("mint_freeze_free_departure_days_", format(date, "%Y"))
  terra::time(result) <- date
  result
}

prism_freeze_free_output_path <- function(
    product = c("length", "departure"),
    year,
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  product <- match.arg(product)
  file.path(
    processed_dir, "prism", aoi_id, "seasonal", "freeze-free", "mint",
    paste0("year-", as.integer(year)), product,
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_freeze_free_map_path <- function(
    product = c("length", "departure"),
    date = NULL,
    maps_dir = swc_paths$maps) {
  product <- match.arg(product)
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "temperature",
    paste0("mint-freeze-free-season-", product, "-", suffix, ".png")
  )
}

calculate_prism_freeze_free_products <- function(
    date = NULL,
    threshold_f = 32,
    minimum_frequency = 0.8,
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    cache_overwrite = FALSE,
    overwrite = TRUE,
    progress_every = 5L,
    quiet = FALSE) {
  if (is.null(date)) {
    date <- latest_common_prism_date(
      "mint", aoi_id = aoi_id, processed_manifest = processed_manifest
    )
  }
  date <- as.Date(date)
  year <- as.integer(format(date, "%Y"))
  dates <- seq(as.Date(sprintf("%d-01-01", year)), date, by = "day")
  collection <- read_prism_best_daily_range(
    "mint", dates, aoi_id, processed_manifest
  )
  observed <- prism_freeze_free_length_from_raster(
    collection$raster, year, threshold_f, date
  )
  cache <- build_prism_freeze_free_cache(
    threshold_f, baseline_start, baseline_end, aoi_id, processed_dir,
    processed_manifest, overwrite = cache_overwrite,
    progress_every = progress_every, quiet = quiet
  )
  climatology <- prism_freeze_free_climatology(cache$raster, minimum_frequency)
  departure <- prism_freeze_free_departure_raster(
    observed, climatology$median_length, date
  )
  paths <- c(
    length = prism_freeze_free_output_path(
      "length", year, date, aoi_id, processed_dir
    ),
    departure = prism_freeze_free_output_path(
      "departure", year, date, aoi_id, processed_dir
    )
  )
  rasters <- list(length = observed, departure = departure)
  for (product in names(rasters)) {
    if (file.exists(paths[[product]]) && !overwrite) {
      stop("Freeze-free output already exists; set `overwrite = TRUE`: ", paths[[product]], call. = FALSE)
    }
    write_prism_processed_raster(rasters[[product]], paths[[product]])
  }
  list(
    date = date,
    year = year,
    threshold_f = threshold_f,
    minimum_frequency = minimum_frequency,
    publishable = prism_freeze_free_publishable(
      date, observed, climatology$median_length
    ),
    observed_length = observed,
    departure = departure,
    normal_length = climatology$median_length,
    frequency = climatology$frequency,
    paths = paths,
    cache = cache
  )
}

build_prism_freeze_free_map <- function(
    raster,
    product = c("length", "departure"),
    date = as.Date(terra::time(raster)),
    year = as.integer(format(date, "%Y")),
    threshold_f = 32,
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities()) {
  product <- match.arg(product)
  date <- as.Date(date)
  complete <- date >= as.Date(sprintf("%d-12-31", year))
  status <- if (complete) "" else " so far"
  if (product == "length") {
    title <- paste0("Freeze-free season length", status, ": ", year)
    subtitle <- paste0(
      "Days from last January-July freeze to first August-December freeze",
      " | threshold ", threshold_f, " degrees F"
    )
    fill_label <- "Freeze-free days"
    palette <- c("#a50026", "#f46d43", "#fee08b", "#d9ef8b", "#66bd63", "#006837")
    values <- c(0, 60, 120, 180, 240, 365)
    limits <- c(0, 365)
    breaks <- c(0, 60, 120, 180, 240, 300, 365)
    labels <- c("0", "60", "120", "180", "240", "300", "365")
  } else {
    title <- paste0("Freeze-free season-length departure", status, ": ", year)
    subtitle <- paste0(
      "Observed through ", format_prism_map_date(date),
      " minus 1991-2020 median | cells with both freeze dates"
    )
    fill_label <- "Departure (days; negative = shorter)"
    palette <- c("#8c2d04", "#d95f0e", "#fec44f", "#f7f7f7", "#c7e9c0", "#41ab5d", "#006d2c")
    values <- c(-60, -30, -10, 0, 10, 30, 60)
    limits <- c(-60, 60)
    breaks <- c(-60, -30, 0, 30, 60)
    labels <- c("-60", "-30", "0", "+30", "+60")
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
    cities = cities,
    product_id = switch(
      product,
      length = "mint_freeze_free_length",
      departure = "mint_freeze_free_departure"
    ),
    mask_to_states = FALSE
  )
}

build_current_prism_freeze_free_maps <- function(
    date = NULL,
    threshold_f = 32,
    minimum_frequency = 0.8,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    progress_every = 5L,
    quiet = FALSE,
    map_products = c("length", "departure")) {
  map_products <- validate_southwest_map_products(
    map_products, c("length", "departure")
  )
  products <- calculate_prism_freeze_free_products(
    date = date,
    threshold_f = threshold_f,
    minimum_frequency = minimum_frequency,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    overwrite = overwrite,
    progress_every = progress_every,
    quiet = quiet
  )
  if (!products$publishable) {
    if (!quiet) {
      message(
        "Freeze-free maps are not yet publishable; fewer than 5% of historically reliable cells have both freeze dates, so prior completed-year maps are retained."
      )
    }
    return(invisible(data.frame(
      date = products$date,
      year = products$year,
      product = map_products,
      published = FALSE,
      stringsAsFactors = FALSE
    )))
  }
  states <- southwest_state_boundaries()
  counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries()
  cities <- southwest_reference_cities()
  rasters <- list(length = products$observed_length, departure = products$departure)
  rasters <- rasters[map_products]
  records <- vector("list", length(rasters))
  for (index in seq_along(rasters)) {
    product <- names(rasters)[[index]]
    if (!quiet) message("Building freeze-free ", product, " map.")
    plot <- build_prism_freeze_free_map(
      rasters[[product]], product, products$date, products$year,
      products$threshold_f, states, counties, countries, cities
    )
    dated_map <- prism_freeze_free_map_path(product, products$date, maps_dir)
    latest_map <- prism_freeze_free_map_path(product, maps_dir = maps_dir)
    footer <- if (product == "length") {
      "Data source: PRISM Climate Group via RCC-ACIS"
    } else {
      prism_map_footer_text()
    }
    save_southwest_map(plot, dated_map, logo_path = logo_path, footer_text = footer)
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest freeze-free map: ", latest_map, call. = FALSE)
    }
    value_range <- range(terra::values(rasters[[product]]), na.rm = TRUE)
    records[[index]] <- data.frame(
      date = products$date,
      year = products$year,
      product = product,
      published = TRUE,
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
