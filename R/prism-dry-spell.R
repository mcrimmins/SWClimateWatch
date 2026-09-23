# Calculate and map current PRISM dry-spell length and seasonal percentile.

prism_dry_spell_cache_version <- 3L

prism_dry_spell_source_dates <- function(
    end_dates,
    lookback_days,
    available_start = swc_prism$archive_start) {
  end_dates <- sort(unique(as.Date(end_dates)))
  lookback_days <- as.integer(lookback_days)
  available_start <- as.Date(available_start)
  if (length(end_dates) == 0L || anyNA(end_dates)) {
    stop("`end_dates` must contain at least one valid date.", call. = FALSE)
  }
  if (length(lookback_days) != 1L || is.na(lookback_days) || lookback_days < 1L) {
    stop("`lookback_days` must be a positive integer.", call. = FALSE)
  }
  dates <- lapply(end_dates, function(end_date) {
    seq(max(available_start, end_date - lookback_days + 1L), end_date, by = "day")
  })
  sort(unique(as.Date(unlist(dates), origin = "1970-01-01")))
}

prism_trailing_dry_length <- function(values, wet_day_threshold) {
  if (length(values) == 0L || is.na(values[[length(values)]])) return(NA_real_)
  wet <- which(!is.na(values) & prism_is_wet_day(values, wet_day_threshold))
  if (length(wet) == 0L) {
    if (anyNA(values)) return(NA_real_)
    return(length(values))
  }
  last_wet <- tail(wet, 1L)
  trailing <- if (last_wet == length(values)) numeric() else values[(last_wet + 1L):length(values)]
  if (anyNA(trailing)) return(NA_real_)
  length(values) - last_wet
}

prism_dry_spell_lengths_for_end_dates <- function(
    raster,
    dates,
    end_dates,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    lookback_days = 365L,
    available_start = swc_prism$archive_start,
    progress_every = 25L,
    quiet = FALSE) {
  dates <- as.Date(dates)
  end_dates <- sort(unique(as.Date(end_dates)))
  lookback_days <- as.integer(lookback_days)
  available_start <- as.Date(available_start)
  progress_every <- validate_prism_progress_every(progress_every)
  if (terra::nlyr(raster) != length(dates) || anyNA(dates) || anyDuplicated(dates)) {
    stop("The dry-spell source must have one unique valid date per layer.", call. = FALSE)
  }
  if (length(wet_day_threshold) != 1L || !is.finite(wet_day_threshold) ||
      wet_day_threshold < 0) {
    stop("`wet_day_threshold` must be one non-negative number.", call. = FALSE)
  }

  started <- proc.time()[["elapsed"]]
  layers <- vector("list", length(end_dates))
  effective_days <- integer(length(end_dates))
  for (index in seq_along(end_dates)) {
    start_date <- max(available_start, end_dates[[index]] - lookback_days + 1L)
    needed <- seq(start_date, end_dates[[index]], by = "day")
    selected <- match(needed, dates)
    if (anyNA(selected)) {
      stop(
        "Dry-spell input is incomplete; first missing date: ",
        format(needed[which(is.na(selected))[[1L]]]),
        call. = FALSE
      )
    }
    effective_days[[index]] <- length(selected)
    layers[[index]] <- terra::app(
      raster[[selected]],
      fun = prism_trailing_dry_length,
      wet_day_threshold = wet_day_threshold
    )
    if (!quiet && (index %% progress_every == 0L || index == length(end_dates))) {
      message(
        "  Dry-spell reference lengths: ", index, "/", length(end_dates),
        " ending dates (", format_prism_elapsed(proc.time()[["elapsed"]] - started), ")."
      )
    }
  }
  result <- do.call(c, layers)
  terra::time(result) <- end_dates
  names(result) <- paste0("pcpn_dry_spell_days_", end_dates)
  censored <- lapply(seq_along(layers), function(index) {
    layers[[index]] >= effective_days[[index]]
  })
  censored_any <- if (length(censored) == 1L) censored[[1L]] else terra::app(do.call(c, censored), max, na.rm = TRUE)
  censored_cells <- terra::global(censored_any, "sum", na.rm = TRUE)[[1L, 1L]]
  list(
    raster = result,
    censored_cells = as.numeric(censored_cells),
    lookback_days = lookback_days
  )
}

