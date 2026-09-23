# Calculate maximum rolling precipitation within a water year and its percentile.

prism_water_year_maximum_cache_version <- 1L

validate_prism_rolling_window <- function(window_days) {
  window_days <- as.integer(window_days)
  if (length(window_days) != 1L || is.na(window_days) || window_days < 1L) {
    stop("`window_days` must be a positive integer.", call. = FALSE)
  }
  window_days
}

prism_complete_water_year_periods <- function(
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end) {
  baseline_start <- as.Date(baseline_start)
  baseline_end <- as.Date(baseline_end)
  if (length(baseline_start) != 1L || length(baseline_end) != 1L ||
      is.na(baseline_start) || is.na(baseline_end) || baseline_start > baseline_end) {
    stop("The water-year baseline must be a valid inclusive date range.", call. = FALSE)
  }
  water_years <- seq(
    as.integer(format(baseline_start, "%Y")),
    as.integer(format(baseline_end, "%Y"))
  )
  data.frame(
    water_year = water_years,
    start_date = as.Date(sprintf("%d-10-01", water_years - 1L)),
    end_date = as.Date(sprintf("%d-09-30", water_years)),
    stringsAsFactors = FALSE
  )
}

prism_water_year_maximum_source_dates <- function(periods) {
  required <- c("start_date", "end_date")
  missing <- setdiff(required, names(periods))
  if (nrow(periods) == 0L || length(missing) > 0L) {
    stop("Complete water-year periods are missing required fields.", call. = FALSE)
  }
  dates <- lapply(seq_len(nrow(periods)), function(index) {
    seq(as.Date(periods$start_date[[index]]), as.Date(periods$end_date[[index]]), by = "day")
  })
  sort(unique(as.Date(unlist(dates), origin = "1970-01-01")))
}

prism_maximum_rolling_total <- function(raster, window_days = 3L, end_date = NULL) {
  window_days <- validate_prism_rolling_window(window_days)
  dates <- as.Date(terra::time(raster))
  if (terra::nlyr(raster) != length(dates) || anyNA(dates) || anyDuplicated(dates)) {
    stop("The rolling-maximum input must have one unique valid date per layer.", call. = FALSE)
  }
  expected <- seq(min(dates), max(dates), by = "day")
  if (length(dates) != length(expected) || any(dates != expected)) {
    stop("The rolling-maximum input must be complete and ordered by date.", call. = FALSE)
  }
  if (terra::nlyr(raster) < window_days) {
    stop("A complete rolling window is not yet available.", call. = FALSE)
  }
  window_count <- terra::nlyr(raster) - window_days + 1L
  rolling <- raster[[seq_len(window_count)]]
  if (window_days > 1L) {
    for (offset in 1:(window_days - 1L)) {
      rolling <- rolling + raster[[seq_len(window_count) + offset]]
    }
  }
  result <- if (terra::nlyr(rolling) == 1L) {
    rolling[[1L]]
  } else {
    terra::app(rolling, max, na.rm = FALSE)
  }
  if (is.null(end_date)) end_date <- max(dates)
  end_date <- as.Date(end_date)
  names(result) <- paste0(
    "pcpn_max_rolling_", sprintf("%02d", window_days), "day_", end_date
  )
  terra::time(result) <- end_date
  result
}

prism_water_year_maxima_for_periods <- function(
    raster,
    dates,
    periods,
    window_days = 3L,
    progress_every = 5L,
    quiet = FALSE) {
  dates <- as.Date(dates)
  window_days <- validate_prism_rolling_window(window_days)
  progress_every <- validate_prism_progress_every(progress_every)
  if (terra::nlyr(raster) != length(dates) || anyNA(dates) || anyDuplicated(dates)) {
    stop("The source raster must have one unique valid date per layer.", call. = FALSE)
  }
  started <- proc.time()[["elapsed"]]
  layers <- vector("list", nrow(periods))
  for (index in seq_len(nrow(periods))) {
    needed <- seq(periods$start_date[[index]], periods$end_date[[index]], by = "day")
    selected <- match(needed, dates)
    if (anyNA(selected)) {
      stop(
        "Water-year maximum input is incomplete; first missing date: ",
        format(needed[which(is.na(selected))[[1L]]]),
        call. = FALSE
      )
    }
    layers[[index]] <- prism_maximum_rolling_total(
      raster[[selected]], window_days, periods$end_date[[index]]
    )
    if (!quiet && (index %% progress_every == 0L || index == nrow(periods))) {
      message(
        "  Water-year maximum ", window_days, "-day totals: ", index, "/",
        nrow(periods), " water years (",
        format_prism_elapsed(proc.time()[["elapsed"]] - started), ")."
      )
    }
  }
  result <- do.call(c, layers)
  terra::time(result) <- periods$end_date
  names(result) <- paste0(
    "pcpn_wy", periods$water_year, "_max_",
    sprintf("%02d", window_days), "day"
  )
  result
}

