# Read-only local evidence inventory. No source requests or publication hooks.

synopsis_date <- function(x) {
  date <- tryCatch(as.Date(x), error = function(e) as.Date(NA))
  if (length(date) != 1L || is.na(date)) stop("Supply one valid snapshot date.")
  date
}

synopsis_config <- function(path) {
  x <- yaml::read_yaml(path)
  if (!is.null(x$maximum_section_bullets) && (!is.numeric(x$maximum_section_bullets) || length(x$maximum_section_bullets) != 1L ||
      is.na(x$maximum_section_bullets) || !x$maximum_section_bullets %in% 2:3)) stop("Synopsis section limit must be two or three.")
  for (name in c("minimum_area_coverage", "rain_threshold_inches", "lower_percentile",
      "upper_percentile", "very_low_percentile", "very_high_percentile", "maximum_station_examples",
      "minimum_weekly_daily_rain_inches", "minimum_weekly_three_day_rain_inches",
      "minimum_recent_rain_area_percent", "material_area_change_points", "material_temperature_change_f")) {
    if (!is.numeric(x[[name]]) || length(x[[name]]) != 1L || !is.finite(x[[name]]))
      stop("Invalid synopsis setting: ", name)
  }
  if (x$minimum_area_coverage <= 0 || x$minimum_area_coverage > 1 ||
      any(unlist(x[c("minimum_weekly_daily_rain_inches", "minimum_weekly_three_day_rain_inches",
        "minimum_recent_rain_area_percent", "material_area_change_points", "material_temperature_change_f")]) <= 0) ||
      x$minimum_recent_rain_area_percent > 100 ||
      x$material_area_change_points > 100 ||
      x$rain_threshold_inches < 0 || x$maximum_station_examples < 0 || x$maximum_station_examples > 2 ||
      x$maximum_station_examples != floor(x$maximum_station_examples) ||
      !all(diff(c(0, x$very_low_percentile, x$lower_percentile,
        x$upper_percentile, x$very_high_percentile, 100)) > 0)) stop("Invalid synopsis thresholds.")
  # Require exactly one editorial season on every calendar day, including leap day.
  days <- format(seq(as.Date("2000-01-01"), as.Date("2000-12-31"), by = "day"), "%m-%d")
  hits <- vapply(days, function(day) length(synopsis_season_matches(day, x)), integer(1))
  if (any(hits != 1L)) stop("Editorial seasons must cover each calendar day exactly once.")
  allowed <- c("max_daily_pcpn", "max_3day_pcpn", "hottest_day", "coldest_night", "freeze_nights_anomaly", "longest_dry_spell")
  if (!length(x$station_states) || any(!unlist(x$station_states) %in% c("AZ", "NM", "CA", "NV", "UT", "CO", "TX")) ||
      !is.numeric(x$minimum_freeze_normal_years) || length(x$minimum_freeze_normal_years) != 1L ||
      !is.finite(x$minimum_freeze_normal_years) || x$minimum_freeze_normal_years < 15 ||
      !is.numeric(x$minimum_freeze_departure_nights) || length(x$minimum_freeze_departure_nights) != 1L ||
      !is.finite(x$minimum_freeze_departure_nights) || x$minimum_freeze_departure_nights < 0)
    stop("Invalid station extreme settings.")
  for (season in names(x$seasons)) {
    metrics <- unlist(x$station_metric_order[[season]])
    if (!length(metrics) || anyDuplicated(metrics) || any(!metrics %in% allowed)) stop("Invalid station metric order: ", season)
  }
  for (field in c("minimum_extreme_rank_years", "minimum_extreme_normal_years", "unusual_station_percentile",
      "active_week_temperature_departure_f", "quiet_week_temperature_departure_f", "minimum_impact_daily_rain_inches",
      "minimum_impact_three_day_rain_inches", "minimum_dry_spell_days")) {
    if (!is.numeric(x[[field]]) || length(x[[field]]) != 1L || !is.finite(x[[field]]) || x[[field]] <= 0)
      stop("Invalid unusualness setting: ", field)
  }
  if (x$minimum_extreme_rank_years < 25 || x$minimum_extreme_normal_years < 15 ||
      x$minimum_extreme_rank_years != floor(x$minimum_extreme_rank_years) ||
      x$minimum_extreme_normal_years != floor(x$minimum_extreme_normal_years) ||
      x$minimum_extreme_normal_years > 30 || x$unusual_station_percentile <= 50 ||
      x$unusual_station_percentile > 100 || x$quiet_week_temperature_departure_f >= x$active_week_temperature_departure_f)
    stop("Invalid historical support or unusualness thresholds.")
  x
}

synopsis_season_matches <- function(day, config) {
  names(Filter(function(s) {
    valid <- format(as.Date(paste0("2000-", c(s$start, s$end))), "%m-%d")
    if (anyNA(valid) || !identical(unname(valid), c(s$start, s$end))) stop("Invalid seasonal date range.")
    if (s$start <= s$end) day >= s$start && day <= s$end else day >= s$start || day <= s$end
  }, config$seasons))
}

synopsis_season <- function(date, config) {
  name <- synopsis_season_matches(format(synopsis_date(date), "%m-%d"), config)
  if (length(name) != 1L) stop("Snapshot must match one editorial season.")
  list(id = name, emphasis = config$seasons[[name]]$emphasis)
}