prism_dry_spell_cache_manifest_path <- function(processed_dir = swc_paths$processed) {
  file.path(processed_dir, "prism", "dry-spell-cache-manifest.csv")
}

prism_dry_spell_cache_path <- function(
    target_date,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  window_days <- validate_prism_window(window_days)
  threshold_label <- sprintf("wet-%03din", round(wet_day_threshold * 100))
  baseline_label <- paste0(
    format(as.Date(baseline_start), "%Y%m%d"), "-",
    format(as.Date(baseline_end), "%Y%m%d")
  )
  file.path(
    processed_dir, "prism", aoi_id, "climatology", baseline_label,
    "dry-spell-samples", "pcpn", threshold_label,
    sprintf("centered-%02dday", window_days),
    paste0(format(as.Date(target_date), "%m-%d"), ".tif")
  )
}

read_prism_dry_spell_cache <- function(path, expected_dates = NULL) {
  if (!file.exists(path)) stop("Dry-spell cache does not exist: ", path, call. = FALSE)
  raster <- terra::rast(path)
  dates <- as.Date(terra::time(raster))
  if (length(dates) != terra::nlyr(raster) || anyNA(dates) || anyDuplicated(dates)) {
    stop("Dry-spell cache must have one unique valid date per layer: ", path, call. = FALSE)
  }
  if (!is.null(expected_dates)) {
    expected_dates <- sort(unique(as.Date(expected_dates)))
    if (length(dates) != length(expected_dates) || any(dates != expected_dates)) {
      stop("Dry-spell cache dates do not match the requested seasonal sample.", call. = FALSE)
    }
  }
  raster
}