prism_water_year_maximum_cache_manifest_path <- function(
    processed_dir = swc_paths$processed) {
  file.path(processed_dir, "prism", "water-year-maximum-cache-manifest.csv")
}

prism_water_year_maximum_cache_path <- function(
    window_days = 3L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  window_days <- validate_prism_rolling_window(window_days)
  baseline_label <- paste0(
    format(as.Date(baseline_start), "%Y%m%d"), "-",
    format(as.Date(baseline_end), "%Y%m%d")
  )
  file.path(
    processed_dir, "prism", aoi_id, "climatology", baseline_label,
    "water-year-maximum-samples", "pcpn",
    paste0(sprintf("%03d", window_days), "day"),
    "complete-water-years.tif"
  )
}

read_prism_water_year_maximum_cache <- function(path, expected_dates = NULL) {
  if (!file.exists(path)) stop("Water-year maximum cache does not exist: ", path, call. = FALSE)
  raster <- terra::rast(path)
  dates <- as.Date(terra::time(raster))
  if (length(dates) != terra::nlyr(raster) || anyNA(dates) || anyDuplicated(dates)) {
    stop("Water-year maximum cache must have one unique valid date per layer.", call. = FALSE)
  }
  if (!is.null(expected_dates)) {
    expected_dates <- as.Date(expected_dates)
    if (length(dates) != length(expected_dates) || any(dates != expected_dates)) {
      stop("Water-year maximum cache dates do not match the requested baseline.", call. = FALSE)
    }
  }
  raster
}

build_prism_water_year_maximum_cache <- function(
    window_days = 3L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    manifest_path = prism_water_year_maximum_cache_manifest_path(processed_dir),
    overwrite = FALSE,
    progress_every = 5L,
    quiet = FALSE) {
  window_days <- validate_prism_rolling_window(window_days)
  periods <- prism_complete_water_year_periods(baseline_start, baseline_end)
  source_dates <- prism_water_year_maximum_source_dates(periods)
  selection <- select_prism_daily_sources("pcpn", source_dates, aoi_id, processed_manifest)
  source_signature <- prism_accumulation_source_signature(selection, processed_manifest)
  path <- prism_water_year_maximum_cache_path(
    window_days, baseline_start, baseline_end, aoi_id, processed_dir
  )
  cache_manifest <- read_prism_manifest(manifest_path)
  existing <- if (nrow(cache_manifest) > 0L &&
      all(c("path", "source_signature", "cache_version", "md5") %in% names(cache_manifest))) {
    cache_manifest[cache_manifest$path == path, , drop = FALSE]
  } else {
    data.frame()
  }
  current <- nrow(existing) > 0L && file.exists(path) &&
    identical(as.integer(tail(existing$cache_version, 1L)),
              prism_water_year_maximum_cache_version) &&
    identical(tail(existing$source_signature, 1L), source_signature) &&
    identical(tail(existing$md5, 1L), unname(tools::md5sum(path)))
  if (current && !overwrite) {
    if (!quiet) message("Using current complete-water-year maximum cache.")
    return(invisible(list(
      raster = read_prism_water_year_maximum_cache(path, periods$end_date),
      periods = periods,
      path = path,
      source_signature = source_signature,
      refreshed = FALSE
    )))
  }

  if (!quiet) {
    message(
      "Building complete-water-year maximum ", window_days,
      "-day cache from ", length(source_dates), " daily layers."
    )
  }
  collection <- read_prism_best_daily_range(
    "pcpn", source_dates, aoi_id, processed_manifest
  )
  maxima <- prism_water_year_maxima_for_periods(
    collection$raster, collection$dates, periods,
    window_days, progress_every, quiet
  )
  write_prism_processed_raster(maxima, path, datatype = "FLT8S")
  record <- data.frame(
    product = "complete_water_year_maximum_rolling_sample",
    cache_version = prism_water_year_maximum_cache_version,
    aoi_id = aoi_id,
    variable = "pcpn",
    native_units = "inch",
    storage_datatype = "FLT8S",
    rolling_window_days = window_days,
    method = "complete-water-years",
    start_date = as.Date(baseline_start),
    end_date = as.Date(baseline_end),
    first_water_year = min(periods$water_year),
    last_water_year = max(periods$water_year),
    sample_layers = terra::nlyr(maxima),
    source_signature = source_signature,
    built_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    bytes = file.info(path)$size,
    md5 = unname(tools::md5sum(path)),
    path = path,
    stringsAsFactors = FALSE
  )
  write_prism_manifest(record, manifest_path)
  if (!quiet) message("Wrote water-year maximum cache: ", path)
  invisible(list(
    raster = read_prism_water_year_maximum_cache(path, periods$end_date),
    periods = periods,
    path = path,
    source_signature = source_signature,
    refreshed = TRUE
  ))
}

