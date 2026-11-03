# Cumulative precipitation calculations shared by the pilot and station page.
acis_cumulative_water_year <- function(date) {
  as.integer(format(as.Date(date), "%Y")) + (as.integer(format(as.Date(date), "%m")) >= 10L)
}

acis_precipitation_water_year <- function(daily, water_year, through = NULL) {
  required <- c("date", "variable", "numeric_value", "observed", "flag", "trace", "accumulated")
  if (!all(required %in% names(daily)) || !inherits(daily$date, "Date") ||
      length(water_year) != 1L || !is.finite(water_year) || water_year != as.integer(water_year)) {
    stop("Invalid cumulative precipitation inputs.")
  }
  start <- as.Date(sprintf("%d-10-01", water_year - 1L))
  end <- as.Date(sprintf("%d-09-30", water_year))
  through <- as.Date(if (is.null(through)) end else through)
  if (length(through) != 1L || is.na(through) || through < start || through > end) {
    stop("Cumulative cutoff must fall within the requested water year.")
  }
  dates <- seq(start, end, by = "day")
  rows <- daily[daily$variable == "pcpn" & daily$date >= start & daily$date <= end, , drop = FALSE]
  if (anyDuplicated(rows$date)) stop("Duplicate precipitation dates.")
  rows <- rows[match(dates, rows$date), , drop = FALSE]
  value <- rows$numeric_value
  missing <- is.na(rows$observed) | !rows$observed | !is.finite(value)
  flagged <- (!is.na(rows$flag) & !rows$flag %in% c("", "T")) |
    (!is.na(rows$accumulated) & rows$accumulated) |
    (!is.na(value) & (value < 0 | value > 100))
  trace <- (!is.na(rows$flag) & rows$flag == "T") | (!is.na(rows$trace) & rows$trace)
  future <- dates > through
  status <- ifelse(future, "FUTURE", ifelse(missing, "MISSING",
    ifelse(flagged, "FLAGGED", ifelse(trace, "TRACE", "AVAILABLE"))))
  good <- status %in% c("AVAILABLE", "TRACE")
  value[good & trace] <- 0
  subtotal <- cumsum(ifelse(good, value, 0))
  missing_days <- cumsum(status == "MISSING")
  flagged_days <- cumsum(status == "FLAGGED")
  complete <- missing_days + flagged_days == 0L
  data.frame(date = dates, month_day = format(dates, "%m-%d"), status = status,
    daily_inches = ifelse(good, value, NA_real_),
    cumulative_inches = ifelse(!future & complete, subtotal, NA_real_),
    observed_subtotal = ifelse(!future, subtotal, NA_real_),
    missing_days = ifelse(future, NA_integer_, missing_days),
    flagged_days = ifelse(future, NA_integer_, flagged_days), stringsAsFactors = FALSE)
}

