# Calculate and map last spring-freeze timing from daily minimum temperature.

prism_last_freeze_cache_version <- 2L

prism_last_freeze_publishable <- function(
    date,
    publication_month_day = "03-01") {
  date <- as.Date(date)
  season_start <- prism_freeze_season_start(date)
  publication_year <- as.integer(format(season_start, "%Y")) + 1L
  publication_date <- as.Date(paste0(publication_year, "-", publication_month_day))
  date >= publication_date
}

prism_last_freeze_index <- function(values, threshold_f = 32) {
  if (length(values) == 0L || anyNA(values)) return(NA_real_)
  freeze <- which(values <= threshold_f)
  if (length(freeze) == 0L) return(NA_real_)
  freeze[[length(freeze)]]
}

prism_last_freeze_from_raster <- function(
    raster,
    season_start,
    threshold_f = 32,
    observation_end = max(as.Date(terra::time(raster))),
    preserve_no_freeze = FALSE) {
  season_start <- as.Date(season_start)
  observation_end <- as.Date(observation_end)
  dates <- as.Date(terra::time(raster))
  expected <- seq(season_start, observation_end, by = "day")
  if (terra::nlyr(raster) != length(expected) || length(dates) != terra::nlyr(raster) ||
      anyNA(dates) || anyDuplicated(dates) || any(dates != expected)) {
    stop(
      "The last-freeze input must be complete and ordered from season start through observation end.",
      call. = FALSE
    )
  }
  if (length(threshold_f) != 1L || !is.finite(threshold_f)) {
    stop("`threshold_f` must be one finite number.", call. = FALSE)
  }
  result <- if(terra::nlyr(raster)==1L) terra::ifel(is.finite(raster),
    terra::ifel(raster<=threshold_f,1,if(preserve_no_freeze) 0 else NA),NA) else terra::app(raster, fun = function(x,...) {
    if(any(!is.finite(x))) return(NA_real_)
    index <- prism_last_freeze_index(x,threshold_f)
    if(is.na(index) && preserve_no_freeze) 0 else index
  })
  names(result) <- paste0(
    "mint_last_freeze_day_", format(season_start, "%Y"), "_through_", observation_end
  )
  terra::time(result) <- observation_end
  result
}

prism_last_freeze_cache_manifest_path <- function(processed_dir = swc_paths$processed) {
  file.path(processed_dir, "prism", "last-freeze-cache-manifest.csv")
}

prism_last_freeze_cache_path <- function(
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
    "last-freeze-samples", "mint", paste0("at-or-below-", threshold_label),
    "aug01-jul31.tif"
  )
}

read_prism_last_freeze_cache <- function(path, expected_years = NULL) {
  if (!file.exists(path)) stop("Last-freeze cache does not exist: ", path, call. = FALSE)
  raster <- terra::rast(path)
  dates <- as.Date(terra::time(raster))
  if (length(dates) != terra::nlyr(raster) || anyNA(dates) || anyDuplicated(dates)) {
    stop("Last-freeze cache must have one unique season-start date per layer.", call. = FALSE)
  }
  if (!is.null(expected_years)) {
    expected_dates <- as.Date(sprintf("%d-08-01", as.integer(expected_years)))
    if (length(dates) != length(expected_dates) || any(dates != expected_dates)) {
      stop("Last-freeze cache seasons do not match the requested baseline.", call. = FALSE)
    }
  }
  raster
}