prism_current_water_year_maximum <- function(
    date,
    window_days = 3L,
    aoi_id = swc_prism$aoi_id,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path())) {
  date <- as.Date(date)
  window_days <- validate_prism_rolling_window(window_days)
  start_date <- prism_water_year_start(date)
  if (as.integer(date - start_date) + 1L < window_days) {
    stop("A complete ", window_days, "-day period is not available until ",
         format(start_date + window_days - 1L), ".", call. = FALSE)
  }
  dates <- seq(start_date, date, by = "day")
  collection <- read_prism_best_daily_range(
    "pcpn", dates, aoi_id, processed_manifest
  )
  result <- prism_maximum_rolling_total(collection$raster, window_days, date)
  names(result) <- paste0(
    "pcpn_water_year_maximum_", sprintf("%02d", window_days), "day_", date
  )
  result
}

prism_water_year_maximum_rank_raster <- function(
    current_maximum,
    reference_maxima,
    window_days,
    date) {
  if (terra::nlyr(current_maximum) != 1L || terra::nlyr(reference_maxima) < 1L) {
    stop("Current maximum must have one layer and the reference must not be empty.", call. = FALSE)
  }
  terra::compareGeom(current_maximum, reference_maxima, stopOnError = TRUE)
  result <- terra::app(c(current_maximum, reference_maxima), fun = function(x, ...) {
    prism_type8_percentile_rank(x[[1L]], x[-1L])
  })
  date <- as.Date(date)
  names(result) <- paste0(
    "pcpn_water_year_maximum_", sprintf("%02d", window_days),
    "day_percentile_rank_", date
  )
  terra::time(result) <- date
  result
}

prism_water_year_precipitation_concentration_raster <- function(
    maximum,
    total,
    window_days = 3L,
    date,
    minimum_total_inches = swc_prism$percent_normal_minimum_inches) {
  window_days <- validate_prism_rolling_window(window_days)
  date <- as.Date(date)
  if (terra::nlyr(maximum) != 1L || terra::nlyr(total) != 1L) {
    stop("Water-year maximum and total must each contain one layer.", call. = FALSE)
  }
  if (length(minimum_total_inches) != 1L || !is.finite(minimum_total_inches) ||
      minimum_total_inches < 0) {
    stop("`minimum_total_inches` must be one non-negative number.", call. = FALSE)
  }
  terra::compareGeom(maximum, total, stopOnError = TRUE)
  result <- terra::ifel(
    total >= minimum_total_inches,
    100 * maximum / total,
    NA
  )
  result <- terra::clamp(result, lower = 0, upper = 100)
  names(result) <- paste0(
    "pcpn_water_year_maximum_", sprintf("%02d", window_days),
    "day_concentration_", date
  )
  terra::time(result) <- date
  result
}