build_prism_dry_spell_cache <- function(
    target_date,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    initial_lookback_days = 365L,
    maximum_lookback_days = 3650L,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    manifest_path = prism_dry_spell_cache_manifest_path(processed_dir),
    overwrite = FALSE,
    allow_incremental = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  target_date <- as.Date(target_date)
  initial_lookback_days <- as.integer(initial_lookback_days)
  maximum_lookback_days <- as.integer(maximum_lookback_days)
  if (initial_lookback_days < 1L || maximum_lookback_days < initial_lookback_days) {
    stop("Dry-spell lookback limits must be positive and ordered.", call. = FALSE)
  }
  reference_groups <- prism_reference_window_dates(
    target_date, baseline_start, baseline_end, window_days
  )
  reference_end_dates <- sort(unique(do.call(c, reference_groups)))
  path <- prism_dry_spell_cache_path(
    target_date, baseline_start, baseline_end, window_days,
    wet_day_threshold, aoi_id, processed_dir
  )
  cache_manifest <- read_prism_manifest(manifest_path)
  existing <- if (nrow(cache_manifest) > 0L &&
      all(c("path", "source_signature", "lookback_days") %in% names(cache_manifest))) {
    cache_manifest[cache_manifest$path == path, , drop = FALSE]
  } else {
    data.frame()
  }

  # Recreate the selected-source fingerprint with the lookback that produced
  # the existing cache before deciding whether it is reusable.
  current <- FALSE
  source_signature <- NA_character_
  if (nrow(existing) > 0L && file.exists(path)) {
    recorded_lookback <- as.integer(tail(existing$lookback_days, 1L))
    source_dates <- prism_dry_spell_source_dates(
      reference_end_dates, recorded_lookback, swc_prism$archive_start
    )
    selection <- select_prism_daily_sources("pcpn", source_dates, aoi_id, processed_manifest)
    source_signature <- prism_accumulation_source_signature(selection, processed_manifest)
    version_current <- "cache_version" %in% names(existing) &&
      identical(as.integer(tail(existing$cache_version, 1L)), prism_dry_spell_cache_version)
    checksum_current <- "md5" %in% names(existing) &&
      identical(tail(existing$md5, 1L), unname(tools::md5sum(path)))
    current <- version_current && checksum_current &&
      identical(tail(existing$source_signature, 1L), source_signature)
  }
  if (current && !overwrite) {
    if (!quiet) message("Using current dry-spell cache for ", format(target_date, "%m-%d"), ".")
    return(invisible(list(
      raster = read_prism_dry_spell_cache(path, reference_end_dates),
      groups = reference_groups,
      path = path,
      source_signature = source_signature,
      lookback_days = as.integer(tail(existing$lookback_days, 1L)),
      build_method = if ("build_method" %in% names(existing)) {
        tail(existing$build_method, 1L)
      } else {
        "direct"
      },
      refreshed = FALSE
    )))
  }

  calculated <- NULL
  lookback_days <- initial_lookback_days
  build_method <- "direct"
  parent_path <- NA_character_
  parent_md5 <- NA_character_
  target_key <- format(target_date, "%m-%d")
  previous_date <- target_date - 1L
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
    previous_path <- prism_dry_spell_cache_path(
      previous_date, baseline_start, baseline_end, window_days,
      wet_day_threshold, aoi_id, processed_dir
    )
    previous_record <- if (nrow(cache_manifest) > 0L &&
        all(c("path", "source_signature", "lookback_days", "cache_version", "md5") %in% names(cache_manifest))) {
      cache_manifest[cache_manifest$path == previous_path, , drop = FALSE]
    } else {
      data.frame()
    }
    if (dates_advance_one_day && file.exists(previous_path) && nrow(previous_record) > 0L &&
        identical(as.integer(tail(previous_record$cache_version, 1L)), prism_dry_spell_cache_version)) {
      previous_lookback <- as.integer(tail(previous_record$lookback_days, 1L))
      previous_source_dates <- prism_dry_spell_source_dates(
        previous_end_dates, previous_lookback, swc_prism$archive_start
      )
      previous_selection <- select_prism_daily_sources(
        "pcpn", previous_source_dates, aoi_id, processed_manifest
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
            "Incrementing dry-spell cache from ", previous_key,
            " to ", target_key, "."
          )
        }
        previous <- read_prism_dry_spell_cache(previous_path, previous_end_dates)
        daily <- read_prism_best_daily_range(
          "pcpn", reference_end_dates, aoi_id, processed_manifest
        )$raster
        terra::compareGeom(previous, daily, stopOnError = TRUE)
        result <- terra::ifel(prism_is_wet_day(daily, wet_day_threshold), 0, previous + 1)
        terra::time(result) <- reference_end_dates
        names(result) <- paste0("pcpn_dry_spell_days_", reference_end_dates)
        calculated <- list(
          raster = result,
          censored_cells = 0,
          lookback_days = previous_lookback
        )
        lookback_days <- previous_lookback
        source_dates <- prism_dry_spell_source_dates(
          reference_end_dates, lookback_days, swc_prism$archive_start
        )
        selection <- select_prism_daily_sources(
          "pcpn", source_dates, aoi_id, processed_manifest
        )
        source_signature <- prism_accumulation_source_signature(
          selection, processed_manifest
        )
        build_method <- "incremental"
        parent_path <- previous_path
        parent_md5 <- actual_md5
      }
    }
  }

  while (is.null(calculated)) {
    source_dates <- prism_dry_spell_source_dates(
      reference_end_dates, lookback_days, swc_prism$archive_start
    )
    selection <- select_prism_daily_sources("pcpn", source_dates, aoi_id, processed_manifest)
    source_signature <- prism_accumulation_source_signature(selection, processed_manifest)
    if (!quiet) {
      message(
        "Building dry-spell cache for ", format(target_date, "%m-%d"),
        " with a ", lookback_days, "-day lookback from ",
        length(source_dates), " daily layers."
      )
    }
    collection <- read_prism_best_daily_range(
      "pcpn", source_dates, aoi_id, processed_manifest
    )
    calculated <- prism_dry_spell_lengths_for_end_dates(
      collection$raster, collection$dates, reference_end_dates,
      wet_day_threshold, lookback_days, swc_prism$archive_start,
      progress_every, quiet
    )
    if (calculated$censored_cells == 0) break
    if (lookback_days >= maximum_lookback_days) {
      stop(
        "Dry-spell calculation still contains ", calculated$censored_cells,
        " lookback-censored cells at ", lookback_days, " days.",
        call. = FALSE
      )
    }
    lookback_days <- min(maximum_lookback_days, lookback_days * 2L)
    if (!quiet) message("Expanding dry-spell lookback to ", lookback_days, " days.")
    calculated <- NULL
  }

  write_prism_processed_raster(calculated$raster, path)
  record <- data.frame(
    product = "seasonal_dry_spell_sample",
    cache_version = prism_dry_spell_cache_version,
    aoi_id = aoi_id,
    variable = "pcpn",
    native_units = "day",
    wet_day_threshold_inches = wet_day_threshold,
    target_calendar_day = format(target_date, "%m-%d"),
    method = sprintf("centered-%02dday", validate_prism_window(window_days)),
    window_days = validate_prism_window(window_days),
    lookback_days = lookback_days,
    censored_cells = calculated$censored_cells,
    build_method = build_method,
    parent_path = parent_path,
    parent_md5 = parent_md5,
    start_date = as.Date(baseline_start),
    end_date = as.Date(baseline_end),
    sample_layers = terra::nlyr(calculated$raster),
    source_signature = source_signature,
    built_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    bytes = file.info(path)$size,
    md5 = unname(tools::md5sum(path)),
    path = path,
    stringsAsFactors = FALSE
  )
  write_prism_manifest(record, manifest_path)
  if (!quiet) message("Wrote dry-spell cache: ", path)
  invisible(list(
    raster = read_prism_dry_spell_cache(path, reference_end_dates),
    groups = reference_groups,
    path = path,
    source_signature = source_signature,
    lookback_days = lookback_days,
    build_method = build_method,
    refreshed = TRUE
  ))
}