acis_station_cumulative_payload <- function(station, cache, as_of = cache$as_of,
    baseline_water_years = 1991:2020, min_years = 20L, historical = NULL,
    allow_stale = FALSE) {
  as_of <- as.Date(as_of)
  if (is.null(cache) || length(as_of) != 1L || is.na(as_of) || (!allow_stale && as_of > cache$as_of) ||
      as.integer(station$uid) != as.integer(cache$uid)) stop("Invalid or stale cumulative cache.")
  water_year <- acis_cumulative_water_year(as_of)
  if (!length(baseline_water_years) || anyNA(baseline_water_years) ||
      anyDuplicated(baseline_water_years) || any(baseline_water_years >= water_year) ||
      length(min_years) != 1L || !is.finite(min_years) || min_years < 1L ||
      min_years != as.integer(min_years)) stop("Invalid cumulative baseline settings.")
  # Align by month/day on a 365-position calendar. Leap-day rainfall is included
  # in March 1 and all subsequent cumulative totals, never silently discarded.
  month_days <- format(seq(as.Date("2000-10-01"), as.Date("2001-09-30"), by = "day"), "%m-%d")
  current <- acis_precipitation_water_year(cache$daily, water_year, as_of)
  previous <- acis_precipitation_water_year(cache$daily, water_year - 1L)
  baseline <- if (is.null(historical)) lapply(baseline_water_years,
    function(year) acis_precipitation_water_year(cache$daily, year)) else NULL
  eligible <- if (is.null(historical)) vapply(baseline,
    function(x) all(is.finite(x$cumulative_inches)), logical(1)) else
    as.character(baseline_water_years) %in% names(historical$curves)
  aligned <- function(x, column) x[[column]][match(month_days, x$month_day)]
  normal <- rep(NA_real_, length(month_days))
  lower <- upper <- normal
  if (sum(eligible) >= min_years) {
    samples <- if (is.null(historical)) vapply(baseline[eligible], aligned,
      numeric(365), column = "cumulative_inches") else vapply(
        historical$curves[as.character(baseline_water_years[eligible])],
        function(x) x$values, numeric(365))
    normal <- rowMeans(samples)
    lower <- apply(samples, 1L, stats::quantile, probs = 0.25, type = 8L, names = FALSE)
    upper <- apply(samples, 1L, stats::quantile, probs = 0.75, type = 8L, names = FALSE)
  }
  current_index <- match(month_days, current$month_day)
  current_day <- current[current_index, , drop = FALSE]
  at_cutoff <- current[current$date == as_of, , drop = FALSE]
  list(schema_version = 1L, uid = as.integer(station$uid), sid = station$sid,
    name = station$name, state = station$state, role = station$role,
    as_of = as.character(as_of), cache_as_of = as.character(cache$as_of),
    water_year = water_year, previous_water_year = water_year - 1L,
    baseline = list(water_years = baseline_water_years, eligible_years = baseline_water_years[eligible],
      sample_years = sum(eligible), minimum_years = min_years,
      available = sum(eligible) >= min_years, method = "Mean of complete water-year cumulative curves",
      band_probabilities = c(0.25, 0.75), quantile_type = 8L),
    current = list(total = at_cutoff$cumulative_inches, observed_subtotal = at_cutoff$observed_subtotal,
      missing_days = at_cutoff$missing_days, flagged_days = at_cutoff$flagged_days),
    points = data.frame(date = as.character(current_day$date), month_day = month_days,
      current = round(current_day$cumulative_inches, 4),
      previous = round(aligned(previous, "cumulative_inches"), 4), normal = round(normal, 4),
      lower = round(lower, 4), upper = round(upper, 4),
      subtotal = round(current_day$observed_subtotal, 4), status = current_day$status,
      missing_days = current_day$missing_days, flagged_days = current_day$flagged_days,
      previous_missing = aligned(previous, "missing_days"),
      previous_flagged = aligned(previous, "flagged_days")),
    baseline_audit = data.frame(water_year = baseline_water_years, eligible = eligible,
      missing_days = if (is.null(historical)) vapply(baseline, function(x) sum(x$status == "MISSING"), integer(1)) else
        historical$audit$missing_days[match(baseline_water_years, historical$audit$water_year)],
      flagged_days = if (is.null(historical)) vapply(baseline, function(x) sum(x$status == "FLAGGED"), integer(1)) else
        historical$audit$flagged_days[match(baseline_water_years, historical$audit$water_year)]))
}