prism_water_year_maximum_output_path <- function(
    product = c("maximum", "percentile-rank"),
    date,
    window_days = 3L,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  product <- match.arg(product)
  file.path(
    processed_dir, "prism", aoi_id, "daily", "water-year-maximum",
    "pcpn", paste0(sprintf("%03d", validate_prism_rolling_window(window_days)), "day"),
    product, paste0(format(as.Date(date)), ".tif")
  )
}

prism_water_year_maximum_map_path <- function(
    product = c("maximum", "percentile-rank"),
    date = NULL,
    window_days = 3L,
    maps_dir = swc_paths$maps) {
  product <- match.arg(product)
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  product_label <- if (product == "maximum") "" else "percentile-rank-"
  file.path(
    maps_dir, "prism", "precipitation",
    paste0(
      "pcpn-water-year-max-", product_label,
      sprintf("%02d", validate_prism_rolling_window(window_days)),
      "day-", suffix, ".png"
    )
  )
}

prism_water_year_concentration_output_path <- function(
    date,
    window_days = 3L,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  file.path(
    processed_dir, "prism", aoi_id, "daily", "water-year-maximum",
    "pcpn", paste0(sprintf("%03d", validate_prism_rolling_window(window_days)), "day"),
    "concentration", paste0(format(as.Date(date)), ".tif")
  )
}

prism_water_year_concentration_map_path <- function(
    date = NULL,
    window_days = 3L,
    maps_dir = swc_paths$maps) {
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "precipitation",
    paste0(
      "pcpn-water-year-precipitation-concentration-",
      sprintf("%02d", validate_prism_rolling_window(window_days)),
      "day-", suffix, ".png"
    )
  )
}

calculate_current_prism_water_year_maximum_products <- function(
    date = NULL,
    window_days = 3L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    cache_overwrite = FALSE,
    overwrite = TRUE,
    progress_every = 5L,
    quiet = FALSE) {
  window_days <- validate_prism_rolling_window(window_days)
  if (is.null(date)) {
    date <- latest_common_prism_date(
      "pcpn", aoi_id = aoi_id, processed_manifest = processed_manifest
    )
  }
  date <- as.Date(date)
  current <- prism_current_water_year_maximum(
    date, window_days, aoi_id, processed_manifest
  )
  cache <- build_prism_water_year_maximum_cache(
    window_days, baseline_start, baseline_end, aoi_id, processed_dir,
    processed_manifest, overwrite = cache_overwrite,
    progress_every = progress_every, quiet = quiet
  )
  rank <- prism_water_year_maximum_rank_raster(
    current, cache$raster, window_days, date
  )
  paths <- c(
    maximum = prism_water_year_maximum_output_path(
      "maximum", date, window_days, aoi_id, processed_dir
    ),
    `percentile-rank` = prism_water_year_maximum_output_path(
      "percentile-rank", date, window_days, aoi_id, processed_dir
    )
  )
  rasters <- list(maximum = current, `percentile-rank` = rank)
  for (product in names(rasters)) {
    if (file.exists(paths[[product]]) && !overwrite) {
      stop("Water-year maximum output already exists; set `overwrite = TRUE`: ",
           paths[[product]], call. = FALSE)
    }
    write_prism_processed_raster(rasters[[product]], paths[[product]])
  }
  list(
    date = date,
    water_year = prism_water_year(date),
    start_date = prism_water_year_start(date),
    window_days = window_days,
    maximum = current,
    percentile_rank = rank,
    paths = paths,
    cache = cache
  )
}

prism_water_year_maximum_scale <- function() {
  list(
    palette = c(
      "#f7fbff", "#d9eff7", "#92c5de", "#4393c3",
      "#41ab5d", "#fddc6c", "#f46d43", "#7a0177"
    ),
    values = c(0, 0.5, 1, 2, 3, 4, 6, 8),
    limits = c(0, 8),
    breaks = c(0, 1, 2, 3, 4, 6, 8),
    labels = c("0", "1", "2", "3", "4", "6", "8+")
  )
}