build_prism_last_freeze_cache <- function(
    threshold_f = 32,
    baseline_start = swc_prism$normal_start,
    baseline_end = swc_prism$normal_end,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    manifest_path = prism_last_freeze_cache_manifest_path(processed_dir),
    overwrite = FALSE,
    progress_every = 5L,
    quiet = FALSE) {
  progress_every <- validate_prism_progress_every(progress_every)
  periods <- prism_first_freeze_periods(baseline_start, baseline_end)
  source_dates <- seq(min(periods$start_date), max(periods$end_date), by = "day")
  selection <- select_prism_daily_sources("mint", source_dates, aoi_id, processed_manifest)
  source_signature <- prism_temperature_threshold_source_signature(
    selection, processed_manifest, threshold_f
  )
  path <- prism_last_freeze_cache_path(
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
    identical(as.integer(tail(existing$cache_version, 1L)), prism_last_freeze_cache_version) &&
    identical(tail(existing$source_signature, 1L), source_signature) &&
    identical(tail(existing$md5, 1L), unname(tools::md5sum(path)))
  if (current && !overwrite) {
    if (!quiet) message("Using current last-freeze climatology cache.")
    return(invisible(list(
      raster = read_prism_last_freeze_cache(path, periods$season_year),
      periods = periods,
      path = path,
      source_signature = source_signature,
      refreshed = FALSE
    )))
  }

  if (!quiet) {
    message(
      "Building last-freeze cache from ", nrow(periods),
      " August-July seasons and ", length(source_dates), " daily layers."
    )
  }
  started <- proc.time()[["elapsed"]]
  layers <- vector("list", nrow(periods))
  for (index in seq_len(nrow(periods))) {
    dates <- seq(periods$start_date[[index]], periods$end_date[[index]], by = "day")
    collection <- read_prism_best_daily_range(
      "mint", dates, aoi_id, processed_manifest
    )
    layers[[index]] <- prism_last_freeze_from_raster(
      collection$raster,
      periods$start_date[[index]],
      threshold_f,
      periods$end_date[[index]], preserve_no_freeze=TRUE
    )
    if (!quiet && (index %% progress_every == 0L || index == nrow(periods))) {
      message(
        "  Last-freeze seasons: ", index, "/", nrow(periods), " (",
        format_prism_elapsed(proc.time()[["elapsed"]] - started), ")."
      )
    }
  }
  samples <- do.call(c, layers)
  terra::time(samples) <- periods$start_date
  names(samples) <- paste0("mint_last_freeze_day_", periods$season_year)
  write_prism_processed_raster(samples, path, datatype = "FLT4S")
  record <- data.frame(
    product = "last_freeze_season_sample",
    cache_version = prism_last_freeze_cache_version,
    aoi_id = aoi_id,
    variable = "mint",
    native_units = "day_since_august_1",
    threshold_f = threshold_f,
    season_start_month_day = "08-01",
    season_end_month_day = "07-31",
    start_date = as.Date(baseline_start),
    end_date = as.Date(baseline_end),
    sample_layers = terra::nlyr(samples),
    no_freeze_encoding = '0 = verified no freeze; NA = incomplete observations',
    source_signature = source_signature,
    built_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    bytes = file.info(path)$size,
    md5 = unname(tools::md5sum(path)),
    path = path,
    stringsAsFactors = FALSE
  )
  write_prism_manifest(record, manifest_path)
  if (!quiet) message("Wrote last-freeze cache: ", path)
  invisible(list(
    raster = read_prism_last_freeze_cache(path, periods$season_year),
    periods = periods,
    path = path,
    source_signature = source_signature,
    refreshed = TRUE
  ))
}

prism_last_freeze_climatology <- function(samples, minimum_frequency = 0.8) {
  climatology <- prism_first_freeze_climatology(samples, minimum_frequency,censor='last')
  names(climatology$frequency) <- "mint_last_freeze_frequency"
  names(climatology$median_day) <- "mint_last_freeze_median_day"
  climatology
}

prism_last_freeze_departure_raster <- function(observed_day, normal_day, date, minimum_freeze_free_days=14L) {
  if(length(minimum_freeze_free_days)!=1L || !is.finite(minimum_freeze_free_days) || minimum_freeze_free_days<0 || minimum_freeze_free_days!=floor(minimum_freeze_free_days)) stop('minimum_freeze_free_days must be a non-negative integer.')
  if (terra::nlyr(observed_day) != 1L || terra::nlyr(normal_day) != 1L) {
    stop("Observed and normal last-freeze rasters must each contain one layer.", call. = FALSE)
  }
  terra::compareGeom(observed_day, normal_day, stopOnError = TRUE)
  current_day <- as.integer(as.Date(date)-prism_freeze_season_start(date))+1L
  final <- as.Date(date)==as.Date(sprintf('%d-07-31',as.integer(format(prism_freeze_season_start(date),'%Y'))+1L))
  eligible <- observed_day>0 & (final | (current_day>=normal_day & current_day-observed_day>=minimum_freeze_free_days))
  result <- terra::ifel(eligible,observed_day-normal_day,NA)
  date <- as.Date(date)
  names(result) <- paste0("mint_last_freeze_departure_days_", date)
  terra::time(result) <- date
  result
}

prism_last_freeze_output_path <- function(
    product = c("observed-day", "departure"),
    date,
    season_start = prism_freeze_season_start(date),
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  product <- match.arg(product)
  file.path(
    processed_dir, "prism", aoi_id, "seasonal", "last-freeze", "mint",
    paste0("season-", format(as.Date(season_start), "%Y")), product,
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_last_freeze_map_path <- function(
    product = c("observed-day", "departure"),
    date = NULL,
    maps_dir = swc_paths$maps) {
  product <- match.arg(product)
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  product_label <- if (product == "observed-day") "date" else "departure"
  file.path(
    maps_dir, "prism", "temperature",
    paste0("mint-last-freeze-", product_label, "-", suffix, ".png")
  )
}

calculate_prism_last_freeze_products <- function(
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
  season_start <- prism_freeze_season_start(date)
  dates <- seq(season_start, date, by = "day")
  collection <- read_prism_best_daily_range(
    "mint", dates, aoi_id, processed_manifest
  )
  observed_sample <- prism_last_freeze_from_raster(
    collection$raster, season_start, threshold_f, date,preserve_no_freeze=TRUE
  )
  observed <- terra::ifel(observed_sample>0,observed_sample,NA)
  names(observed) <- names(observed_sample); terra::time(observed) <- date
  cache <- build_prism_last_freeze_cache(
    threshold_f, baseline_start, baseline_end, aoi_id, processed_dir,
    processed_manifest, overwrite = cache_overwrite,
    progress_every = progress_every, quiet = quiet
  )
  climatology <- prism_last_freeze_climatology(cache$raster, minimum_frequency)
  departure <- prism_last_freeze_departure_raster(
    observed, climatology$median_day, date
  )
  final <- date==as.Date(sprintf('%d-07-31',as.integer(format(season_start,'%Y'))+1L))
  pending <- terra::ifel(!final & !is.na(observed_sample) & !is.na(climatology$median_day) & is.na(departure),1,NA)
  terra::time(pending) <- date; names(pending) <- paste0('mint_last_freeze_season_in_progress_',date)
  paths <- c(
    `observed-day` = prism_last_freeze_output_path(
      "observed-day", date, season_start, aoi_id, processed_dir
    ),
    departure = prism_last_freeze_output_path(
      "departure", date, season_start, aoi_id, processed_dir
    )
  )
  paths <- c(paths,`season-in-progress`=sub('/departure/','/season-in-progress/',paths[['departure']],fixed=TRUE))
  rasters <- list(`observed-day` = observed, departure = departure,`season-in-progress`=pending)
  for (product in names(rasters)) {
    if (file.exists(paths[[product]]) && !overwrite) {
      stop("Last-freeze output already exists; set `overwrite = TRUE`: ", paths[[product]], call. = FALSE)
    }
    write_prism_processed_raster(rasters[[product]], paths[[product]])
  }
  list(
    date = date,
    season_start = season_start,
    season_label = prism_first_freeze_season_label(season_start),
    threshold_f = threshold_f,
    minimum_frequency = minimum_frequency,
    publishable = prism_last_freeze_publishable(date),
    observed_day = observed,
    departure = departure,
    season_in_progress = pending,
    normal_day = climatology$median_day,
    frequency = climatology$frequency,
    paths = paths,
    cache = cache
  )
}

build_prism_last_freeze_map <- function(
    raster,
    product = c("observed-day", "departure"),
    date = as.Date(terra::time(raster)),
    season_start = prism_freeze_season_start(date),
    threshold_f = 32,
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),status_raster=NULL) {
  product <- match.arg(product)
  date <- as.Date(date)
  season_start <- as.Date(season_start)
  if(product=='observed-day') raster <- terra::app(raster,function(x,...) prism_freeze_plot_day_index(x,season_start))
  if (product == "observed-day") {
    title <- paste0("Last freeze observed so far: ", prism_first_freeze_season_label(season_start))
    subtitle <- paste0(
      format_prism_map_period(season_start, date),
      " | minimum temperature at or below ", threshold_f, " degrees F"
    )
    fill_label <- "Last freeze date"
    palette <- c("#313695", "#4575b4", "#74add1", "#abd9e9", "#fee090", "#fdae61", "#f46d43", "#a50026")
    values <- c(1, 93, 154, 213, 244, 274, 305, 365)
    limits <- c(1, 365)
    breaks <- c(93, 154, 213, 274, 365)
    labels <- c("Nov 1", "Jan 1", "Mar 1", "May 1", "Jul 31")
  } else {
    title <- paste0("Last-freeze departure: ", prism_first_freeze_season_label(season_start))
    subtitle <- paste0(
      "Through ", format_prism_map_date(date),
      " | vs ",prism_reference_year_label('normal')," median | provisional; >=14 days since freeze"
    )
    fill_label <- "Departure (days; negative = early)"
    palette <- c("#313695", "#4575b4", "#abd9e9", "#f7f7f7", "#fdae61", "#d73027", "#7f0000")
    values <- c(-60, -30, -10, 0, 10, 30, 60)
    limits <- c(-60, 60)
    breaks <- c(-60, -30, 0, 30, 60)
    labels <- c("-60", "-30", "0", "+30", "+60")
  }
  plot <- southwest_raster_map(
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
      `observed-day` = "mint_last_freeze_date",
      departure = "mint_last_freeze_departure"
    ),
    mask_to_states = FALSE
  )
  prism_freeze_status_overlay(plot,if(product=='departure') status_raster else NULL,'Season in progress','#b8bec3',template=raster)
}

build_current_prism_last_freeze_maps <- function(
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
    map_products = c("observed-day", "departure")) {
  map_products <- validate_southwest_map_products(
    map_products, c("observed-day", "departure")
  )
  products <- calculate_prism_last_freeze_products(
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
        "Last-freeze maps are not yet publishable; the prior completed-season maps are retained until March 1."
      )
    }
    return(invisible(data.frame(
      date = products$date,
      season = products$season_label,
      product = map_products,
      published = FALSE,
      stringsAsFactors = FALSE
    )))
  }
  states <- southwest_state_boundaries()
  counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries()
  cities <- southwest_reference_cities()
  rasters <- list(`observed-day` = products$observed_day, departure = products$departure)
  rasters <- rasters[map_products]
  records <- vector("list", length(rasters))
  for (index in seq_along(rasters)) {
    product <- names(rasters)[[index]]
    if (!quiet) message("Building last-freeze ", product, " map.")
    plot <- build_prism_last_freeze_map(
      rasters[[product]], product, products$date, products$season_start,
      products$threshold_f, states, counties, countries, cities,
      status_raster=if(product=='departure') products$season_in_progress else NULL
    )
    dated_map <- prism_last_freeze_map_path(product, products$date, maps_dir)
    latest_map <- prism_last_freeze_map_path(product, maps_dir = maps_dir)
    footer <- if (product == "observed-day") {
      "Data source: PRISM Climate Group via RCC-ACIS"
    } else {
      prism_map_footer_text()
    }
    save_southwest_map(plot, dated_map, logo_path = logo_path, footer_text = footer)
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest last-freeze map: ", latest_map, call. = FALSE)
    }
    finite_values <- terra::values(rasters[[product]],mat=FALSE)
    finite_values <- finite_values[is.finite(finite_values)]
    value_range <- if(length(finite_values)) range(finite_values) else c(NA_real_,NA_real_)
    records[[index]] <- data.frame(
      date = products$date,
      season = products$season_label,
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