synopsis_grid_specs <- function(root, date) {
  date <- synopsis_date(date)
  base <- file.path(root, "data/processed/prism/az-nm-pad050/daily")
  ids <- c("pcpn_total_30day", "pcpn_percentile_30day", "tmean_departure_30day",
    "pcpn_water_year_total", "pcpn_water_year_percentile")
  paths <- c("accumulation/pcpn/30day", "percentile-rank/pcpn/30day",
    "rolling-departure/tmean/030day", "water-year/pcpn/total", "water-year/pcpn/percentile-rank")
  wy_start <- as.Date(sprintf("%d-10-01", as.integer(format(date, "%Y")) -
    as.integer(format(date, "%m-%d") < "10-01")))
  data.frame(id = ids, path = file.path(base, paths, paste0(date, ".tif")),
    start = as.character(c(rep(date - 29L, 3L), rep(wy_start, 2L))),
    end = as.character(date), type = c("rain", "percentile", "temperature", "rain", "percentile"),
    reference = c("None (observed total)", "1991-2020; centered five-day reference",
      "1991-2020", "None (observed total)", "1991-2020; matching water-year-to-date reference"),
    link = paste0("pages/products/", ids, ".html"), stringsAsFactors = FALSE)
}

synopsis_latest_date <- function(root, today = Sys.Date()) {
  specs <- synopsis_grid_specs(root, today)
  dates <- lapply(dirname(specs$path), function(path) {
    files <- list.files(path, pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}\\.tif$")
    sub("\\.tif$", "", files)
  })
  shared <- Reduce(intersect, dates)
  shared <- shared[shared <= as.character(today)]
  if (!length(shared)) stop("No shared cached date for the five core grids; supply snapshot_date explicitly to inventory missing inputs.")
  as.Date(max(shared))
}

synopsis_regional_stats <- function(values, weights, type, config) {
  if (length(values) != length(weights) || any(weights < 0, na.rm = TRUE)) stop("Invalid area weights.")
  inside <- is.finite(weights) & weights > 0
  good <- inside & is.finite(values)
  area <- sum(weights[inside])
  coverage <- if (area > 0) sum(weights[good]) / area else 0
  metrics <- switch(type, rain = c("mean", "area_at_least_rain_threshold"),
    temperature = "mean_departure", percentile = c("area_below_lower_percentile", "area_above_upper_percentile", "area_below_very_low_percentile", "area_above_very_high_percentile"))
  if (is.null(metrics)) stop("Unknown metric type.")
  result <- setNames(rep(NA_real_, length(metrics)), metrics)
  invalid <- any(!is.na(values[inside]) & !is.finite(values[inside])) ||
    (type == "rain" && any(values[good] < 0)) ||
    (type == "percentile" && any(values[good] < 0 | values[good] > 100))
  status <- if (invalid) "INVALID_RANGE" else if (coverage < config$minimum_area_coverage || area == 0) "LOW_COVERAGE" else "AVAILABLE_CACHED"
  if (status == "AVAILABLE_CACHED") {
    fraction <- function(test) 100 * sum(weights[good & test], na.rm = TRUE) / sum(weights[good])
    result <- switch(type,
      rain = c(mean = stats::weighted.mean(values[good], weights[good]),
        area_at_least_rain_threshold = fraction(values >= config$rain_threshold_inches - 1e-7)),
      temperature = c(mean_departure = stats::weighted.mean(values[good], weights[good])),
      percentile = c(area_below_lower_percentile = fraction(values < config$lower_percentile),
        area_above_upper_percentile = fraction(values > config$upper_percentile),
        area_below_very_low_percentile = fraction(values < config$very_low_percentile),
        area_above_very_high_percentile = fraction(values > config$very_high_percentile)))
  }
  list(values = result, coverage = coverage, valid_area_km2 = sum(weights[good]),
    total_area_km2 = area, status = status)
}

