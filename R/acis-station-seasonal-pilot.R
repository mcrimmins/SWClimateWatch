# Local seasonal prototype. Uses only cached observations; production is unchanged.
acis_precipitation_seasons <- list(
  water = list(label = "Water year", start = "10-01", end = "09-30", cross = TRUE),
  cool = list(label = "Cool season", start = "10-01", end = "03-31", cross = TRUE),
  monsoon = list(label = "Monsoon", start = "06-15", end = "09-30", cross = FALSE))

acis_season_bounds <- function(season, year) {
  s <- acis_precipitation_seasons[[season]]
  if (is.null(s)) stop("Unknown precipitation season.")
  as.Date(c(sprintf("%d-%s", year - as.integer(s$cross), s$start),
            sprintf("%d-%s", year, s$end)))
}

acis_precipitation_season <- function(daily, season, year, through = NULL) {
  bounds <- acis_season_bounds(season, year)
  through <- if (is.null(through)) bounds[2] else as.Date(through)
  if (length(through) != 1L || is.na(through) || through < bounds[1] || through > bounds[2])
    stop("Cutoff outside season.")
  # Reuse daily QC, then restart accumulation at this season's own start.
  curve <- acis_precipitation_water_year(daily, year, through)
  curve <- curve[curve$date >= bounds[1] & curve$date <= bounds[2], ]
  good <- curve$status %in% c("AVAILABLE", "TRACE")
  future <- curve$status == "FUTURE"
  subtotal <- cumsum(ifelse(good, curve$daily_inches, 0))
  curve$missing_days <- cumsum(curve$status == "MISSING")
  curve$flagged_days <- cumsum(curve$status == "FLAGGED")
  curve$cumulative_inches <- ifelse(!future & curve$missing_days + curve$flagged_days == 0,
                                    subtotal, NA_real_)
  curve$observed_subtotal <- ifelse(future, NA_real_, subtotal)
  curve$missing_days[future] <- curve$flagged_days[future] <- NA_integer_
  curve
}

