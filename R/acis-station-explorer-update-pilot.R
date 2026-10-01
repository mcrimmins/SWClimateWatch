# Resumable, unpublished daily station-explorer refresh. Source the station
# inventory, daily-pilot, current-prototype, and explorer-prototype modules first.

plan_acis_station_explorer_refresh <- function(stations, cached, as_of) {
  as_of <- as.Date(as_of)
  if (length(as_of) != 1L || is.na(as_of) ||
      length(cached) != nrow(stations)) {
    stop("Invalid station explorer refresh plan.")
  }
  cache_as_of <- vapply(cached, function(cache) {
    if (is.null(cache)) NA_character_ else as.character(cache$as_of)
  }, character(1))
  pending <- is.na(cache_as_of) | as.Date(cache_as_of) < as_of
  data.frame(uid = stations$uid, sid = stations$sid, name = stations$name,
             target_date = as.character(as_of), cache_as_of = cache_as_of,
             pending = pending, stringsAsFactors = FALSE)
}

run_acis_station_explorer_update_pilot <- function(
    as_of = Sys.Date() - 1L, max_requests = 0L, refresh_days = 45L,
    build_page = TRUE, fetch = acis_station_fetch,
    stations_path = file.path(swc_acis_station_dir, "reference-network",
                              "daily-audit", "stations.csv"),
    cache_dir = file.path("data", "processed", "acis-stations",
                          "reference-network", "daily"),
    output_dir = file.path(swc_acis_station_dir,
                           "station-explorer-prototype")) {
  as_of <- as.Date(as_of)
  if (length(as_of) != 1L || is.na(as_of) ||
      length(max_requests) != 1L || is.na(max_requests) ||
      !is.finite(max_requests) || max_requests < 0L ||
      max_requests > .Machine$integer.max ||
      max_requests != as.integer(max_requests) ||
      length(refresh_days) != 1L || is.na(refresh_days) ||
      !is.finite(refresh_days) || refresh_days < 1L ||
      refresh_days > .Machine$integer.max ||
      refresh_days != as.integer(refresh_days) ||
      length(build_page) != 1L || is.na(build_page)) {
    stop("Invalid station explorer update options.")
  }
  stations <- acis_reference_station_table(stations_path)
  cached <- lapply(seq_len(nrow(stations)), function(i) {
    acis_station_read_daily_cache(acis_station_daily_cache_path(
      stations$uid[[i]], cache_dir), stations$uid[[i]])
  })
  before <- plan_acis_station_explorer_refresh(stations, cached, as_of)
  pending <- which(before$pending)
  scheduled <- head(pending, as.integer(max_requests))
  message(sprintf("ACIS explorer pilot: %d records; %d current; %d scheduled; %d deferred.",
                  nrow(stations), nrow(stations) - length(pending),
                  length(scheduled), length(pending) - length(scheduled)))
  if (max_requests == 0L) {
    return(list(preview = before, after = before, scheduled = integer(),
                failures = character(), page = NA_character_,
                page_as_of = if (all(vapply(cached, is.null, logical(1))))
                  as.Date(NA) else acis_station_explorer_page_date(cached, as_of)))
  }
  failures <- character()
  for (i in scheduled) {
    station <- stations[i, , drop = FALSE]
    message(sprintf("Refreshing %s (%s).", station$name, station$sid))
    tryCatch({
      update_acis_station_daily_cache(
        station, as_of = as_of, refresh_days = as.integer(refresh_days),
        cache_dir = cache_dir, fetch = fetch)
      updated <- acis_station_read_daily_cache(
        acis_station_daily_cache_path(station$uid, cache_dir), station$uid)
      if (is.null(updated)) stop("Updated cache could not be read.")
      cached[[i]] <- updated
    }, error = function(e) {
      failures <<- c(failures,
                     paste(station$sid, conditionMessage(e), sep = ": "))
      message("  Refresh failed: ", conditionMessage(e))
    })
  }
  after <- plan_acis_station_explorer_refresh(stations, cached, as_of)
  page <- NA_character_
  page_as_of <- as.Date(NA)
  if (isTRUE(build_page) && !all(vapply(cached, is.null, logical(1)))) {
    page_as_of <- acis_station_explorer_page_date(cached, as_of)
    result <- build_acis_station_explorer_prototype(
      as_of = page_as_of, stations = stations, cached = cached,
      output_dir = output_dir)
    page <- result$page
    message(sprintf("Local explorer preview built for %s; %d station caches behind the target date.",
                    as.character(page_as_of), sum(after$pending)))
  }
  list(preview = before, after = after, scheduled = scheduled,
       failures = failures, page = page, page_as_of = page_as_of)
}