# Build only small recent summaries from existing daily caches. Never downloads
# or builds a climatology; a missing input is an explicit unavailable result.
synopsis_recent_evidence <- function(root, date, config, output_dir) {
  result <- list(status = "UNAVAILABLE", facts = data.frame(), days = data.frame(),
    note = "Seven-day cached daily inputs are unavailable.", cache_reused = FALSE)
  manifest_path <- file.path(root, "data/processed/prism/manifest.csv")
  if (!file.exists(manifest_path)) return(result)
  tryCatch({
    context <- new.env(parent = globalenv())
    for (file in c("config.R", "acis-prism.R", "process-prism.R", "build-prism-climatology.R",
        "prism-percentile-rank.R", "build-current-prism-maps.R", "build-current-prism-precipitation-maps.R"))
      sys.source(file.path(root, "R", file), envir = context)
    context$swc_paths$processed <- file.path(root, "data/processed")
    manifest <- context$read_prism_manifest(manifest_path)
    relative <- !grepl("^([A-Za-z]:|[/\\\\])", manifest$path)
    manifest$path[relative] <- file.path(root, manifest$path[relative])
    dates <- seq(date - 6L, date, by = "day")
    selections <- lapply(c("pcpn", "maxt", "mint"), function(variable)
      tryCatch(context$select_prism_daily_sources(variable, dates, processed_manifest = manifest), error = function(e) NULL))
    paths <- unique(unlist(lapply(selections, function(x) x$path)))
    normals <- vapply(c("maxt", "mint"), function(variable) context$prism_climatology_path(variable,
      "mean", context$swc_prism$normal_start, context$swc_prism$normal_end,
      method = context$prism_statistic_method("mean", context$swc_prism$centered_window_days),
      aoi_id = context$swc_prism$aoi_id, processed_dir = context$swc_paths$processed), character(1))
    inputs <- c(paths, normals, file.path(root, "R/config.R"))
    signature <- digest::digest(list(version = 2L, date = date, config = config,
      paths = inputs, md5 = unname(tools::md5sum(inputs)),
      terra = as.character(utils::packageVersion("terra")), maps = as.character(utils::packageVersion("maps"))))
    cache_path <- file.path(output_dir, "recent-evidence-cache.rds")
    cached <- if (file.exists(cache_path)) tryCatch(readRDS(cache_path), error = function(e) NULL) else NULL
    cached_paths <- if (!is.null(cached$result$facts)) cached$result$facts$source_path else character()
    if (identical(cached$signature, signature) && length(cached_paths) && all(file.exists(cached_paths)) &&
        all(unname(tools::md5sum(cached_paths)) == cached$result$facts$source_md5)) {
      cached$result$cache_reused <- TRUE
      return(cached$result)
    }
    region_weights <- NULL; geometry <- NULL
    summarize <- function(raster, type) {
      if (terra::nlyr(raster) != 1L) stop("Recent evidence requires one layer.")
      if (is.null(region_weights)) {
        region_weights <<- synopsis_area_weights(raster); geometry <<- raster
      } else terra::compareGeom(geometry, raster, stopOnError = TRUE)
      values <- terra::values(raster, mat = FALSE)
      lapply(region_weights, function(w) synopsis_regional_stats(values, w, type, config))
    }
    rain <- context$read_prism_best_daily_range("pcpn", dates, processed_manifest = manifest)$raster
    total <- context$prism_accumulation_from_raster(rain, "pcpn", date)
    dir.create(file.path(output_dir, "recent-grids"), recursive = TRUE, showWarnings = FALSE)
    path <- file.path(output_dir, "recent-grids", paste0(date, "-pcpn-07day.tif"))
    context$write_prism_processed_raster(total, path)
    specs <- data.frame(id = "pcpn_total_07day", path = path, start = as.character(date - 6L),
      end = as.character(date), type = "rain", reference = "None (observed seven-day total)",
      link = "pages/products/pcpn_total_07day.html", stringsAsFactors = FALSE)
    summarize(total, "rain") # Establish masks once for this geometry.
    daily <- list()
    for (i in seq_along(dates)) {
      stats <- summarize(rain[[i]], "rain")
      for (region in names(stats)) daily[[length(daily) + 1L]] <- data.frame(
        fact_id = paste("daily-pcpn", region, dates[i], sep = ":"), date = as.character(dates[i]),
        region = region, mean_inches = stats[[region]]$values[["mean"]],
        rain_area_percent = stats[[region]]$values[["area_at_least_rain_threshold"]],
        rain_threshold_inches = config$rain_threshold_inches,
        coverage = stats[[region]]$coverage, status = stats[[region]]$status,
        link = "pages/daily-explorer.html", stringsAsFactors = FALSE)
    }
    temp_note <- ""
    temp <- tryCatch(context$calculate_prism_rolling_temperature_departure(variable = "tmean", days = 7L,
      date = date, processed_manifest = manifest, output_path = file.path(output_dir, "recent-grids", paste0(date, "-tmean-07day.tif")),
      overwrite = TRUE, quiet = TRUE), error = function(e) {temp_note <<- conditionMessage(e); NULL})
    if (!is.null(temp)) specs <- rbind(specs, data.frame(id = "tmean_departure_07day",
      path = file.path(output_dir, "recent-grids", paste0(date, "-tmean-07day.tif")),
      start = as.character(date - 6L), end = as.character(date), type = "temperature",
      reference = paste(format(context$swc_prism$normal_start, "%Y"), format(context$swc_prism$normal_end, "%Y"), sep = "-"),
      link = "pages/daily-explorer.html", stringsAsFactors = FALSE))
    facts <- synopsis_grid_facts(specs, config, function(raster) {
      terra::compareGeom(geometry, raster, stopOnError = TRUE); region_weights
    })
    result <- list(status = if (any(facts$status == "AVAILABLE_CACHED")) "AVAILABLE_CACHED" else "UNAVAILABLE",
      facts = facts, days = do.call(rbind, daily), signature = signature, source_paths = paths,
      source_md5 = unname(tools::md5sum(paths)), note = temp_note, cache_reused = FALSE)
    saveRDS(list(signature = signature, result = result), cache_path)
    result
  }, error = function(e) {result$note <- conditionMessage(e); result})
}

synopsis_area_weights <- function(raster) {
  if (!nzchar(terra::crs(raster))) stop("Grid has no CRS.")
  states <- sf::st_as_sf(maps::map("state", regions = c("arizona", "new mexico"), fill = TRUE, plot = FALSE))
  area <- terra::values(terra::cellSize(raster, unit = "km"), mat = FALSE)
  masks <- lapply(c("arizona", "new mexico"), function(state) {
    shape <- terra::project(terra::vect(states[states$ID == state, ]), terra::crs(raster))
    mask <- terra::values(terra::rasterize(shape, raster, field = 1, background = NA), mat = FALSE)
    ifelse(is.finite(mask), area, 0)
  })
  names(masks) <- c("AZ", "NM")
  c(list(AZNM = masks$AZ + masks$NM), masks)
}