prism_dry_spell_output_path <- function(
    product = c("length", "percentile-rank"),
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  product <- match.arg(product)
  file.path(
    processed_dir, "prism", aoi_id, "daily", "dry-spell", "pcpn", product,
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_dry_spell_map_path <- function(
    product = c("length", "percentile-rank"),
    date = NULL,
    maps_dir = swc_paths$maps) {
  product <- match.arg(product)
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "precipitation",
    paste("pcpn", "current-dry-spell", product, suffix, sep = "-") |> paste0(".png")
  )
}

calculate_prism_current_dry_spell <- function(
    date,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    initial_lookback_days = 365L,
    maximum_lookback_days = 3650L,
    aoi_id = swc_prism$aoi_id,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    quiet = FALSE) {
  date <- as.Date(date)
  lookback_days <- as.integer(initial_lookback_days)
  maximum_lookback_days <- as.integer(maximum_lookback_days)
  repeat {
    source_dates <- prism_dry_spell_source_dates(
      date, lookback_days, swc_prism$archive_start
    )
    if (!quiet) {
      message("Calculating current dry spell with a ", lookback_days, "-day lookback.")
    }
    collection <- read_prism_best_daily_range(
      "pcpn", source_dates, aoi_id, processed_manifest
    )
    calculated <- prism_dry_spell_lengths_for_end_dates(
      collection$raster, collection$dates, date,
      wet_day_threshold, lookback_days, swc_prism$archive_start,
      progress_every = 1L, quiet = TRUE
    )
    if (calculated$censored_cells == 0) break
    if (lookback_days >= maximum_lookback_days) {
      stop(
        "Current dry-spell calculation still contains ", calculated$censored_cells,
        " lookback-censored cells at ", lookback_days, " days.",
        call. = FALSE
      )
    }
    lookback_days <- min(maximum_lookback_days, lookback_days * 2L)
    if (!quiet) message("Expanding current dry-spell lookback to ", lookback_days, " days.")
  }
  result <- calculated$raster
  names(result) <- paste0("pcpn_current_dry_spell_days_", date)
  terra::time(result) <- date
  list(raster = result, lookback_days = lookback_days)
}

prism_dry_spell_percentile_rank_raster <- function(
    current_dry_spell,
    reference_dry_spells,
    current_date) {
  if (terra::nlyr(current_dry_spell) != 1L) {
    stop("The current dry-spell raster must contain exactly one layer.", call. = FALSE)
  }
  terra::compareGeom(current_dry_spell, reference_dry_spells, stopOnError = TRUE)
  result <- terra::app(c(current_dry_spell, reference_dry_spells), fun = function(x, ...) {
    prism_type8_percentile_rank(x[[1L]], x[-1L])
  })
  current_date <- as.Date(current_date)
  names(result) <- paste0("pcpn_current_dry_spell_percentile_rank_", current_date)
  terra::time(result) <- current_date
  result
}

calculate_prism_dry_spell_products <- function(
    date = NULL,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    wet_day_threshold = swc_prism$wet_day_threshold_inches,
    initial_lookback_days = 365L,
    maximum_lookback_days = 3650L,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    cache_overwrite = FALSE,
    overwrite = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  if (is.null(date)) {
    date <- latest_common_prism_date(
      "pcpn", aoi_id = aoi_id, processed_manifest = processed_manifest
    )
  }
  date <- as.Date(date)
  current <- calculate_prism_current_dry_spell(
    date, wet_day_threshold, initial_lookback_days, maximum_lookback_days,
    aoi_id, processed_manifest, quiet
  )
  cache <- build_prism_dry_spell_cache(
    date, baseline_start, baseline_end, window_days, wet_day_threshold,
    initial_lookback_days, maximum_lookback_days, aoi_id, processed_dir,
    processed_manifest, overwrite = cache_overwrite,
    progress_every = progress_every, quiet = quiet
  )
  ranks <- lapply(cache$groups, function(group_dates) {
    selected <- which(as.Date(terra::time(cache$raster)) %in% group_dates)
    prism_dry_spell_percentile_rank_raster(
      current$raster, cache$raster[[selected]], date
    )
  })
  rank <- if (length(ranks) == 1L) ranks[[1L]] else Reduce(`+`, ranks) / length(ranks)
  names(rank) <- paste0("pcpn_current_dry_spell_percentile_rank_", date)
  terra::time(rank) <- date
  paths <- c(
    length = prism_dry_spell_output_path("length", date, aoi_id, processed_dir),
    `percentile-rank` = prism_dry_spell_output_path("percentile-rank", date, aoi_id, processed_dir)
  )
  rasters <- list(length = current$raster, `percentile-rank` = rank)
  for (product in names(rasters)) {
    if (file.exists(paths[[product]]) && !overwrite) {
      stop("Dry-spell output already exists; set `overwrite = TRUE`: ", paths[[product]], call. = FALSE)
    }
    write_prism_processed_raster(rasters[[product]], paths[[product]])
  }
  list(
    date = date,
    length = current$raster,
    percentile_rank = rank,
    current_lookback_days = current$lookback_days,
    reference_lookback_days = cache$lookback_days,
    paths = paths,
    cache = cache
  )
}

build_prism_dry_spell_map <- function(
    raster,
    product = c("length", "percentile-rank"),
    date = as.Date(terra::time(raster)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),
    rivers = southwest_major_rivers()) {
  product <- match.arg(product)
  date <- as.Date(date)
  if (product == "length") {
    title <- "Current dry-spell length"
    subtitle <- paste0(
      "Through ", format_prism_map_date(date),
      " | wet day threshold: 0.04 inch"
    )
    fill_label <- "Consecutive dry days"
    palette <- c("#1a9850", "#91cf60", "#d9ef8b", "#fee08b", "#fc8d59", "#d73027", "#7f0000")
    values <- c(0, 3, 7, 14, 30, 60, 90)
    limits <- c(0, 90)
    breaks <- c(0, 7, 14, 30, 60, 90)
    labels <- c("0", "7", "14", "30", "60", "90+")
  } else {
    title <- "Current dry-spell percentile rank"
    subtitle <- paste0(
      format_prism_map_date(date),
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
      length = "pcpn_current_dry_spell_length",
      `percentile-rank` = "pcpn_current_dry_spell_percentile"
    ),
    mask_to_states = FALSE
  )
}

build_current_prism_dry_spell_maps <- function(
    date = NULL,
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
  products <- calculate_prism_dry_spell_products(
    date = date,
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
    if (!quiet) message("Building current dry-spell ", product, " map.")
    plot <- build_prism_dry_spell_map(
      rasters[[product]], product, products$date,
      states, counties, countries, cities
    )
    dated_map <- prism_dry_spell_map_path(product, products$date, maps_dir)
    latest_map <- prism_dry_spell_map_path(product, maps_dir = maps_dir)
    footer <- if (product == "length") {
      "Data source: PRISM Climate Group via RCC-ACIS"
    } else {
      prism_map_footer_text()
    }
    save_southwest_map(
      plot, dated_map, logo_path = logo_path,
      footer_text = footer
    )
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest dry-spell map: ", latest_map, call. = FALSE)
    }
    value_range <- range(terra::values(rasters[[product]]), na.rm = TRUE)
    records[[index]] <- data.frame(
      date = products$date,
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