acis_station_cumulative_history <- function(station, cache, water_year) {
  daily <- cache$daily[cache$daily$variable == "pcpn", , drop = FALSE]
  groups <- split(daily, acis_cumulative_water_year(daily$date))
  years <- sort(as.integer(names(groups)), decreasing = TRUE)
  years <- years[years < water_year]
  month_days <- format(seq(as.Date("2000-10-01"), as.Date("2001-09-30"), by = "day"), "%m-%d")
  curves <- list(); audit <- list()
  for (year in years) {
    curve <- acis_precipitation_water_year(groups[[as.character(year)]], year)
    eligible <- all(is.finite(curve$cumulative_inches))
    audit[[as.character(year)]] <- data.frame(water_year = year, eligible = eligible,
      missing_days = sum(curve$status == "MISSING"), flagged_days = sum(curve$status == "FLAGGED"))
    if (eligible) curves[[as.character(year)]] <- list(schema_version = 1L,
      uid = as.integer(station$uid), water_year = year, calendar = "month-day-365",
      annual_total = round(tail(curve$cumulative_inches, 1L), 4),
      values = round(curve$cumulative_inches[match(month_days, curve$month_day)], 4))
  }
  catalog <- lapply(curves, function(x) list(water_year = x$water_year,
    annual_total = x$annual_total, file = sprintf("history/%d/%d.json", x$uid, x$water_year)))
  list(catalog = unname(catalog), curves = curves,
       audit = if (length(audit)) do.call(rbind, audit) else data.frame(
         water_year = integer(), eligible = logical(), missing_days = integer(), flagged_days = integer()))
}

acis_cumulative_record_status <- function(value, low, high, tolerance = 1e-6) {
  if (!all(is.finite(c(value, low, high)))) return("UNAVAILABLE")
  if (value > high + tolerance) return("NEW_HIGH")
  if (value < low - tolerance) return("NEW_LOW")
  if (abs(value-high) <= tolerance && abs(value-low) <= tolerance) return("TIED_BOTH")
  if (abs(value-high) <= tolerance) return("TIED_HIGH")
  if (abs(value-low) <= tolerance) return("TIED_LOW")
  "WITHIN_RANGE"
}

acis_cumulative_history_context <- function(payload, history, min_history_years = 20L,
    reuse_reference = FALSE) {
  if (length(min_history_years) != 1L || !is.finite(min_history_years) ||
      min_history_years < 1L || min_history_years != as.integer(min_history_years)) stop("Invalid history support threshold.")
  n <- length(history$curves)
  points <- payload$points
  if (!reuse_reference) {
    points$record_low <- points$record_high <- rep(NA_real_, nrow(points))
    points$low_years <- points$high_years <- rep("", nrow(points))
  }
  supported <- n >= min_history_years
  tolerance <- 1e-6
  years <- unname(vapply(history$curves, function(x) as.integer(x$water_year), integer(1)))
  if (supported) {
    samples <- vapply(history$curves, function(x) x$values, numeric(365))
    if (!reuse_reference) {
      points$record_low <- apply(samples, 1L, min)
      points$record_high <- apply(samples, 1L, max)
      for (i in seq_len(nrow(points))) {
        points$low_years[i] <- paste(sort(years[abs(samples[i, ]-points$record_low[i]) <= tolerance], decreasing = TRUE), collapse = ",")
        points$high_years[i] <- paste(sort(years[abs(samples[i, ]-points$record_high[i]) <= tolerance], decreasing = TRUE), collapse = ",")
      }
    }
  }
  points$record_status <- vapply(seq_len(nrow(points)), function(i)
    acis_cumulative_record_status(points$current[i],points$record_low[i],points$record_high[i]), character(1))
  cutoff <- max(which(points$date <= payload$as_of))
  match <- list(available = FALSE, water_year = NA_integer_, rmse_inches = NA_real_,
    tied_years = integer(), days_compared = 0L, early_season = TRUE, cutoff_date = points$date[cutoff],
    method = "RMSE of calendar-matched cumulative totals, October 1 through cutoff",
    note = "Too few complete historical water years.")
  if (supported && is.finite(payload$current$total)) {
    positions <- which(points$date <= payload$as_of & is.finite(points$current))
    if (length(positions)) {
      errors <- sqrt(colMeans((samples[positions, , drop = FALSE]-points$current[positions])^2))
      best <- min(errors)
      tied <- sort(years[abs(errors-best) <= tolerance], decreasing = TRUE)
      match <- list(available = TRUE, water_year = tied[1L], rmse_inches = unname(best),
        tied_years = unname(tied), days_compared = length(positions), early_season = length(positions) < 30L,
        cutoff_date = points$date[max(positions)],
        method = match$method, note = "Most recent tied year shown; descriptive match, not a forecast.")
    }
  } else if (supported) match$note <- "Current accumulation is incomplete; closest progression withheld."
  payload$points <- points
  payload$historical_context <- list(available = supported, sample_years = n,
    minimum_years = min_history_years, first_year = if (n) min(years) else NA_integer_,
    last_year = if (n) max(years) else NA_integer_, tie_tolerance_inches = tolerance,
    cutoff_date = points$date[cutoff], current_status = points$record_status[cutoff])
  payload$closest_match <- match
  payload
}