synopsis_grid_facts <- function(specs, config, weights_function = synopsis_area_weights) {
  masks <- new.env(parent = emptyenv())
  rows <- list()
  for (i in seq_len(nrow(specs))) {
    spec <- specs[i, ]; note <- ""
    result <- tryCatch({
      if (!file.exists(spec$path)) stop("Derived grid missing.")
      raster <- terra::rast(spec$path)
      if (terra::nlyr(raster) != 1L) stop("Expected one derived layer.")
      stamp <- as.Date(terra::time(raster))
      if (length(stamp) != 1L || is.na(stamp) || as.character(stamp) != spec$end) stop("Grid time does not match snapshot date.")
      key <- digest::digest(list(terra::nrow(raster), terra::ncol(raster), as.vector(terra::ext(raster)), terra::crs(raster)))
      if (!exists(key, masks, inherits = FALSE)) assign(key, weights_function(raster), masks)
      weights <- get(key, masks)
      lapply(weights[c("AZNM", "AZ", "NM")], function(w) synopsis_regional_stats(terra::values(raster, mat = FALSE), w, spec$type, config))
    }, error = function(e) { note <<- conditionMessage(e); NULL })
    md5 <- if (file.exists(spec$path)) unname(tools::md5sum(spec$path)) else NA_character_
    for (region in c("AZNM", "AZ", "NM")) {
      stat <- if (!is.null(result)) result[[region]] else
        synopsis_regional_stats(rep(NA_real_, 1), 1, spec$type, config)
      for (metric in names(stat$values)) {
        cutoff <- switch(metric, area_below_lower_percentile = config$lower_percentile,
          area_above_upper_percentile = config$upper_percentile, area_below_very_low_percentile = config$very_low_percentile,
          area_above_very_high_percentile = config$very_high_percentile,
          area_at_least_rain_threshold = config$rain_threshold_inches, NA_real_)
        rows[[length(rows) + 1L]] <- data.frame(fact_id = paste(spec$id, region, metric, sep = ":"),
          product = spec$id, region = region, metric = metric, value = unname(stat$values[[metric]]),
          units = if (grepl("^area_", metric)) "percent of valid region area" else if (spec$type == "temperature") "degreeF departure" else "inch",
          threshold = cutoff, period_start = spec$start, period_end = spec$end, reference = spec$reference,
          coverage = if (is.null(result)) NA_real_ else stat$coverage,
          valid_area_km2 = if (is.null(result)) NA_real_ else stat$valid_area_km2,
          total_area_km2 = if (is.null(result)) NA_real_ else stat$total_area_km2,
          status = if (is.null(result)) "UNAVAILABLE" else stat$status, note = note,
          source_path = spec$path, source_md5 = md5, link = spec$link,
          mask_version = paste0("maps-state-center-cell-v1;maps=", utils::packageVersion("maps"),
            ";terra=", utils::packageVersion("terra")), stringsAsFactors = FALSE)
      }
    }
  }
  do.call(rbind, rows)
}