acis_station_seasonal_payload <- function(station, cache, season, as_of,
    baseline_years = 1991:2020, minimum_baseline = 20L, minimum_history = 30L) {
  snapshot <- as.Date(as_of)
  s <- acis_precipitation_seasons[[season]]
  year <- as.integer(format(snapshot, "%Y"))
  if (s$cross) year <- year + (format(snapshot, "%m-%d") >= s$start)
  else if (format(snapshot, "%m-%d") < s$start) year <- year - 1L
  bounds <- acis_season_bounds(season, year)
  cutoff <- min(snapshot, bounds[2])
  # Feb 29 has no common non-leap counterpart. Use Feb 28 for all comparisons
  # that day, explicitly labeled; leap precipitation enters March 1 onward.
  leap_cutoff <- format(cutoff, "%m-%d") == "02-29"
  if (leap_cutoff) cutoff <- cutoff - 1L
  current <- acis_precipitation_season(cache$daily, season, year, cutoff)
  aligned <- function(x, field = "cumulative_inches") x[[field]][x$month_day != "02-29"]
  points <- current[current$month_day != "02-29", ]
  n <- nrow(points)
  last <- max(which(points$date <= cutoff))
  daily <- cache$daily[cache$daily$variable == "pcpn", ]
  years <- if (nrow(daily)) seq.int(as.integer(format(min(daily$date), "%Y")), year - 1L) else integer()
  years <- years[years < year]
  curves <- lapply(years, function(y) acis_precipitation_season(daily, season, y))
  samples <- if (length(curves)) vapply(curves, aligned, numeric(n)) else matrix(numeric(), n, 0L)
  complete <- if (length(curves)) vapply(curves, function(x) all(is.finite(x$cumulative_inches)), logical(1)) else logical()
  eligible <- complete & years %in% baseline_years
  normal <- lower <- upper <- rep(NA_real_, n)
  if (sum(eligible) >= minimum_baseline) {
    normal <- rowMeans(samples[, eligible, drop = FALSE])
    lower <- apply(samples[, eligible, drop = FALSE], 1L, quantile, .25, type = 8, names = FALSE)
    upper <- apply(samples[, eligible, drop = FALSE], 1L, quantile, .75, type = 8, names = FALSE)
  }
  # Prefix-complete historical seasons may contribute even if later dates have gaps.
  matched <- if (length(years)) apply(samples[seq_len(last), , drop = FALSE], 2L,
                                    function(x) all(is.finite(x))) else logical()
  historical <- samples[last, matched]
  base <- matched & years %in% baseline_years
  average <- if (sum(base) >= minimum_baseline) mean(samples[last, base]) else NA_real_
  value <- points$cumulative_inches[last]
  supported <- is.finite(value) && sum(matched) >= minimum_history
  tolerance <- 1e-6
  comparison <- list(cutoff = as.character(cutoff), historical_years = sum(matched),
    baseline_years = sum(base), available = supported, average_inches = average,
    departure_inches = if (is.finite(value)) value - average else NA_real_,
    percent_average = if (is.finite(value) && is.finite(average) && average > 0) 100 * value/average else NA_real_,
    wet_rank = if (supported) 1L + sum(historical > value + tolerance) else NA_integer_,
    rank_sample = if (supported) length(historical) + 1L else NA_integer_,
    tied_years = if (supported) sum(abs(historical - value) <= tolerance) else NA_integer_,
    percentile = if (supported) 100 * (sum(historical < value - tolerance) +
      .5 * sum(abs(historical - value) <= tolerance))/length(historical) else NA_real_,
    note = paste("Matching calendar dates; rank includes current season, percentile compares earlier seasons.",
      "At least 30 complete historical prefixes and 20 baseline prefixes for departures.",
      if (leap_cutoff) "February 29 comparisons use February 28 for every year." else ""))
  history <- list(curves = list(), catalog = list())
  for (j in which(complete)) {
    entry <- list(schema_version = 1L, uid = as.integer(station$uid), water_year = years[j],
      calendar = "season-month-day", annual_total = round(samples[n,j], 4), values = round(samples[,j], 4))
    history$curves[[as.character(years[j])]] <- entry
    history$catalog[[length(history$catalog)+1L]] <- list(water_year = years[j],
      annual_total = entry$annual_total, file = sprintf("history/%d/%d.json", station$uid, years[j]))
  }
  record_low <- record_high <- rep(NA_real_, n)
  low_years <- high_years <- rep("", n)
  if (sum(complete) >= minimum_history) {
    record_low <- apply(samples[, complete, drop = FALSE], 1L, min)
    record_high <- apply(samples[, complete, drop = FALSE], 1L, max)
    for (i in seq_len(n)) {
      low_years[i] <- paste(years[complete][abs(samples[i,complete]-record_low[i]) <= tolerance], collapse = ",")
      high_years[i] <- paste(years[complete][abs(samples[i,complete]-record_high[i]) <= tolerance], collapse = ",")
    }
  }
  closest <- list(available = FALSE, note = "Requires complete current accumulation and 30 complete historical seasons.")
  if (is.finite(value) && sum(complete) >= minimum_history) {
    errors <- sqrt(colMeans((samples[seq_len(last), complete, drop = FALSE] -
      points$cumulative_inches[seq_len(last)])^2))
    tied <- sort(years[complete][abs(errors-min(errors)) <= tolerance], decreasing = TRUE)
    closest <- list(available = TRUE, water_year = tied[1], tied_years = tied,
      rmse_inches = min(errors), days_compared = last, early_season = last < 30,
      cutoff_date = as.character(cutoff))
  }
  previous <- if (as.character(year-1L) %in% names(history$curves))
    history$curves[[as.character(year-1L)]]$values else rep(NA_real_, n)
  payload <- list(schema_version = 1L, uid = as.integer(station$uid), sid = station$sid,
    name = station$name, state = station$state, role = station$role,
    snapshot_date = as.character(snapshot), as_of = as.character(cutoff), cache_as_of = as.character(cache$as_of),
    season = season, season_label = s$label, season_start = as.character(bounds[1]),
    season_end = as.character(bounds[2]), season_complete = cutoff == bounds[2],
    water_year = year, previous_water_year = year-1L,
    baseline = list(water_years = baseline_years, sample_years = sum(eligible), available = sum(eligible) >= minimum_baseline),
    current = list(total = value, observed_subtotal = points$observed_subtotal[last],
      missing_days = points$missing_days[last], flagged_days = points$flagged_days[last]),
    comparison = comparison, comparison_years = history$catalog,
    historical_context = list(available = sum(complete) >= minimum_history, sample_years = sum(complete),
      first_year = if (any(complete)) min(years[complete]) else NA_integer_,
      last_year = if (any(complete)) max(years[complete]) else NA_integer_,
      cutoff_date = as.character(cutoff), current_status = acis_cumulative_record_status(value, record_low[last], record_high[last])),
    closest_match = closest,
    annual_history = list(first_year = if (length(years)) min(years) else NA_integer_,
      last_year = year-1L, normal_inches = tail(normal,1)),
    points = data.frame(date = as.character(points$date), month_day = points$month_day,
      current = round(points$cumulative_inches,4), previous = previous, normal = round(normal,4),
      lower = round(lower,4), upper = round(upper,4), subtotal = round(points$observed_subtotal,4),
      status = points$status, missing_days = points$missing_days, flagged_days = points$flagged_days,
      record_low = round(record_low,4), record_high = round(record_high,4), low_years, high_years))
  list(payload = payload, history = history)
}

