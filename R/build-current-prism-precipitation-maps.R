# Build current PRISM precipitation accumulation and percentile-rank maps.

select_prism_daily_sources <- function(
    variable,
    dates,
    aoi_id = swc_prism$aoi_id,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path())) {
  variable <- validate_prism_variables(variable)
  if (length(variable) != 1L) {
    stop("Exactly one PRISM variable is required.", call. = FALSE)
  }
  dates <- sort(unique(as.Date(dates)))
  if (length(dates) == 0L || anyNA(dates)) {
    stop("`dates` must contain at least one valid date.", call. = FALSE)
  }

  required <- c(
    "product", "aoi_id", "variable", "native_units", "start_date", "end_date",
    "processed_at", "path"
  )
  missing <- setdiff(required, names(processed_manifest))
  if (length(missing) > 0L) {
    stop("Processed manifest is missing column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
  eligible <- processed_manifest[
    processed_manifest$product == "daily" &
      !is.na(processed_manifest$aoi_id) & processed_manifest$aoi_id == aoi_id &
      processed_manifest$variable == variable,
    , drop = FALSE
  ]
  expected_unit <- unname(swc_prism$native_units[[variable]])
  if (nrow(eligible) > 0L && any(eligible$native_units != expected_unit)) {
    stop("Processed files do not consistently use the expected native units.", call. = FALSE)
  }

  selections <- lapply(dates, function(date) {
    candidates <- eligible[
      eligible$start_date <= date & eligible$end_date >= date,
      , drop = FALSE
    ]
    if (nrow(candidates) == 0L) {
      stop("No processed PRISM source contains ", format(date), ".", call. = FALSE)
    }
    span_days <- as.integer(candidates$end_date - candidates$start_date)
    recent <- grepl("[\\\\/]daily[\\\\/]recent[\\\\/]", candidates$path)
    processed_at <- suppressWarnings(as.numeric(as.POSIXct(candidates$processed_at, tz = "UTC")))
    processed_at[is.na(processed_at)] <- 0
    choice <- order(!recent, span_days, -processed_at)[[1L]]
    data.frame(
      date = date,
      path = candidates$path[[choice]],
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, selections)
}

read_prism_best_daily_range <- function(
    variable,
    dates,
    aoi_id = swc_prism$aoi_id,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path())) {
  selection <- select_prism_daily_sources(
    variable = variable,
    dates = dates,
    aoi_id = aoi_id,
    processed_manifest = processed_manifest
  )
  if (any(!file.exists(selection$path))) {
    stop("The processed manifest references one or more missing rasters.", call. = FALSE)
  }

  # Read and subset each source file once. This is materially faster than
  # constructing one SpatRaster object per day for long water-year samples.
  source_paths <- unique(selection$path)
  subsets <- lapply(source_paths, function(path) {
    source <- read_prism_daily_raster(path, variable, validate_values = FALSE)
    source_dates <- as.Date(terra::time(source))
    needed_dates <- selection$date[selection$path == path]
    layers <- match(needed_dates, source_dates)
    if (anyNA(layers) || anyDuplicated(layers)) {
      problem_date <- needed_dates[which(is.na(layers) | duplicated(layers))[[1L]]]
      stop(
        "Selected PRISM source does not contain exactly one layer for ",
        format(problem_date), ".",
        call. = FALSE
      )
    }
    result <- source[[layers]]
    terra::time(result) <- needed_dates
    result
  })
  reference <- subsets[[1L]]
  if (length(subsets) > 1L) {
    for (index in 2:length(subsets)) {
      terra::compareGeom(reference, subsets[[index]], stopOnError = TRUE)
    }
  }
  raster <- do.call(c, subsets)
  dates <- as.Date(terra::time(raster))
  ordering <- order(dates)
  raster <- raster[[ordering]]
  dates <- dates[ordering]
  terra::time(raster) <- dates
  names(raster) <- paste(variable, format(dates), sep = "_")
  list(raster = raster, dates = dates, sources = selection)
}

prism_accumulation_from_raster <- function(raster, variable, end_date) {
  variable <- validate_prism_variables(variable)
  if (length(variable) != 1L || variable != "pcpn") {
    stop("Accumulation maps currently support only `pcpn`.", call. = FALSE)
  }
  dates <- as.Date(terra::time(raster))
  if (terra::nlyr(raster) == 0L || length(dates) != terra::nlyr(raster) || anyNA(dates)) {
    stop("The accumulation input must have one valid date per layer.", call. = FALSE)
  }
  expected <- seq(min(dates), max(dates), by = "day")
  if (length(dates) != length(expected) || any(dates != expected)) {
    stop("The accumulation input must be complete and ordered by date.", call. = FALSE)
  }
  result <- if (terra::nlyr(raster) == 1L) {
    raster[[1L]]
  } else {
    terra::app(raster, sum, na.rm = FALSE)
  }
  end_date <- as.Date(end_date)
  names(result) <- paste0("pcpn_total_", sprintf("%02d", length(dates)), "day_", end_date)
  terra::time(result) <- end_date
  result
}

prism_accumulation_output_path <- function(
    days,
    end_date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  file.path(
    processed_dir, "prism", aoi_id, "daily", "accumulation", "pcpn",
    paste0(sprintf("%02d", as.integer(days)), "day"),
    paste0(format(as.Date(end_date)), ".tif")
  )
}

prism_precipitation_map_path <- function(
    days,
    date = NULL,
    maps_dir = swc_paths$maps) {
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "precipitation",
    paste0("pcpn-total-", sprintf("%02d", as.integer(days)), "day-", suffix, ".png")
  )
}

prism_accumulation_percentile_rank_output_path <- function(
    days,
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  file.path(
    processed_dir, "prism", aoi_id, "daily", "percentile-rank", "pcpn",
    paste0(sprintf("%02d", as.integer(days)), "day"),
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_precipitation_percentile_map_path <- function(
    days,
    date = NULL,
    maps_dir = swc_paths$maps) {
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "precipitation",
    paste0(
      "pcpn-percentile-rank-", sprintf("%02d", as.integer(days)),
      "day-", suffix, ".png"
    )
  )
}

prism_precipitation_scale <- function(days) {
  days <- as.integer(days)
  thresholds <- switch(
    as.character(days),
    `1` = c(0, 0.01, 0.10, 0.25, 0.50, 1, 2, 4),
    `7` = c(0, 0.05, 0.25, 0.50, 1, 2, 4, 8),
    `30` = c(0, 0.10, 0.50, 1, 2, 4, 8, 15),
    `90` = c(0, 0.25, 1, 2, 5, 10, 20, 35),
    stop("Supported precipitation windows are 1, 7, 30, and 90 days.", call. = FALSE)
  )
  breaks <- switch(
    as.character(days),
    `1` = c(0, 0.5, 1, 2, 4),
    `7` = c(0, 1, 2, 4, 8),
    `30` = c(0, 2, 4, 8, 15),
    `90` = c(0, 5, 10, 20, 35)
  )
  labels <- vapply(
    breaks,
    format,
    character(1),
    trim = TRUE,
    scientific = FALSE
  )
  labels[[length(labels)]] <- paste0(labels[[length(labels)]], "+")
  list(
    palette = c(
      "#f7fbff", "#d9eff7", "#92c5de", "#4393c3",
      "#41ab5d", "#fddc6c", "#f46d43", "#7a0177"
    ),
    values = thresholds,
    limits = range(thresholds),
    breaks = breaks,
    labels = labels
  )
}

format_prism_map_period <- function(start_date, end_date) {
  start_date <- as.Date(start_date)
  end_date <- as.Date(end_date)
  if (start_date == end_date) return(format_prism_map_date(end_date))
  if (format(start_date, "%Y-%m") == format(end_date, "%Y-%m")) {
    return(paste0(
      sub(" 0", " ", format(start_date, "%B %d"), fixed = TRUE),
      "-",
      as.integer(format(end_date, "%d")),
      ", ",
      format(end_date, "%Y")
    ))
  }
  if (format(start_date, "%Y") == format(end_date, "%Y")) {
    paste0(
      sub(" 0", " ", format(start_date, "%B %d"), fixed = TRUE),
      "-",
      format_prism_map_date(end_date)
    )
  } else {
    paste(format_prism_map_date(start_date), format_prism_map_date(end_date), sep = "-")
  }
}

prism_precipitation_footer_text <- function(start_date, end_date) {
  paste(
    "Data source: PRISM Climate Group via RCC-ACIS",
    paste0("Accumulation period: ", format_prism_map_period(start_date, end_date)),
    sep = "\n"
  )
}

build_prism_accumulation_map <- function(
    accumulation,
    days,
    end_date = as.Date(terra::time(accumulation)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),
    rivers = southwest_major_rivers()) {
  days <- as.integer(days)
  if (!days %in% c(1L, 7L, 30L, 90L)) {
    stop("Supported precipitation windows are 1, 7, 30, and 90 days.", call. = FALSE)
  }
  end_date <- as.Date(end_date)
  start_date <- end_date - days + 1L
  scale <- prism_precipitation_scale(days)
  title <- switch(
    as.character(days),
    `1` = "Daily precipitation",
    `7` = "7-day total precipitation",
    `30` = "30-day total precipitation",
    `90` = "90-day total precipitation"
  )
  southwest_raster_map(
    raster = accumulation,
    states = states,
    title = title,
    subtitle = format_prism_map_period(start_date, end_date),
    caption = NULL,
    fill_label = "Precipitation (inches)",
    palette = scale$palette,
    palette_values = scale$values,
    limits = scale$limits,
    breaks = scale$breaks,
    labels = scale$labels,
    counties = counties,
    countries = countries,
    rivers = rivers,
    cities = cities,
    product_id = paste0("pcpn_total_", sprintf("%02d", days), "day"),
    mask_to_states = FALSE
  )
}

build_current_precipitation_maps <- function(
    date = NULL,
    windows = c(1L, 7L, 30L, 90L),
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    quiet = FALSE,
    map_windows = windows) {
  windows <- sort(unique(as.integer(windows)))
  if (length(windows) == 0L || any(!windows %in% c(1L, 7L, 30L, 90L))) {
    stop("Supported precipitation windows are 1, 7, 30, and 90 days.", call. = FALSE)
  }
  map_windows <- sort(unique(as.integer(map_windows)))
  if (anyNA(map_windows) || any(!map_windows %in% windows)) {
    stop("`map_windows` must be a subset of `windows`.", call. = FALSE)
  }
  if (is.null(date)) {
    date <- latest_common_prism_date("pcpn", aoi_id = aoi_id)
  }
  date <- as.Date(date)
  dates <- seq(date - max(windows) + 1L, date, by = "day")
  manifest <- read_prism_manifest(prism_processed_manifest_path(processed_dir))
  collection <- read_prism_best_daily_range(
    variable = "pcpn",
    dates = dates,
    aoi_id = aoi_id,
    processed_manifest = manifest
  )
  states <- southwest_state_boundaries()
  counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries()
  cities <- southwest_reference_cities()
  records <- vector("list", length(windows))

  for (index in seq_along(windows)) {
    days <- windows[[index]]
    start_date <- date - days + 1L
    selected <- which(collection$dates >= start_date & collection$dates <= date)
    accumulation <- prism_accumulation_from_raster(
      collection$raster[[selected]],
      "pcpn",
      date
    )
    output_path <- prism_accumulation_output_path(days, date, aoi_id, processed_dir)
    if (file.exists(output_path) && !overwrite) {
      stop("Accumulation output already exists; set `overwrite = TRUE`: ", output_path, call. = FALSE)
    }
    write_prism_processed_raster(accumulation, output_path)
    publish_map <- days %in% map_windows
    dated_map <- latest_map <- NA_character_
    if (publish_map) {
      if (!quiet) message("Building ", days, "-day precipitation map through ", date, ".")
      plot <- build_prism_accumulation_map(
        accumulation,
        days,
        date,
        states = states,
        counties = counties,
        countries = countries,
        cities = cities
      )
      dated_map <- prism_precipitation_map_path(days, date, maps_dir)
      latest_map <- prism_precipitation_map_path(days, maps_dir = maps_dir)
      save_southwest_map(
        plot,
        dated_map,
        logo_path = logo_path,
        footer_text = prism_precipitation_footer_text(start_date, date)
      )
      dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
      if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
        stop("Could not update latest precipitation map: ", latest_map, call. = FALSE)
      }
    } else if (!quiet) {
      message("Updated ", days, "-day precipitation data prerequisite; map is disabled.")
    }
    value_range <- range(terra::values(accumulation), na.rm = TRUE)
    records[[index]] <- data.frame(
      end_date = date,
      days = days,
      minimum_inches = value_range[[1L]],
      maximum_inches = value_range[[2L]],
      published = publish_map,
      accumulation_path = output_path,
      map_path = dated_map,
      latest_map_path = latest_map,
      stringsAsFactors = FALSE
    )
  }
  invisible(do.call(rbind, records))
}

prism_rolling_source_dates <- function(end_dates, accumulation_days) {
  end_dates <- sort(unique(as.Date(end_dates)))
  accumulation_days <- as.integer(accumulation_days)
  if (length(end_dates) == 0L || anyNA(end_dates)) {
    stop("`end_dates` must contain at least one valid date.", call. = FALSE)
  }
  if (length(accumulation_days) != 1L || is.na(accumulation_days) || accumulation_days < 1L) {
    stop("`accumulation_days` must be a positive integer.", call. = FALSE)
  }
  values <- unlist(lapply(end_dates, function(date) {
    seq(date - accumulation_days + 1L, date, by = "day")
  }))
  sort(unique(as.Date(values, origin = "1970-01-01")))
}

prism_rolling_totals_for_end_dates <- function(
    raster,
    dates,
    end_dates,
    accumulation_days,
    progress_every = 25L,
    quiet = FALSE) {
  dates <- as.Date(dates)
  end_dates <- sort(unique(as.Date(end_dates)))
  accumulation_days <- as.integer(accumulation_days)
  progress_every <- validate_prism_progress_every(progress_every)
  if (terra::nlyr(raster) != length(dates) || anyNA(dates) || anyDuplicated(dates)) {
    stop("The source raster must have one unique valid date per layer.", call. = FALSE)
  }

  started <- proc.time()[["elapsed"]]
  layers <- vector("list", length(end_dates))
  for (index in seq_along(end_dates)) {
    needed <- seq(
      end_dates[[index]] - accumulation_days + 1L,
      end_dates[[index]],
      by = "day"
    )
    selected <- match(needed, dates)
    if (anyNA(selected)) {
      stop(
        "Rolling reference input is incomplete; first missing date: ",
        format(needed[which(is.na(selected))[[1L]]]),
        call. = FALSE
      )
    }
    layers[[index]] <- if (accumulation_days == 1L) {
      raster[[selected]]
    } else {
      terra::app(raster[[selected]], sum, na.rm = FALSE)
    }
    if (!quiet && (index %% progress_every == 0L || index == length(end_dates))) {
      message(
        "  ", accumulation_days, "-day reference totals: ", index, "/",
        length(end_dates), " ending dates (",
        format_prism_elapsed(proc.time()[["elapsed"]] - started), ")."
      )
    }
  }
  result <- do.call(c, layers)
  terra::time(result) <- end_dates
  names(result) <- paste0(
    "pcpn_total_", sprintf("%02d", accumulation_days), "day_", end_dates
  )
  result
}

prism_accumulation_percentile_rank_raster <- function(
    current_accumulation,
    reference_accumulations,
    accumulation_days,
    current_date) {
  if (terra::nlyr(current_accumulation) != 1L) {
    stop("The current accumulation must contain exactly one layer.", call. = FALSE)
  }
  terra::compareGeom(current_accumulation, reference_accumulations, stopOnError = TRUE)
  result <- terra::app(c(current_accumulation, reference_accumulations), fun = function(x, ...) {
    prism_type8_percentile_rank(x[[1L]], x[-1L])
  })
  current_date <- as.Date(current_date)
  accumulation_days <- as.integer(accumulation_days)
  names(result) <- paste0(
    "pcpn_percentile_rank_", sprintf("%02d", accumulation_days),
    "day_", current_date
  )
  terra::time(result) <- current_date
  result
}

calculate_prism_accumulation_percentile_rank <- function(
    current_accumulation,
    accumulation_days,
    current_date = as.Date(terra::time(current_accumulation)),
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    use_cache = TRUE,
    cache_overwrite = FALSE,
    cache_manifest_path = file.path(processed_dir, "prism", "accumulation-cache-manifest.csv"),
    output_path = NULL,
    overwrite = FALSE,
    progress_every = 25L,
    quiet = FALSE) {
  accumulation_days <- as.integer(accumulation_days)
  if (length(accumulation_days) != 1L || is.na(accumulation_days) || accumulation_days < 1L) {
    stop("`accumulation_days` must be a positive integer.", call. = FALSE)
  }
  current_date <- as.Date(current_date)
  reference_groups <- prism_reference_window_dates(
    current_date,
    baseline_start = baseline_start,
    baseline_end = baseline_end,
    window_days = window_days
  )
  reference_end_dates <- sort(unique(do.call(c, reference_groups)))
  if (isTRUE(use_cache)) {
    if (!exists("build_prism_accumulation_cache", mode = "function")) {
      stop("Source `R/prism-accumulation-cache.R` before using the accumulation cache.", call. = FALSE)
    }
    cache <- build_prism_accumulation_cache(
      accumulation_days = accumulation_days,
      target_date = current_date,
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
    reference_totals <- cache$raster
    reference_groups <- cache$groups
  } else {
    source_dates <- prism_rolling_source_dates(reference_end_dates, accumulation_days)
    if (!quiet) {
      message(
        "Loading ", length(source_dates), " daily precipitation layers for ",
        accumulation_days, "-day reference totals."
      )
    }
    collection <- read_prism_best_daily_range(
      variable = "pcpn",
      dates = source_dates,
      aoi_id = aoi_id,
      processed_manifest = processed_manifest
    )
    reference_totals <- prism_rolling_totals_for_end_dates(
      collection$raster,
      collection$dates,
      reference_end_dates,
      accumulation_days,
      progress_every = progress_every,
      quiet = quiet
    )
  }

  ranks <- lapply(reference_groups, function(group_dates) {
    selected <- which(as.Date(terra::time(reference_totals)) %in% group_dates)
    prism_accumulation_percentile_rank_raster(
      current_accumulation,
      reference_totals[[selected]],
      accumulation_days,
      current_date
    )
  })
  result <- if (length(ranks) == 1L) {
    ranks[[1L]]
  } else {
    Reduce(`+`, ranks) / length(ranks)
  }
  names(result) <- paste0(
    "pcpn_percentile_rank_", sprintf("%02d", accumulation_days),
    "day_", current_date
  )
  terra::time(result) <- current_date

  if (!is.null(output_path)) {
    if (file.exists(output_path) && !overwrite) {
      stop("Percentile-rank output already exists; set `overwrite = TRUE`: ", output_path, call. = FALSE)
    }
    write_prism_processed_raster(result, output_path)
    if (!quiet) message("Wrote precipitation percentile-rank raster: ", output_path)
  }
  result
}

build_prism_accumulation_percentile_rank_map <- function(
    rank_raster,
    accumulation_days,
    date = as.Date(terra::time(rank_raster)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),
    rivers = southwest_major_rivers()) {
  accumulation_days <- as.integer(accumulation_days)
  if (!accumulation_days %in% c(7L, 30L, 90L)) {
    stop("Rolling precipitation percentile-rank maps support 7-, 30-, and 90-day totals.", call. = FALSE)
  }
  date <- as.Date(date)
  start_date <- date - accumulation_days + 1L
  southwest_raster_map(
    raster = rank_raster,
    states = states,
    title = paste0(accumulation_days, "-day precipitation percentile rank"),
    subtitle = paste0(
      format_prism_map_period(start_date, date),
      " relative to 1991-2020 | centered 5-day baseline"
    ),
    caption = NULL,
    fill_label = "Percentile rank",
    palette = c("#7f3b08", "#b35806", "#f1a340", "#f7f7f7", "#998ec3", "#542788", "#2d004b"),
    palette_values = c(0, 10, 25, 50, 75, 90, 100),
    limits = c(0, 100),
    breaks = c(0, 10, 25, 50, 75, 90, 100),
    labels = c("0", "10", "25", "50", "75", "90", "100"),
    counties = counties,
    countries = countries,
    rivers = rivers,
    cities = cities,
    product_id = paste0("pcpn_percentile_", sprintf("%02d", accumulation_days), "day"),
    mask_to_states = FALSE
  )
}

build_current_precipitation_percentile_maps <- function(
    date = NULL,
    windows = c(7L, 30L, 90L),
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  windows <- sort(unique(as.integer(windows)))
  if (length(windows) == 0L || any(!windows %in% c(7L, 30L, 90L))) {
    stop("Rolling precipitation percentile-rank maps support 7-, 30-, and 90-day totals.", call. = FALSE)
  }
  if (is.null(date)) {
    date <- latest_common_prism_date("pcpn", aoi_id = aoi_id)
  }
  date <- as.Date(date)
  manifest <- read_prism_manifest(prism_processed_manifest_path(processed_dir))
  states <- southwest_state_boundaries()
  counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries()
  cities <- southwest_reference_cities()
  records <- vector("list", length(windows))

  for (index in seq_along(windows)) {
    days <- windows[[index]]
    accumulation_path <- prism_accumulation_output_path(days, date, aoi_id, processed_dir)
    if (!file.exists(accumulation_path)) {
      stop(
        "Current accumulation is missing; run `build_current_precipitation_maps()` first: ",
        accumulation_path,
        call. = FALSE
      )
    }
    accumulation <- terra::rast(accumulation_path)
    rank_path <- prism_accumulation_percentile_rank_output_path(
      days, date, aoi_id, processed_dir
    )
    if (!quiet) message("Calculating ", days, "-day precipitation percentile rank.")
    rank <- calculate_prism_accumulation_percentile_rank(
      current_accumulation = accumulation,
      accumulation_days = days,
      current_date = date,
      aoi_id = aoi_id,
      processed_dir = processed_dir,
      processed_manifest = manifest,
      output_path = rank_path,
      overwrite = overwrite,
      progress_every = progress_every,
      quiet = quiet
    )
    plot <- build_prism_accumulation_percentile_rank_map(
      rank,
      days,
      date,
      states = states,
      counties = counties,
      countries = countries,
      cities = cities
    )
    dated_map <- prism_precipitation_percentile_map_path(days, date, maps_dir)
    latest_map <- prism_precipitation_percentile_map_path(days, maps_dir = maps_dir)
    save_southwest_map(
      plot,
      dated_map,
      logo_path = logo_path,
      footer_text = prism_map_footer_text()
    )
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest precipitation percentile map: ", latest_map, call. = FALSE)
    }
    value_range <- range(terra::values(rank), na.rm = TRUE)
    records[[index]] <- data.frame(
      date = date,
      days = days,
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

prism_accumulation_percentile_change_output_path <- function(
    accumulation_days = 30L,
    change_days = 14L,
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  file.path(
    processed_dir, "prism", aoi_id, "daily", "percentile-rank-change", "pcpn",
    paste0(sprintf("%02d", as.integer(accumulation_days)), "day"),
    paste0(sprintf("%02d", as.integer(change_days)), "day-change"),
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_precipitation_percentile_change_map_path <- function(
    accumulation_days = 30L,
    change_days = 14L,
    date = NULL,
    maps_dir = swc_paths$maps) {
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "precipitation",
    paste0(
      "pcpn-percentile-rank-change-",
      sprintf("%02d", as.integer(accumulation_days)), "day-over-",
      sprintf("%02d", as.integer(change_days)), "day-",
      suffix, ".png"
    )
  )
}

prism_accumulation_percentile_change_raster <- function(
    current_rank,
    previous_rank,
    accumulation_days = 30L,
    change_days = 14L,
    current_date = as.Date(terra::time(current_rank))) {
  if (terra::nlyr(current_rank) != 1L || terra::nlyr(previous_rank) != 1L) {
    stop("Current and previous percentile ranks must each have one layer.", call. = FALSE)
  }
  accumulation_days <- as.integer(accumulation_days)
  change_days <- as.integer(change_days)
  if (
    length(accumulation_days) != 1L || is.na(accumulation_days) ||
      accumulation_days < 1L
  ) {
    stop("`accumulation_days` must be a positive integer.", call. = FALSE)
  }
  if (length(change_days) != 1L || is.na(change_days) || change_days < 1L) {
    stop("`change_days` must be a positive integer.", call. = FALSE)
  }
  current_date <- as.Date(current_date)
  previous_date <- current_date - change_days
  current_time <- as.Date(terra::time(current_rank))
  previous_time <- as.Date(terra::time(previous_rank))
  if (
    length(current_time) != 1L || is.na(current_time) || current_time != current_date ||
      length(previous_time) != 1L || is.na(previous_time) || previous_time != previous_date
  ) {
    stop("Percentile-rank dates do not match the requested change period.", call. = FALSE)
  }
  terra::compareGeom(current_rank, previous_rank, stopOnError = TRUE)
  result <- current_rank - previous_rank
  names(result) <- paste0(
    "pcpn_percentile_rank_change_",
    sprintf("%02d", accumulation_days), "day_over_",
    sprintf("%02d", change_days), "day_", current_date
  )
  terra::time(result) <- current_date
  result
}

calculate_prism_accumulation_for_date <- function(
    accumulation_days,
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    output_path = prism_accumulation_output_path(
      accumulation_days, date, aoi_id, processed_dir
    ),
    overwrite = TRUE) {
  accumulation_days <- as.integer(accumulation_days)
  date <- as.Date(date)
  dates <- seq(date - accumulation_days + 1L, date, by = "day")
  collection <- read_prism_best_daily_range(
    "pcpn", dates, aoi_id, processed_manifest
  )
  result <- prism_accumulation_from_raster(
    collection$raster, "pcpn", date
  )
  if (!is.null(output_path)) {
    if (file.exists(output_path) && !overwrite) {
      stop("Accumulation output already exists; set `overwrite = TRUE`: ", output_path, call. = FALSE)
    }
    write_prism_processed_raster(result, output_path)
  }
  result
}

build_prism_accumulation_percentile_change_map <- function(
    change_raster,
    accumulation_days = 30L,
    change_days = 14L,
    date = as.Date(terra::time(change_raster)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),
    rivers = southwest_major_rivers()) {
  accumulation_days <- as.integer(accumulation_days)
  change_days <- as.integer(change_days)
  date <- as.Date(date)
  previous_date <- date - change_days
  southwest_raster_map(
    raster = change_raster,
    states = states,
    title = paste0(
      change_days, "-day change in ", accumulation_days,
      "-day precipitation percentile rank"
    ),
    subtitle = paste0(
      format_prism_map_date(previous_date), " to ",
      format_prism_map_date(date),
      " | positive = wetter, negative = drier"
    ),
    caption = NULL,
    fill_label = "Percentile-point change",
    palette = c(
      "#7f2704", "#d94801", "#fdbb84", "#f7f7f7",
      "#b3cde3", "#4393c3", "#08519c"
    ),
    palette_values = c(-100, -50, -25, 0, 25, 50, 100),
    limits = c(-100, 100),
    breaks = c(-100, -50, -25, 0, 25, 50, 100),
    labels = c("-100", "-50", "-25", "0", "+25", "+50", "+100"),
    counties = counties,
    countries = countries,
    rivers = rivers,
    cities = cities,
    product_id = "pcpn_percentile_change_30day_14day",
    mask_to_states = FALSE
  )
}

build_current_precipitation_percentile_change_map <- function(
    date = NULL,
    accumulation_days = 30L,
    change_days = 14L,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  accumulation_days <- as.integer(accumulation_days)
  change_days <- as.integer(change_days)
  if (accumulation_days != 30L || change_days != 14L) {
    stop("The operational change map currently supports a 30-day rank over 14 days.", call. = FALSE)
  }
  manifest <- read_prism_manifest(prism_processed_manifest_path(processed_dir))
  if (is.null(date)) {
    date <- latest_common_prism_date(
      "pcpn", aoi_id = aoi_id, processed_manifest = manifest
    )
  }
  date <- as.Date(date)
  previous_date <- date - change_days

  rank_for_date <- function(rank_date, reuse_existing = FALSE) {
    rank_path <- prism_accumulation_percentile_rank_output_path(
      accumulation_days, rank_date, aoi_id, processed_dir
    )
    if (isTRUE(reuse_existing) && file.exists(rank_path)) {
      rank <- terra::rast(rank_path)
      if (
        terra::nlyr(rank) == 1L &&
          identical(as.Date(terra::time(rank)), rank_date)
      ) {
        return(list(raster = rank, path = rank_path, reused = TRUE))
      }
    }
    accumulation <- calculate_prism_accumulation_for_date(
      accumulation_days = accumulation_days,
      date = rank_date,
      aoi_id = aoi_id,
      processed_dir = processed_dir,
      processed_manifest = manifest,
      overwrite = overwrite
    )
    rank <- calculate_prism_accumulation_percentile_rank(
      current_accumulation = accumulation,
      accumulation_days = accumulation_days,
      current_date = rank_date,
      baseline_start = baseline_start,
      baseline_end = baseline_end,
      window_days = window_days,
      aoi_id = aoi_id,
      processed_dir = processed_dir,
      processed_manifest = manifest,
      output_path = rank_path,
      overwrite = overwrite,
      progress_every = progress_every,
      quiet = quiet
    )
    list(raster = rank, path = rank_path, reused = FALSE)
  }

  if (!quiet) {
    message(
      "Calculating ", change_days, "-day change in the ",
      accumulation_days, "-day precipitation percentile rank."
    )
  }
  current <- rank_for_date(date, reuse_existing = TRUE)
  previous <- rank_for_date(previous_date, reuse_existing = FALSE)
  change <- prism_accumulation_percentile_change_raster(
    current$raster,
    previous$raster,
    accumulation_days,
    change_days,
    date
  )
  output_path <- prism_accumulation_percentile_change_output_path(
    accumulation_days, change_days, date, aoi_id, processed_dir
  )
  if (file.exists(output_path) && !overwrite) {
    stop("Percentile-change output already exists; set `overwrite = TRUE`: ", output_path, call. = FALSE)
  }
  write_prism_processed_raster(change, output_path)

  plot <- build_prism_accumulation_percentile_change_map(
    change,
    accumulation_days,
    change_days,
    date
  )
  dated_map <- prism_precipitation_percentile_change_map_path(
    accumulation_days, change_days, date, maps_dir
  )
  latest_map <- prism_precipitation_percentile_change_map_path(
    accumulation_days, change_days, maps_dir = maps_dir
  )
  save_southwest_map(
    plot,
    dated_map,
    logo_path = logo_path,
    footer_text = prism_map_footer_text(baseline_start, baseline_end)
  )
  dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
    stop("Could not update latest precipitation percentile-change map: ", latest_map, call. = FALSE)
  }
  value_range <- range(terra::values(change), na.rm = TRUE)
  invisible(data.frame(
    date = date,
    previous_date = previous_date,
    accumulation_days = accumulation_days,
    change_days = change_days,
    minimum_change = value_range[[1L]],
    maximum_change = value_range[[2L]],
    current_rank_path = current$path,
    previous_rank_path = previous$path,
    change_path = output_path,
    map_path = dated_map,
    latest_map_path = latest_map,
    stringsAsFactors = FALSE
  ))
}

prism_accumulation_percent_normal_output_path <- function(
    days,
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  file.path(
    processed_dir, "prism", aoi_id, "daily", "percent-normal", "pcpn",
    paste0(sprintf("%02d", as.integer(days)), "day"),
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_precipitation_percent_normal_map_path <- function(
    days,
    date = NULL,
    maps_dir = swc_paths$maps) {
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "precipitation",
    paste0(
      "pcpn-percent-normal-", sprintf("%02d", as.integer(days)),
      "day-", suffix, ".png"
    )
  )
}

prism_precipitation_percent_normal_scale <- function() {
  list(
    palette = c(
      "#543005", "#8c510a", "#d8b365", "#f6e8c3",
      "#f5f5f5", "#c7eae5", "#5ab4ac", "#01665e"
    ),
    values = c(0, 25, 50, 75, 100, 125, 150, 200),
    limits = c(0, 200),
    breaks = c(0, 50, 75, 100, 125, 150, 200),
    labels = c("0", "50", "75", "100", "125", "150", "200+")
  )
}

prism_accumulation_percent_normal_raster <- function(
    current_accumulation,
    reference_accumulations,
    accumulation_days,
    current_date,
    minimum_normal_inches = swc_prism$percent_normal_minimum_inches) {
  accumulation_days <- as.integer(accumulation_days)
  current_date <- as.Date(current_date)
  if (terra::nlyr(current_accumulation) != 1L || terra::nlyr(reference_accumulations) < 1L) {
    stop("Current accumulation must have one layer and the reference must not be empty.", call. = FALSE)
  }
  if (length(accumulation_days) != 1L || is.na(accumulation_days) || accumulation_days < 1L) {
    stop("`accumulation_days` must be a positive integer.", call. = FALSE)
  }
  if (length(minimum_normal_inches) != 1L || !is.finite(minimum_normal_inches) ||
      minimum_normal_inches < 0) {
    stop("`minimum_normal_inches` must be one non-negative number.", call. = FALSE)
  }
  terra::compareGeom(current_accumulation, reference_accumulations, stopOnError = TRUE)
  normal <- terra::app(reference_accumulations, mean, na.rm = FALSE)
  result <- terra::ifel(
    normal >= minimum_normal_inches,
    100 * current_accumulation / normal,
    NA
  )
  names(result) <- paste0(
    "pcpn_percent_normal_", sprintf("%02d", accumulation_days),
    "day_", current_date
  )
  terra::time(result) <- current_date
  result
}

calculate_prism_accumulation_percent_normal <- function(
    current_accumulation,
    accumulation_days,
    current_date = as.Date(terra::time(current_accumulation)),
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    minimum_normal_inches = swc_prism$percent_normal_minimum_inches,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    cache_overwrite = FALSE,
    cache_manifest_path = prism_accumulation_cache_manifest_path(processed_dir),
    output_path = NULL,
    overwrite = FALSE,
    progress_every = 25L,
    quiet = FALSE) {
  accumulation_days <- as.integer(accumulation_days)
  current_date <- as.Date(current_date)
  cache <- build_prism_accumulation_cache(
    accumulation_days = accumulation_days,
    target_date = current_date,
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
  result <- prism_accumulation_percent_normal_raster(
    current_accumulation,
    cache$raster,
    accumulation_days,
    current_date,
    minimum_normal_inches
  )
  if (!is.null(output_path)) {
    if (file.exists(output_path) && !overwrite) {
      stop("Percent-of-normal output already exists; set `overwrite = TRUE`: ", output_path, call. = FALSE)
    }
    write_prism_processed_raster(result, output_path)
    if (!quiet) message("Wrote precipitation percent-of-normal raster: ", output_path)
  }
  result
}

build_prism_accumulation_percent_normal_map <- function(
    percent_normal,
    accumulation_days,
    date = as.Date(terra::time(percent_normal)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),
    rivers = southwest_major_rivers()) {
  accumulation_days <- as.integer(accumulation_days)
  if (!accumulation_days %in% c(30L, 90L)) {
    stop("Percent-of-normal maps support 30- and 90-day totals.", call. = FALSE)
  }
  date <- as.Date(date)
  start_date <- date - accumulation_days + 1L
  scale <- prism_precipitation_percent_normal_scale()
  southwest_raster_map(
    raster = percent_normal,
    states = states,
    title = paste0(accumulation_days, "-day precipitation percent of normal"),
    subtitle = paste0(
      format_prism_map_period(start_date, date),
      " relative to 1991-2020 | centered 5-day baseline"
    ),
    caption = NULL,
    fill_label = "Percent of normal",
    palette = scale$palette,
    palette_values = scale$values,
    limits = scale$limits,
    breaks = scale$breaks,
    labels = scale$labels,
    counties = counties,
    countries = countries,
    rivers = rivers,
    cities = cities,
    product_id = paste0("pcpn_percent_normal_", sprintf("%02d", accumulation_days), "day"),
    mask_to_states = FALSE
  )
}

build_current_precipitation_percent_normal_maps <- function(
    date = NULL,
    windows = c(30L, 90L),
    minimum_normal_inches = swc_prism$percent_normal_minimum_inches,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  windows <- sort(unique(as.integer(windows)))
  if (length(windows) == 0L || any(!windows %in% c(30L, 90L))) {
    stop("Percent-of-normal maps support 30- and 90-day totals.", call. = FALSE)
  }
  if (is.null(date)) {
    date <- latest_common_prism_date("pcpn", aoi_id = aoi_id)
  }
  date <- as.Date(date)
  manifest <- read_prism_manifest(prism_processed_manifest_path(processed_dir))
  states <- southwest_state_boundaries()
  counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries()
  cities <- southwest_reference_cities()
  records <- vector("list", length(windows))

  for (index in seq_along(windows)) {
    days <- windows[[index]]
    accumulation_path <- prism_accumulation_output_path(days, date, aoi_id, processed_dir)
    if (!file.exists(accumulation_path)) {
      stop(
        "Current accumulation is missing; run `build_current_precipitation_maps()` first: ",
        accumulation_path,
        call. = FALSE
      )
    }
    accumulation <- terra::rast(accumulation_path)
    output_path <- prism_accumulation_percent_normal_output_path(
      days, date, aoi_id, processed_dir
    )
    if (!quiet) message("Calculating ", days, "-day precipitation percent of normal.")
    percent_normal <- calculate_prism_accumulation_percent_normal(
      current_accumulation = accumulation,
      accumulation_days = days,
      current_date = date,
      minimum_normal_inches = minimum_normal_inches,
      aoi_id = aoi_id,
      processed_dir = processed_dir,
      processed_manifest = manifest,
      output_path = output_path,
      overwrite = overwrite,
      progress_every = progress_every,
      quiet = quiet
    )
    plot <- build_prism_accumulation_percent_normal_map(
      percent_normal, days, date, states, counties, countries, cities
    )
    dated_map <- prism_precipitation_percent_normal_map_path(days, date, maps_dir)
    latest_map <- prism_precipitation_percent_normal_map_path(days, maps_dir = maps_dir)
    save_southwest_map(
      plot, dated_map, logo_path = logo_path,
      footer_text = prism_map_footer_text()
    )
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest precipitation percent-of-normal map: ", latest_map, call. = FALSE)
    }
    value_range <- range(terra::values(percent_normal), na.rm = TRUE)
    records[[index]] <- data.frame(
      date = date,
      days = days,
      minimum_percent_normal = value_range[[1L]],
      maximum_percent_normal = value_range[[2L]],
      raster_path = output_path,
      map_path = dated_map,
      latest_map_path = latest_map,
      stringsAsFactors = FALSE
    )
  }
  invisible(do.call(rbind, records))
}