synopsis_station_extremes <- function(root, date, config, period_days = 30L) {
  if (length(period_days) != 1L || is.na(period_days) || !period_days %in% c(7L, 30L)) stop("Station window must be 7 or 30 days.")
  period_id <- paste0(period_days, "day")
  path <- file.path(root, "site/stations/station-explorer-data.csv")
  audit_path <- file.path(root, "data/diagnostics/acis-stations/publication-audit/product-readiness.csv")
  empty <- list(status = "UNAVAILABLE", candidates = data.frame(), selected = data.frame(),
    note = "Matching station summaries, daily details and publication screening are required.")
  if (!file.exists(path) || !file.exists(audit_path)) return(empty)
  rows <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  audit <- tryCatch(utils::read.csv(audit_path, stringsAsFactors = FALSE), error = function(e) NULL)
  required <- c("uid", "name", "state", "role", "as_of", "cache_as_of", "period", "period_start")
  audit_required <- c("uid", "period", "page_date", "metric", "publication_status", "caution_codes")
  if (is.null(rows) || is.null(audit) || !all(required %in% names(rows)) ||
      !all(audit_required %in% names(audit))) return(empty)
  rows <- rows[which(rows$period == period_id & rows$as_of == as.character(date) &
    rows$cache_as_of >= as.character(date) & rows$period_start == as.character(date - period_days + 1L) &
    rows$role == "fixed" & rows$state %in% unlist(config$station_states)), , drop = FALSE]
  if (anyDuplicated(rows$uid)) return(empty)
  candidates <- list()
  for (i in seq_len(nrow(rows))) {
    x <- rows[i, ]
    detail_path <- file.path(root, "site/stations/station-details", paste0(x$uid, ".json"))
    detail <- tryCatch(jsonlite::read_json(detail_path, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(detail) || !identical(as.character(detail$uid), as.character(x$uid)) ||
        !identical(detail$as_of, as.character(date)) || !is.data.frame(detail$daily) ||
        !"date" %in% names(detail$daily)) next
    daily <- detail$daily
    # An absent day or flagged/partial value cannot be silently replaced by zero.
    series <- function(variable, start, end) {
      expected <- as.character(seq(as.Date(start), as.Date(end), by = "day"))
      columns <- c(variable, paste0(variable, "_status"))
      if (!all(columns %in% names(daily))) return(NULL)
      d <- daily[daily$date %in% expected, , drop = FALSE]
      d <- d[order(d$date), , drop = FALSE]
      if (!is.numeric(d[[variable]]) || !identical(as.character(d$date), expected) ||
          anyNA(d[[columns[2]]]) || !all(d[[columns[2]]] == "AVAILABLE") || any(!is.finite(d[[variable]]))) return(NULL)
      values <- as.numeric(d[[variable]])
      if (variable == "pcpn" && any(values < 0 | values > 100)) return(NULL)
      if (variable != "pcpn" && any(values < -150 | values > 150)) return(NULL)
      if (variable != "pcpn" && all(c("maxt", "mint") %in% names(d)) && is.numeric(d$maxt) && is.numeric(d$mint) &&
          any(is.finite(d$maxt) & is.finite(d$mint) & d$maxt < d$mint)) return(NULL)
      values
    }
    number <- function(field) if (field %in% names(x)) as.numeric(x[[field]]) else NA_real_
    valid_date <- function(field) {
      if (!field %in% names(x)) return(NA_character_)
      value <- tryCatch(as.Date(x[[field]]), error = function(e) as.Date(NA))
      if (length(value) != 1L || is.na(value)) NA_character_ else as.character(value)
    }
    for (metric in c("max_daily_pcpn", "max_3day_pcpn", "hottest_day", "coldest_night", "freeze_nights_anomaly", "longest_dry_spell")) {
      if (period_days == 7L && metric == "longest_dry_spell") next
      rain <- metric %in% c("max_daily_pcpn", "max_3day_pcpn", "longest_dry_spell")
      screen <- audit[which(audit$uid == x$uid & audit$period == period_id &
        audit$page_date == as.character(date) & audit$metric == if (rain) "pcpn_value" else "tmean_value"), , drop = FALSE]
      if (nrow(screen) != 1L || !screen$publication_status %in% c("DISPLAY", "DISPLAY_CAUTION")) next
      variable <- if (rain) "pcpn" else if (metric == "hottest_day") "maxt" else "mint"
      start <- as.character(date - period_days + 1L); end <- as.character(date)
      if (metric == "freeze_nights_anomaly") {
        if (period_days == 7L) next
        start <- valid_date("freeze_season_start"); end <- valid_date("freeze_season_end")
        if (is.na(start) || is.na(end) || end != as.character(date) || start > end ||
            !is.finite(number("freeze_normal_years")) ||
            number("freeze_normal_years") < config$minimum_freeze_normal_years) next
      }
      values <- series(variable, start, end)
      value <- number(metric)
      if (is.null(values) || !is.finite(value)) next
      event_start <- event_end <- NA_character_
      observed <- normal <- sample_years <- NA_real_
      if (metric == "freeze_nights_anomaly") {
        observed <- sum(values <= 32); normal <- number("freeze_nights_normal")
        sample_years <- number("freeze_normal_years")
        if (!is.finite(normal) || normal < 0 || normal > length(values) ||
            !isTRUE(all.equal(as.numeric(observed), number("freeze_nights"))) ||
            abs(observed - normal - value) > 1e-6 ||
            abs(value) < config$minimum_freeze_departure_nights) next
        event_start <- start; event_end <- end
      } else if (metric == "longest_dry_spell") {
        run <- rle(values < 0.04)
        maximum <- if (any(run$values)) max(run$lengths[run$values]) else 0
        event_start <- valid_date("longest_dry_spell_start_date"); event_end <- valid_date("longest_dry_spell_end_date")
        if (is.na(event_start) || is.na(event_end) || value < 1 || value != maximum ||
            event_start < start || event_end > end || event_start > event_end ||
            as.integer(as.Date(event_end) - as.Date(event_start)) + 1L != value) next
        days_in_run <- as.character(seq(as.Date(event_start), as.Date(event_end), by = "day"))
        positions <- match(days_in_run, as.character(seq(as.Date(start), as.Date(end), by = "day")))
        if (anyNA(positions) || !all(values[positions] < 0.04)) next
      } else if (metric == "max_3day_pcpn") {
        if (length(values) < 3L) next
        totals <- values[-c(1, 2)] + values[-c(1, length(values))] + values[-c(length(values)-1L, length(values))]
        event_start <- valid_date("max_3day_pcpn_start_date"); event_end <- valid_date("max_3day_pcpn_end_date")
        k <- match(event_start, as.character(seq(date - period_days + 1L, date, by = "day")))
        if (is.na(k) || k > length(totals) || is.na(event_end) ||
            event_end != as.character(as.Date(event_start) + 2L) ||
            abs(value - max(totals)) > 1e-6 || abs(value - totals[k]) > 1e-6 || value <= 0) next
      } else {
        event_start <- event_end <- valid_date(paste0(metric, "_date"))
        days <- as.character(seq(date - period_days + 1L, date, by = "day"))
        k <- match(event_end, days)
        extreme <- if (metric == "coldest_night") min(values) else max(values)
        if (is.na(k) || abs(value - extreme) > 1e-6 || abs(value - values[k]) > 1e-6 || (rain && value <= 0)) next
      }
      candidates[[length(candidates) + 1L]] <- data.frame(
        fact_id = paste("station", x$uid, metric, period_id, date, sep = ":"), uid = x$uid,
        window_days = period_days,
        name = x$name, state = x$state, metric = metric, family = if (metric == "longest_dry_spell") "dryness" else if (rain) "rainfall" else "temperature",
        value = value, units = if (metric == "longest_dry_spell") "days" else if (rain) "inch" else if (metric == "freeze_nights_anomaly") "nights departure" else "degreeF",
        period_start = start, period_end = end, event_start = event_start, event_end = event_end,
        observed = observed, normal = normal, sample_years = sample_years,
        reference = if (metric == "freeze_nights_anomaly") "1991-2020 matching cool-season-to-date mean" else paste0("Selected ", period_days, "-day window; no historical rarity claim"),
        caution_codes = ifelse(is.na(screen$caution_codes), "", screen$caution_codes),
        source_path = detail_path, source_md5 = unname(tools::md5sum(detail_path)),
        link = "pages/station-conditions.html", stringsAsFactors = FALSE)
    }
  }
  if (!length(candidates)) return(empty)
  candidates <- do.call(rbind, candidates)
  order_ids <- unlist(config$station_metric_order[[synopsis_season(date, config)$id]])
  candidates <- candidates[candidates$metric %in% order_ids, , drop = FALSE]
  priority <- match(candidates$metric, order_ids)
  # Order within each metric only; never compare inches, degrees and nights numerically.
  magnitude <- ifelse(candidates$metric == "coldest_night", candidates$value,
    ifelse(candidates$metric == "freeze_nights_anomaly", -abs(candidates$value), -candidates$value))
  candidates <- candidates[order(priority, magnitude, candidates$uid), , drop = FALSE]
  selected <- candidates[FALSE, , drop = FALSE]
  for (i in seq_len(min(config$maximum_station_examples, 2L))) {
    pool <- candidates[!candidates$uid %in% selected$uid, , drop = FALSE]
    if (!nrow(pool)) break
    if (nrow(selected)) {
      # Prefer a different metric family, then another state, without declaring network records.
      if (any(!pool$family %in% selected$family)) pool <- pool[!pool$family %in% selected$family, , drop = FALSE]
      if (any(!pool$state %in% selected$state)) pool <- pool[!pool$state %in% selected$state, , drop = FALSE]
    }
    selected <- rbind(selected, pool[1L, , drop = FALSE])
  }
  list(status = if (nrow(candidates)) "AVAILABLE_CACHED" else "NO_ELIGIBLE_CANDIDATES",
    candidates = candidates, selected = selected,
    note = "Examples from eligible fixed stations, chosen for seasonal relevance and complementary geography/metrics; not network or all-time records.")
}

synopsis_station_inventory <- function(root, date, config) {
  path <- file.path(root, "site/stations/station-explorer-data.csv")
  empty <- list(status = "UNAVAILABLE", note = "Station summary missing or incompatible.",
    path = path, examples = data.frame(), rows = 0L, matching_rows = 0L)
  if (!file.exists(path)) return(empty)
  x <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  required <- c("uid", "name", "state", "role", "period", "as_of", "period_start", "pcpn_status",
    "pcpn_missing_days", "pcpn_flagged_days", "max_daily_pcpn", "max_daily_pcpn_date")
  if (is.null(x) || !all(required %in% names(x))) return(empty)
  matching <- x$period == "30day" & x$as_of == as.character(date) &
    x$period_start == as.character(date - 29L)
  eligible <- matching & x$role == "fixed" & x$pcpn_status == "AVAILABLE" &
    x$pcpn_missing_days == 0 & x$pcpn_flagged_days == 0 &
    is.finite(x$max_daily_pcpn) & x$max_daily_pcpn >= 0 &
    !is.na(x$max_daily_pcpn_date) & x$max_daily_pcpn_date >= as.character(date - 29L) &
    x$max_daily_pcpn_date <= as.character(date)
  good <- x[which(eligible), required, drop = FALSE]
  good <- good[!duplicated(good$uid), , drop = FALSE]
  good <- good[order(-good$max_daily_pcpn, good$uid), , drop = FALSE]
  examples <- utils::head(good, config$maximum_station_examples)
  list(status = if (nrow(good)) "AVAILABLE_CACHED" else "NO_ELIGIBLE_MATCHING_ROWS",
    note = "Raw rainfall inventory among eligible fixed stations. Final draft selection also requires the separate historical-window and publication checks; these are not regional/all-calendar-day records.",
    path = path, source_md5 = unname(tools::md5sum(path)), rows = nrow(x),
    available_as_of_dates = sort(unique(x$as_of)),
    matching_rows = sum(matching, na.rm = TRUE), eligible_stations = nrow(good), examples = examples,
    link = "pages/station-conditions.html")
}

synopsis_snow_inventory <- function(root, date) {
  path <- file.path(root, "data/processed/snodas/manifest.csv")
  active <- format(date, "%m") %in% c("10", "11", "12", "01", "02", "03", "04", "05")
  result <- list(status = if (active) "UNAVAILABLE" else "INACTIVE_SEASON",
    active = active, snapshot_date = as.character(date), paired_date = NA_character_,
    seven_day_prior_verified = FALSE, regional_metrics = "DEFERRED_MASK_DEFINITION",
    note = "Regional mountain/reference denominators and snow thresholds need agreement; no snow-cover or percent-of-median claims are generated.",
    link = "pages/current-snow.html")
  if (!active || !file.exists(path)) return(result)
  x <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(x) || !all(c("date", "variable", "path", "md5", "units") %in% names(x))) return(result)
  verified <- function(stamp) {
    pair <- x[x$date == as.character(stamp) & x$variable %in% c("swe", "depth"), , drop = FALSE]
    if (nrow(pair) != 2L || !setequal(pair$variable, c("swe", "depth")) || anyNA(pair$md5) ||
        !all(pair$units == "inch")) return(FALSE)
    files <- file.path(root, pair$path)
    all(file.exists(files)) && all(unname(tools::md5sum(files)) == pair$md5)
  }
  if (verified(date)) {
    result$status <- "PAIRED_FILES_CHECKSUM_VERIFIED"
    result$paired_date <- as.character(date)
    result$seven_day_prior_verified <- verified(date - 7L)
  }
  result
}