build_prism_water_year_maximum_map <- function(
    raster,
    product = c("maximum", "percentile-rank"),
    date = as.Date(terra::time(raster)),
    window_days = 3L,
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),
    rivers = southwest_major_rivers()) {
  product <- match.arg(product)
  date <- as.Date(date)
  window_days <- validate_prism_rolling_window(window_days)
  water_year <- prism_water_year(date)
  period <- format_prism_map_period(prism_water_year_start(date), date)
  if (product == "maximum") {
    scale <- prism_water_year_maximum_scale()
    title <- paste0("Water year ", water_year, " maximum ", window_days,
                    "-day precipitation")
    subtitle <- paste0("Maximum so far | ", period)
    fill_label <- "Precipitation (inches)"
  } else {
    scale <- list(
      palette = c("#7f3b08", "#b35806", "#f1a340", "#f7f7f7", "#998ec3", "#542788", "#2d004b"),
      values = c(0, 10, 25, 50, 75, 90, 100),
      limits = c(0, 100),
      breaks = c(0, 10, 25, 50, 75, 90, 100),
      labels = c("0", "10", "25", "50", "75", "90", "100")
    )
    title <- paste0("Maximum ", window_days, "-day precipitation percentile rank")
    subtitle <- paste0(
      "Water year ", water_year, " through ", format_prism_map_date(date),
      " | provisional relative to complete water years 1991-2020"
    )
    fill_label <- "Percentile rank"
  }
  southwest_raster_map(
    raster = raster,
    states = states,
    title = title,
    subtitle = subtitle,
    caption = NULL,
    fill_label = fill_label,
    palette = scale$palette,
    palette_values = scale$values,
    limits = scale$limits,
    breaks = scale$breaks,
    labels = scale$labels,
    counties = counties,
    countries = countries,
    rivers = rivers,
    cities = cities,
    product_id = switch(
      product,
      maximum = "pcpn_water_year_max_03day",
      `percentile-rank` = "pcpn_water_year_max_percentile_03day"
    ),
    mask_to_states = FALSE
  )
}