build_acis_station_seasonal_pilot <- function(uids = c(29687L,1403L,19376L), as_of = NULL,
    stations = acis_reference_station_table(),
    cache_dir = "data/processed/acis-stations/reference-network/daily",
    output_dir = "data/diagnostics/station-seasonal-pilot",
    result_cache_dir = file.path(output_dir, "build-cache")) {
  started <- proc.time()[["elapsed"]]
  stations <- stations[match(uids, stations$uid), , drop = FALSE]
  if (anyNA(stations$uid)) stop("Unknown station UID.")
  message("Reading cached observations for ",length(uids)," stations; no downloads.")
  caches <- lapply(seq_along(uids), function(i) {
    cache <- acis_station_read_daily_cache(acis_station_daily_cache_path(uids[i],cache_dir),uids[i])
    if (i %% 10L == 0L || i == length(uids)) message("Station caches read: ",i,"/",length(uids))
    cache
  })
  present <- !vapply(caches,is.null,logical(1))
  if (!any(present)) stop("Station caches missing; refresh locally first.")
  if (is.null(as_of)) as_of <- min(as.Date(vapply(caches[present],function(x) as.character(x$as_of),character(1))))
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(result_cache_dir, recursive = TRUE, showWarnings = FALSE)
  keys <- vapply(seq_along(uids),function(i) digest::digest(list(
    version=2L, station=stations[i,], cache=caches[[i]], as_of=as.character(as_of)),algo="sha256"),character(1))
  summary <- list()
  for (season in names(acis_precipitation_seasons)) for (i in seq_along(uids)) {
    root <- file.path(output_dir,season)
    if (!present[i]) {
      acis_cumulative_write_json(list(available=FALSE,note="No cached daily observations are available for this station."),
        file.path(root,paste0(uids[i],".json")))
      next
    }
    cache_file <- file.path(result_cache_dir,paste0(uids[i],"-",season,".rds"))
    saved <- if (file.exists(cache_file)) tryCatch(readRDS(cache_file),error=function(e) NULL) else NULL
    reused <- identical(saved$key,keys[i])
    if (reused) result <- saved$result else {
      result <- acis_station_seasonal_payload(stations[i,], caches[[i]], season, as_of)
      saveRDS(list(key=keys[i],result=result),cache_file)
    }
    acis_cumulative_write_json(result$payload,file.path(root,paste0(uids[i],".json")))
    for (entry in result$history$catalog) acis_cumulative_write_json(
      result$history$curves[[as.character(entry$water_year)]],file.path(root,entry$file))
    summary[[length(summary)+1L]] <- data.frame(uid=uids[i],station=stations$name[i],season,
      cutoff=result$payload$as_of, total=result$payload$current$total,
      complete_seasons=length(result$history$curves), matched_years=result$payload$comparison$historical_years,
      reused=reused)
    message(sprintf("Seasonal plots: %s %d/%d (%s).",season,i,length(uids),if(reused) "cached" else "built"))
  }
  catalog <- list(schema_version=1L,as_of=as.character(as_of),stations=lapply(seq_along(uids),function(i)
    list(uid=uids[i],name=stations$name[i],state=stations$state[i],file=paste0(uids[i],".json"))))
  acis_cumulative_write_json(catalog,file.path(output_dir,"stations.json"))
  assets <- list.files("scripts/station-seasonal-assets",full.names=TRUE)
  file.copy(assets,output_dir,overwrite=TRUE)
  summary <- do.call(rbind,summary)
  write.csv(summary,file.path(output_dir,"summary.csv"),row.names=FALSE)
  print(summary,row.names=FALSE)
  message(sprintf("Local seasonal preview ready in %.1fs; no downloads or publication.",proc.time()[["elapsed"]]-started))
  invisible(summary)
}

validate_station_seasonal_integration <- function(directory) {
  rows <- read.csv(file.path(directory,"station-explorer-data.csv"))
  root <- file.path(directory,"seasonal")
  catalog <- jsonlite::read_json(file.path(root,"stations.json"),simplifyVector=TRUE)
  stopifnot(setequal(rows$uid,catalog$stations$uid),identical(unique(rows$as_of),catalog$as_of))
  for (season in names(acis_precipitation_seasons)) for (uid in unique(rows$uid)) {
    payload <- jsonlite::read_json(file.path(root,season,paste0(uid,".json")),simplifyVector=TRUE)
    if (identical(payload$available,FALSE)) next
    stopifnot(payload$uid==uid,payload$season==season,payload$snapshot_date==catalog$as_of,
      nrow(payload$points)==switch(season,water=365L,cool=182L,monsoon=108L),
      payload$as_of<=payload$season_end,payload$as_of>=payload$season_start)
    if (length(payload$comparison_years)) for (path in payload$comparison_years$file)
      stopifnot(file.exists(file.path(root,season,path)))
  }
  js <- paste(readLines(file.path(directory,"explorer.js"),encoding="UTF-8",warn=FALSE),collapse="\n")
  stopifnot(grepl("seasonal/index.html?embedded=1&amp;uid=",js,fixed=TRUE),
    !grepl("cumulative/index.html?",js,fixed=TRUE),
    grepl("Choose water year, cool season or monsoon",js,fixed=TRUE))
  message("Integrated seasonal validation: PASS; all station links, page dates and seasonal payloads checked.")
  invisible(TRUE)
}