synopsis_report <- function(evidence) {
  facts <- evidence$facts
  fmt <- function(x) ifelse(is.finite(x), format(round(x, 2), trim = TRUE), "unavailable")
  rows <- vapply(seq_len(nrow(facts)), function(i) {
    f <- facts[i, ]
    paste0("| ", f$region, " | ", f$product, " / ", f$metric, " | ", fmt(f$value),
      " | ", f$units, " | ", if (is.finite(f$threshold)) f$threshold else "—",
      " | ", f$period_start, " to ", f$period_end, " | ", fmt(100 * f$coverage), " | ", f$reference, " | ", f$status, " |")
  }, character(1))
  c("# Conditions synopsis: local evidence inventory", "",
    paste0("Snapshot: **", evidence$snapshot_date, "**; generated: ", evidence$generated_utc, "."),
    paste0("Snapshot age: ", evidence$snapshot_age_days, " days relative to the run date. Editorial period: **", evidence$season$id, "**."),
    evidence$season$emphasis, "",
    "Local cached evidence only. No downloads, API calls, published-state changes or site updates.",
    "AVAILABLE_CACHED means local structural/range/coverage checks passed; it does not establish source freshness or independently audit the historical reference build.",
    "Reference labels follow project configuration (see evidence JSON); inspect provenance before publication.", "",
    "## Recent seven-day evidence", "",
    paste0("Status: ", evidence$recent$status, "; ", if (nrow(evidence$recent$facts)) sum(evidence$recent$facts$status == "AVAILABLE_CACHED") else 0,
      " regional facts and ", nrow(evidence$recent$days), " daily regional rows. Cached-input summaries cover ",
      as.character(as.Date(evidence$snapshot_date) - 6L), " through ", evidence$snapshot_date, "."),
    "See recent-facts.csv and recent-days.csv. Seven-day station inventory is separate from the 30-day seasonal inventory; the draft selects across them.",
    evidence$recent$note, "",
    "## Regional grid facts", "",
    "Area fractions use valid region area; coverage reports valid/total region area. Percentile cutoffs are strict (< or >); rainfall cutoff uses >= with float-storage tolerance.", "",
    "| Region | Metric | Value | Units | Cutoff | Period | Coverage % | Reference | Status |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- |", rows, "",
    "## Station and snow availability", "",
    paste0("Stations: ", evidence$stations$status, "; ", evidence$stations$matching_rows, " matching 30-day rows."),
    evidence$stations$note,
    paste0("Station cache dates: ", paste(evidence$stations$available_as_of_dates, collapse = ", "), "."),
    "The following 30-day inventory examples also require daily-detail and publication-screen checks. Final draft highlights use seven-day extremes and seasonal context:", "",
    if (nrow(evidence$station_extremes$selected)) vapply(seq_len(nrow(evidence$station_extremes$selected)), function(i) {
      x <- evidence$station_extremes$selected[i, ]
      paste0("- ", x$name, " (", x$state, "): ", x$metric, " = ", fmt(x$value), " ", x$units,
        "; event ", x$event_start, " to ", x$event_end, "; ", x$reference, ".")
    }, character(1)) else "No fully screened station extreme for this snapshot.", "",
    paste0("Snow: ", evidence$snow$status, "; exact seven-day prior pair verified: ", evidence$snow$seven_day_prior_verified, "."),
    evidence$snow$note, "",
    "## Evidence destinations", "",
    paste0("- [", unique(facts$product), "](https://cales.arizona.edu/climate/watch/", unique(facts$link), ")"),
    "- [Station Conditions](https://cales.arizona.edu/climate/watch/pages/station-conditions.html)",
    "- [Current Snow](https://cales.arizona.edu/climate/watch/pages/current-snow.html)", "",
    "These public destinations do not select a historical date/station. Current product pages may show a newer date than this local snapshot. Site-root-relative destinations are retained in the evidence file.", "",
    "## Remaining seasonal adapters", "",
    "| Season | Available basis | Remaining work |",
    "| --- | --- | --- |",
    "| All seasons | Regional facts, screened station peaks and complete matching-window historical context | Additional hot/warm-night indices and event aggregation |",
    "| Winter | Snow pair/checksum inventory | Mountain/reference masks, supported storage/deficit and change summaries |",
    "| Spring | Same core facts and active-season snow inventory | Snow relevance taper and late-storm cases |",
    "| Early summer | Core facts; current snow explicitly inactive | Optional dated closeout link; no stale current-snow inference |",
    "| Summer | Core facts and local station rain examples | Dry intervals, heat and matching seasonal totals only from supported caches |",
    "| Fall | Core facts, supported freeze-night departures and early-season snow inventory | First-freeze-date adapter and additional seasonal phrasing |", "",
    paste0("Regional cache reused: ", evidence$regional_cache_reused, "; evidence processing: ", round(evidence$elapsed_seconds, 2), " seconds (before diagnostic output writes)."), "",
    "No previous-published snapshot is read or advanced. Published-update change claims and production integration remain subsequent increments; the draft script has separate local-preview history and contextual prose.")
}