build_current_prism_water_year_maximum_maps <- function(
    date = NULL,
    window_days = 3L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    progress_every = 5L,
    quiet = FALSE,
    map_products = c("maximum", "percentile-rank")) {
  map_products <- validate_southwest_map_products(
    map_products, c("maximum", "percentile-rank"), allow_empty = TRUE
  )
  products <- calculate_current_prism_water_year_maximum_products(
    date, window_days, baseline_start, baseline_end, aoi_id, processed_dir,
    cache_overwrite = FALSE, overwrite = overwrite,
    progress_every = progress_every, quiet = quiet
  )
  states <- southwest_state_boundaries()
  counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries()
  cities <- southwest_reference_cities()
  rasters <- list(maximum = products$maximum, `percentile-rank` = products$percentile_rank)
  rasters <- rasters[map_products]
  if (length(rasters) == 0L) {
    return(invisible(data.frame()))
  }
  records <- vector("list", length(rasters))
  for (index in seq_along(rasters)) {
    product <- names(rasters)[[index]]
    if (!quiet) message("Building water-year maximum ", product, " map.")
    plot <- build_prism_water_year_maximum_map(
      rasters[[product]], product, products$date, window_days,
      states, counties, countries, cities
    )
    dated_map <- prism_water_year_maximum_map_path(
      product, products$date, window_days, maps_dir
    )
    latest_map <- prism_water_year_maximum_map_path(
      product, window_days = window_days, maps_dir = maps_dir
    )
    footer <- if (product == "maximum") {
      prism_precipitation_footer_text(products$start_date, products$date)
    } else {
      prism_map_footer_text(baseline_start, baseline_end)
    }
    save_southwest_map(plot, dated_map, logo_path = logo_path, footer_text = footer)
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest water-year maximum map: ", latest_map, call. = FALSE)
    }
    value_range <- range(terra::values(rasters[[product]]), na.rm = TRUE)
    records[[index]] <- data.frame(
      date = products$date,
      water_year = products$water_year,
      window_days = window_days,
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

prism_water_year_concentration_scale <- function() {
  list(
    palette = c(
      "#f7fbff", "#c6dbef", "#6baed6", "#41ab5d",
      "#fddc6c", "#f46d43", "#b2182b", "#7a0177"
    ),
    values = c(0, 10, 20, 30, 40, 60, 80, 100),
    limits = c(0, 100),
    breaks = c(0, 10, 20, 30, 40, 60, 80, 100),
    labels = c("0", "10", "20", "30", "40", "60", "80", "100")
  )
}

build_prism_water_year_concentration_map <- function(
    raster,
    date = as.Date(terra::time(raster)),
    window_days = 3L,
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),
    rivers = southwest_major_rivers()) {
  date <- as.Date(date)
  window_days <- validate_prism_rolling_window(window_days)
  scale <- prism_water_year_concentration_scale()
  southwest_raster_map(
    raster = raster,
    states = states,
    title = paste0(
      "Water year ", prism_water_year(date), " precipitation concentration"
    ),
    subtitle = paste0(
      "Percent supplied by the wettest ", window_days, "-day period | ",
      format_prism_map_period(prism_water_year_start(date), date)
    ),
    caption = NULL,
    fill_label = "Percent of total",
    palette = scale$palette,
    palette_values = scale$values,
    limits = scale$limits,
    breaks = scale$breaks,
    labels = scale$labels,
    counties = counties,
    countries = countries,
    rivers = rivers,
    cities = cities,
    product_id = "pcpn_water_year_concentration_03day",
    mask_to_states = FALSE
  )
}

build_current_prism_water_year_concentration_map <- function(
    date = NULL,
    window_days = 3L,
    minimum_total_inches = swc_prism$percent_normal_minimum_inches,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    quiet = FALSE) {
  window_days <- validate_prism_rolling_window(window_days)
  if (is.null(date)) {
    date <- latest_common_prism_date(
      "pcpn", aoi_id = aoi_id, processed_manifest = processed_manifest
    )
  }
  date <- as.Date(date)
  maximum_path <- prism_water_year_maximum_output_path(
    "maximum", date, window_days, aoi_id, processed_dir
  )
  total_path <- prism_water_year_product_path(
    "total", date, aoi_id, processed_dir
  )
  maximum <- if (file.exists(maximum_path)) {
    terra::rast(maximum_path)
  } else {
    prism_current_water_year_maximum(
      date, window_days, aoi_id, processed_manifest
    )
  }
  total <- if (file.exists(total_path)) {
    terra::rast(total_path)
  } else {
    prism_current_water_year_total(date, aoi_id, processed_manifest)
  }
  concentration <- prism_water_year_precipitation_concentration_raster(
    maximum, total, window_days, date, minimum_total_inches
  )
  output_path <- prism_water_year_concentration_output_path(
    date, window_days, aoi_id, processed_dir
  )
  if (file.exists(output_path) && !overwrite) {
    stop("Water-year concentration output already exists; set `overwrite = TRUE`: ",
         output_path, call. = FALSE)
  }
  write_prism_processed_raster(concentration, output_path)
  if (!quiet) message("Building water-year precipitation concentration map.")
  plot <- build_prism_water_year_concentration_map(
    concentration, date, window_days
  )
  dated_map <- prism_water_year_concentration_map_path(
    date, window_days, maps_dir
  )
  latest_map <- prism_water_year_concentration_map_path(
    window_days = window_days, maps_dir = maps_dir
  )
  save_southwest_map(
    plot, dated_map, logo_path = logo_path,
    footer_text = prism_precipitation_footer_text(
      prism_water_year_start(date), date
    )
  )
  dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
    stop("Could not update latest water-year concentration map: ", latest_map, call. = FALSE)
  }
  value_range <- range(terra::values(concentration), na.rm = TRUE)
  invisible(data.frame(
    date = date,
    water_year = prism_water_year(date),
    window_days = window_days,
    minimum_percent = value_range[[1L]],
    maximum_percent = value_range[[2L]],
    minimum_total_inches = minimum_total_inches,
    raster_path = output_path,
    map_path = dated_map,
    latest_map_path = latest_map,
    stringsAsFactors = FALSE
  ))
}