acis_cumulative_refresh_current <- function(reference, cache, as_of, history) {
  curve <- acis_precipitation_water_year(cache$daily, reference$water_year, as_of)
  day <- curve[match(reference$points$month_day, curve$month_day), , drop = FALSE]
  cutoff <- curve[curve$date == as.Date(as_of), , drop = FALSE]
  reference$as_of <- as.character(as_of)
  reference$cache_as_of <- as.character(cache$as_of)
  reference$current <- list(total = cutoff$cumulative_inches, observed_subtotal = cutoff$observed_subtotal,
    missing_days = cutoff$missing_days, flagged_days = cutoff$flagged_days)
  for (field in c("status", "missing_days", "flagged_days")) reference$points[[field]] <- day[[field]]
  reference$points$date <- as.character(day$date)
  reference$points$current <- round(day$cumulative_inches, 4)
  reference$points$subtotal <- round(day$observed_subtotal, 4)
  acis_cumulative_history_context(reference, history, reuse_reference = TRUE)
}

acis_cumulative_write_json <- function(value, path) {
  serialized <- as.character(jsonlite::toJSON(value, auto_unbox = TRUE,
    dataframe = "rows", na = "null", digits = NA, pretty = FALSE))
  if (file.exists(path) && identical(paste(readLines(path, warn = FALSE), collapse = "\n"), serialized)) {
    return(invisible(FALSE))
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(serialized, path, useBytes = TRUE)
  invisible(TRUE)
}

# Historical screening is content-addressed independently of the daily refresh.
# A revision to any past precipitation report or an October rollover invalidates it.
write_acis_station_cumulative_site <- function(stations, caches, as_of, output_dir,
    history_cache_dir = file.path("data", "processed", "acis-stations", "cumulative-history"),
    asset_dir = file.path("scripts", "station-cumulative-assets")) {
  stopifnot(length(caches) == nrow(stations), !anyDuplicated(stations$uid))
  started <- proc.time()[["elapsed"]]
  as_of <- as.Date(as_of)
  wy <- acis_cumulative_water_year(as_of)
  directory <- file.path(output_dir, "cumulative")
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  dir.create(history_cache_dir, recursive = TRUE, showWarnings = FALSE)
  reused <- 0L
  entries <- lapply(seq_len(nrow(stations)), function(i) {
    station <- stations[i, , drop = FALSE]; uid <- as.integer(station$uid)
    cache <- caches[[i]]
    if (is.null(cache)) {
      payload <- list(schema_version = 1L, uid = uid, as_of = as.character(as_of),
        available = FALSE, note = "No daily station cache is available for cumulative precipitation.")
    } else {
      # Never let reports beyond a cache's verified cutoff become observations.
      cache$daily <- cache$daily[cache$daily$date <= cache$as_of, , drop = FALSE]
      past <- cache$daily[cache$daily$variable == "pcpn" &
        cache$daily$date < as.Date(sprintf("%d-10-01", wy - 1L)), , drop = FALSE]
      past <- past[order(past$date), c("date", "variable", "numeric_value", "observed", "flag", "trace", "accumulated")]
      rownames(past) <- NULL
      key <- digest::digest(list(version = 2L, uid = uid, water_year = wy, daily = past,
        station = station), algo = "sha256")
      cache_path <- file.path(history_cache_dir, paste0(uid, ".rds"))
      saved <- if (file.exists(cache_path)) tryCatch(readRDS(cache_path), error = function(e) NULL) else NULL
      if (!is.null(saved) && identical(saved$key, key) && !is.null(saved$reference)) {
        history <- saved$history; reused <<- reused + 1L
        payload <- acis_cumulative_refresh_current(saved$reference, cache, as_of, history)
      } else {
        history <- acis_station_cumulative_history(station, cache, wy)
        payload <- acis_station_cumulative_payload(station, cache, as_of,
          historical = history, allow_stale = TRUE)
        payload <- acis_cumulative_history_context(payload, history)
        saveRDS(list(key = key, history = history, reference = payload), cache_path)
      }
      payload$comparison_years <- history$catalog
      payload$available <- TRUE
      output_key_path <- file.path(directory, "history", as.character(uid), "source-key.txt")
      output_current <- file.exists(output_key_path) &&
        identical(readLines(output_key_path, warn = FALSE), key)
      for (curve in history$curves) {
        path <- file.path(directory, sprintf("history/%d/%d.json", uid, curve$water_year))
        if (!output_current || !file.exists(path) || file.info(path)$size == 0)
          acis_cumulative_write_json(curve, path)
      }
      dir.create(dirname(output_key_path), recursive = TRUE, showWarnings = FALSE)
      if (!output_current) writeLines(key, output_key_path)
    }
    acis_cumulative_write_json(payload, file.path(directory, paste0(uid, ".json")))
    list(uid = uid, name = station$name, state = station$state, file = paste0(uid, ".json"))
  })
  acis_cumulative_write_json(list(schema_version = 1L, as_of = as.character(as_of),
    stations = entries), file.path(directory, "stations.json"))
  for (asset in c("index.html", "cumulative.js", "cumulative.css")) {
    if (!file.copy(file.path(asset_dir, asset), directory, overwrite = TRUE)) stop("Cumulative asset copy failed.")
  }
  message(sprintf("Station cumulative plots: %d stations; %d historical caches reused; %.1fs; no requests.",
    nrow(stations), reused, proc.time()[["elapsed"]] - started))
  invisible(list(directory = directory, stations = nrow(stations), historical_reused = reused))
}

# Called both before atomic station staging and before S3 publication.
validate_acis_station_cumulative_site <- function(directory, uids, as_of) {
  required <- file.path(directory, c("index.html", "cumulative.js", "cumulative.css", "stations.json"))
  if (!all(file.exists(required)) || any(file.info(required)$size <= 0)) stop("Cumulative station resources are missing.")
  catalog <- jsonlite::read_json(file.path(directory, "stations.json"), simplifyVector = FALSE)
  ids <- vapply(catalog$stations, function(x) as.integer(x$uid), integer(1))
  if (catalog$schema_version != 1L || !identical(catalog$as_of, as.character(as_of)) ||
      anyDuplicated(ids) || !setequal(ids, as.integer(uids))) stop("Cumulative station catalog does not match station data.")
  if (!all(vapply(catalog$stations, function(x)
      identical(x$file, paste0(x$uid, ".json")), logical(1)))) stop("Invalid cumulative station catalog paths.")
  for (uid in ids) {
    path <- file.path(directory, paste0(uid, ".json"))
    if (!file.exists(path)) stop("Cumulative station payload is missing.")
    payload <- jsonlite::read_json(path)
    if (payload$schema_version != 1L || payload$uid != uid || payload$as_of != as.character(as_of)) stop("Cumulative station payload has the wrong identity or date.")
    if (isTRUE(payload$available)) {
      if (length(payload$points) != 365L) stop("Cumulative station curve is incomplete.")
      for (year in payload$comparison_years) {
        expected <- sprintf("history/%d/%d.json", uid, year$water_year)
        path <- file.path(directory, expected)
        if (!identical(year$file, expected) || !file.exists(path) || file.info(path)$size == 0)
          stop("Cumulative comparison curve is missing or invalid.")
      }
    }
  }
  invisible(TRUE)
}

build_acis_station_cumulative_pilot <- function(
    uids = c(29687L, 1403L, 19376L), as_of = NULL,
    stations = acis_reference_station_table(),
    cache_dir = file.path("data", "processed", "acis-stations", "reference-network", "daily"),
    output_dir = file.path("data", "diagnostics", "station-cumulative-pilot")) {
  started <- proc.time()[["elapsed"]]
  if (anyDuplicated(uids) || !length(uids) || anyNA(match(uids, stations$uid))) stop("Unknown or duplicate pilot stations.")
  stations <- stations[match(uids, stations$uid), , drop = FALSE]
  caches <- lapply(uids, function(uid) acis_station_read_daily_cache(acis_station_daily_cache_path(uid, cache_dir), uid))
  if (any(vapply(caches, is.null, logical(1)))) stop("Pilot requires existing daily caches; no downloads are performed.")
  if (is.null(as_of)) as_of <- min(as.Date(vapply(caches, function(x) as.character(x$as_of), character(1))))
  payloads <- lapply(seq_along(uids), function(i) acis_station_cumulative_payload(stations[i, ], caches[[i]], as_of))
  histories <- lapply(seq_along(uids), function(i) acis_station_cumulative_history(
    stations[i, ], caches[[i]], payloads[[i]]$water_year))
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_along(payloads)) {
    payloads[[i]] <- acis_cumulative_history_context(payloads[[i]], histories[[i]])
    payloads[[i]]$comparison_years <- histories[[i]]$catalog
    acis_cumulative_write_json(payloads[[i]], file.path(output_dir, paste0(uids[[i]], ".json")))
    for (curve in histories[[i]]$curves) acis_cumulative_write_json(curve,
      file.path(output_dir, sprintf("history/%d/%d.json", curve$uid, curve$water_year)))
  }
  catalog <- list(schema_version = 1L, as_of = as.character(as_of), stations = lapply(payloads, function(x)
    list(uid = x$uid, name = x$name, state = x$state, file = paste0(x$uid, ".json"))))
  jsonlite::write_json(catalog, file.path(output_dir, "stations.json"), auto_unbox = TRUE, pretty = TRUE)
  audits <- do.call(rbind, lapply(payloads, function(x) cbind(uid = x$uid, x$baseline_audit)))
  utils::write.csv(audits, file.path(output_dir, "baseline-audit.csv"), row.names = FALSE)
  historical_audit <- do.call(rbind, lapply(seq_along(uids), function(i) {
    if (nrow(histories[[i]]$audit)) cbind(uid = uids[[i]], histories[[i]]$audit) else NULL
  }))
  utils::write.csv(historical_audit, file.path(output_dir, "history-audit.csv"), row.names = FALSE)
  for (asset in c("index.html", "cumulative.js", "cumulative.css")) {
    if (!file.copy(file.path("scripts", "station-cumulative-assets", asset),
                   file.path(output_dir, asset), overwrite = TRUE)) stop("Pilot asset copy failed.")
  }
  summary <- data.frame(uid = uids, name = stations$name, as_of = as.character(as_of),
    baseline_years = vapply(payloads, function(x) x$baseline$sample_years, integer(1)),
    comparison_years = vapply(histories, function(x) length(x$catalog), integer(1)),
    current_missing = vapply(payloads, function(x) x$current$missing_days, integer(1)),
    current_flagged = vapply(payloads, function(x) x$current$flagged_days, integer(1)),
    current_total = vapply(payloads, function(x) x$current$total, numeric(1)))
  utils::write.csv(summary, file.path(output_dir, "summary.csv"), row.names = FALSE)
  print(summary, row.names = FALSE)
  message("Local cumulative pilot: ", round(proc.time()[["elapsed"]] - started, 2),
    " seconds; zero ACIS requests; no site or publication changes. Output: ", output_dir)
  invisible(list(directory = output_dir, summary = summary))
}