build_conditions_synopsis_evidence <- function(snapshot_date = NULL, root = ".",
    output_dir = file.path(root, "data/diagnostics/conditions-synopsis"), today = Sys.Date(),
    config_path = file.path(root, "config/conditions-synopsis.yml")) {
  started <- proc.time()[["elapsed"]]
  config <- synopsis_config(config_path)
  date <- if (is.null(snapshot_date)) synopsis_latest_date(root, today) else synopsis_date(snapshot_date)
  if (date > today) stop("Snapshot cannot be later than the run date.")
  specs <- synopsis_grid_specs(root, date)
  # Baselines come from the same project configuration used by the grid builders.
  project_config <- new.env(parent = baseenv())
  sys.source(file.path(root, "R/config.R"), envir = project_config)
  prism <- project_config$swc_prism
  normal <- paste(format(prism$normal_start, "%Y"), format(prism$normal_end, "%Y"), sep = "-")
  percentile <- paste(format(prism$percentile_start, "%Y"), format(prism$percentile_end, "%Y"), sep = "-")
  specs$reference[specs$id == "pcpn_percentile_30day"] <- paste0(percentile, "; centered ", prism$centered_window_days, "-day reference for 30-day totals")
  specs$reference[specs$id == "pcpn_water_year_percentile"] <- paste0(percentile, "; matching water-year-to-date totals (exact calendar endpoint)")
  specs$reference[specs$type == "temperature"] <- normal
  inputs <- c(specs$path, config_path, file.path(root, "R/config.R"),
    file.path(root, "site/stations/station-explorer-data.csv"), file.path(root, "data/processed/snodas/manifest.csv"))
  signature <- digest::digest(list(version = 3L, date = date, config = config,
    paths = inputs, md5 = unname(tools::md5sum(inputs[file.exists(inputs)])),
    terra = as.character(utils::packageVersion("terra")), maps = as.character(utils::packageVersion("maps"))))
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  cache_path <- file.path(output_dir, "evidence-cache.rds")
  cache <- if (file.exists(cache_path)) tryCatch(readRDS(cache_path), error = function(e) NULL) else NULL
  reused <- identical(cache$signature, signature)
  if (reused) facts <- cache$facts else {
    facts <- synopsis_grid_facts(specs, config)
    saveRDS(list(signature = signature, facts = facts), cache_path)
  }
  # Recheck station eligibility and snow file checksums even on a regional-cache hit.
  evidence <- list(schema_version = 4L, mode = "local_inventory_only", snapshot_date = as.character(date),
    generated_utc = format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC", tz = "UTC"),
    snapshot_age_days = as.integer(today - date), selection = if (is.null(snapshot_date)) "latest shared five-grid cached date" else "explicit snapshot",
    season = synopsis_season(date, config), signature = signature, configuration = config,
    facts = facts, stations = synopsis_station_inventory(root, date, config), snow = synopsis_snow_inventory(root, date),
    station_extremes = synopsis_station_extremes(root, date, config),
    station_week = synopsis_station_extremes(root, date, config, period_days = 7L),
    recent = synopsis_recent_evidence(root, date, config, output_dir),
    previous_published_snapshot = NULL, regional_cache_reused = reused)
  module <- file.path(root, "R/conditions-synopsis-station-context.R")
  if (file.exists(module) && config$maximum_station_examples > 0L) {
    context <- new.env(parent = environment())
    sys.source(module, envir = context)
    for (packet in c("station_extremes", "station_week")) evidence[[packet]] <- context$synopsis_add_station_context(
      evidence[[packet]], root, date, config, file.path(output_dir, "station-context"))
  }
  module <- file.path(root, "R/conditions-synopsis-regional-highlights.R")
  if (file.exists(module)) {
    context <- new.env(parent = environment()); sys.source(module, envir = context)
    evidence$regional_highlights <- list(normal_reference = normal, centered_window_days = prism$centered_window_days,
      grids = context$synopsis_highlight_grid_inventory(root, date, config),
      stations = context$synopsis_station_network_counts(root, date, config))
    utils::write.csv(evidence$regional_highlights$grids, file.path(output_dir, "regional-highlight-facts.csv"), row.names = FALSE, na = "")
    utils::write.csv(evidence$regional_highlights$stations$facts, file.path(output_dir, "station-network-counts.csv"), row.names = FALSE, na = "")
    utils::write.csv(evidence$regional_highlights$stations$members, file.path(output_dir, "station-network-members.csv"), row.names = FALSE, na = "")
  }
  evidence$elapsed_seconds <- unname(proc.time()[["elapsed"]] - started)
  jsonlite::write_json(evidence, file.path(output_dir, "evidence.json"), dataframe = "rows", auto_unbox = TRUE, na = "null", pretty = TRUE, digits = 12)
  utils::write.csv(facts, file.path(output_dir, "facts.csv"), row.names = FALSE, na = "")
  utils::write.csv(evidence$station_extremes$selected, file.path(output_dir, "station-30day-examples.csv"), row.names = FALSE, na = "")
  utils::write.csv(evidence$station_extremes$candidates, file.path(output_dir, "station-30day-candidates.csv"), row.names = FALSE, na = "")
  utils::write.csv(evidence$station_week$candidates, file.path(output_dir, "station-week-candidates.csv"), row.names = FALSE, na = "")
  utils::write.csv(evidence$recent$facts, file.path(output_dir, "recent-facts.csv"), row.names = FALSE, na = "")
  utils::write.csv(evidence$recent$days, file.path(output_dir, "recent-days.csv"), row.names = FALSE, na = "")
  writeLines(synopsis_report(evidence), file.path(output_dir, "report.md"), useBytes = TRUE)
  message("Local synopsis evidence: ", date, "; ", sum(facts$status == "AVAILABLE_CACHED"), "/", nrow(facts),
    " regional facts available; cache ", if (reused) "reused" else "built", "; ", round(evidence$elapsed_seconds, 2), "s.")
  message("Report: ", file.path(output_dir, "report.md"), ". No downloads or publication.")
  invisible(evidence)
}
