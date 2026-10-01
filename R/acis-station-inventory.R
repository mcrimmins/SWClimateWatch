# Read-only discovery and annual completeness audit for RCC-ACIS stations.
# No station data or site assets are published by this module.

swc_acis_station_variables <- c("maxt", "mint", "pcpn")
swc_acis_station_dir <- file.path("data", "diagnostics", "acis-stations")

acis_station_fetch <- function(endpoint, params) {
  request <- httr2::request(paste0("https://data.rcc-acis.org/", endpoint)) |>
    httr2::req_body_form(params = as.character(jsonlite::toJSON(params, auto_unbox = TRUE))) |>
    httr2::req_user_agent("SWClimateWatch station inventory (research audit)") |>
    httr2::req_timeout(120) |>
    httr2::req_retry(max_tries = 3)
  result <- jsonlite::fromJSON(
    httr2::resp_body_string(httr2::req_perform(request)),
    simplifyVector = FALSE
  )
  if (!is.null(result$error)) stop("RCC-ACIS: ", result$error, call. = FALSE)
  result
}

acis_station_metadata <- function(fetch = acis_station_fetch) {
  fields <- c("uid", "name", "state", "ll", "elev", "sids", "valid_daterange")
  common <- list(elems = swc_acis_station_variables, meta = fields)
  # State lookup includes ThreadEx area records, which often have no point ll.
  states <- fetch("StnMeta", c(list(state = swc_region$abbreviations), common))$meta
  # The bounding box adds long-record stations in the surrounding border pad.
  box <- fetch("StnMeta", c(list(bbox = unname(swc_region$bbox)), common))$meta
  records <- c(states, box)
  if (length(records) == 0L) stop("RCC-ACIS returned no station metadata.")
  ids <- vapply(records, function(x) as.character(x$uid), character(1))
  records[!duplicated(ids)]
}

acis_station_range <- function(record, variable) {
  index <- match(variable, swc_acis_station_variables)
  ranges <- record$valid_daterange
  if (is.null(ranges) || length(ranges) < index) return(rep(NA_character_, 2L))
  value <- unlist(ranges[[index]], use.names = FALSE)
  if (length(value) != 2L) rep(NA_character_, 2L) else as.character(value)
}

acis_station_preferred_sid <- function(sids) {
  ids <- as.character(unlist(sids, use.names = FALSE))
  if (!length(ids)) return(NA_character_)
  for (kind in c("9", "6", "2", "1")) {
    match_id <- grep(paste0(" ", kind, "$"), ids, value = TRUE)
    if (length(match_id)) return(match_id[[1L]])
  }
  ids[[1L]]
}

acis_station_candidates <- function(metadata, today = Sys.Date(),
                                    min_span_years = 70, recent_within_days = 730) {
  stopifnot(inherits(today, "Date"), min_span_years > 0, recent_within_days > 0)
  rows <- lapply(metadata, function(record) {
    ids <- as.character(unlist(record$sids, use.names = FALSE))
    is_threadex <- any(grepl(" 9$", ids))
    ranges <- lapply(swc_acis_station_variables,
                     function(variable) acis_station_range(record, variable))
    starts <- vapply(ranges, `[[`, character(1), 1L)
    ends <- vapply(ranges, `[[`, character(1), 2L)
    spans <- as.numeric(as.Date(ends) - as.Date(starts)) / 365.25
    recent <- as.numeric(today - as.Date(ends)) <= recent_within_days
    # Metadata is a screen, not evidence of annual completeness.
    selected <- is_threadex || all(!is.na(spans) & spans >= min_span_years &
                                       !is.na(recent) & recent)
    ll <- as.numeric(unlist(record$ll, use.names = FALSE))
    data.frame(
      uid = as.integer(record$uid), sid = acis_station_preferred_sid(record$sids),
      name = as.character(record$name), state = as.character(record$state),
      longitude = if (length(ll) >= 2L) ll[[1L]] else NA_real_,
      latitude = if (length(ll) >= 2L) ll[[2L]] else NA_real_,
      elevation_ft = if (is.null(record$elev)) NA_real_ else as.numeric(record$elev),
      threadex = is_threadex, selected = selected,
      maxt_start = starts[[1L]], maxt_end = ends[[1L]],
      mint_start = starts[[2L]], mint_end = ends[[2L]],
      pcpn_start = starts[[3L]], pcpn_end = ends[[3L]],
      shortest_span_years = if (all(is.finite(spans))) min(spans) else NA_real_,
      stringsAsFactors = FALSE
    )
  })
  result <- do.call(rbind, rows)
  result <- result[order(!result$selected, !result$threadex,
                         -result$shortest_span_years, result$state, result$name,
                         na.last = TRUE), , drop = FALSE]
  rownames(result) <- NULL
  result
}

acis_station_annual_coverage <- function(candidate, through_year = as.integer(format(Sys.Date(), "%Y")) - 1L,
                                         fetch = acis_station_fetch) {
  starts <- as.Date(unlist(candidate[c("maxt_start", "mint_start", "pcpn_start")],
                           use.names = FALSE))
  if (all(is.na(starts))) stop("No valid ACIS date range for ", candidate$sid)
  first_year <- as.integer(format(min(starts, na.rm = TRUE), "%Y"))
  if (first_year > through_year) stop("No complete calendar years for ", candidate$sid)
  elements <- lapply(swc_acis_station_variables, function(variable) {
    list(name = variable, interval = "yly", duration = "yly",
         reduce = list(reduce = if (variable == "pcpn") "sum" else "mean",
                       add = "mcnt"))
  })
  response <- fetch("StnData", list(
    sid = candidate$sid, sdate = sprintf("%04d-01-01", first_year),
    edate = sprintf("%04d-12-31", through_year), elems = elements
  ))
  if (is.null(response$data)) stop("No annual data returned for ", candidate$sid)
  years <- seq.int(first_year, through_year)
  year_days <- as.integer(as.Date(sprintf("%04d-01-01", years + 1L)) -
                            as.Date(sprintf("%04d-01-01", years)))
  result <- expand.grid(year = years, variable = swc_acis_station_variables,
                        KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  result$days <- rep(year_days, times = length(swc_acis_station_variables))
  result$missing_days <- NA_integer_
  for (entry in response$data) {
    year <- suppressWarnings(as.integer(entry[[1L]]))
    if (is.na(year) || !year %in% years || length(entry) < 4L) next
    for (index in seq_along(swc_acis_station_variables)) {
      cell <- unlist(entry[[index + 1L]], use.names = FALSE)
      missing <- suppressWarnings(as.integer(tail(cell, 1L)))
      row <- which(result$year == year & result$variable == swc_acis_station_variables[[index]])
      if (length(missing) == 1L && !is.na(missing)) result$missing_days[row] <- missing
    }
  }
  if (anyNA(result$missing_days) || any(result$missing_days < 0L | result$missing_days > result$days)) {
    stop("Incomplete or invalid ACIS missing-day counts for ", candidate$sid, call. = FALSE)
  }
  result$observed_days <- result$days - result$missing_days
  result$coverage <- result$observed_days / result$days
  result$uid <- candidate$uid
  result$sid <- candidate$sid
  result[, c("uid", "sid", "year", "variable", "days", "observed_days",
             "missing_days", "coverage")]
}

acis_station_coverage_cache_current <- function(path, through_year) {
  if (!file.exists(path)) return(FALSE)
  data <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(data) || !all(c("year", "variable", "coverage") %in% names(data)) ||
      nrow(data) == 0L || anyNA(data$coverage)) return(FALSE)
  years <- seq.int(min(data$year), through_year)
  expected <- expand.grid(year = years, variable = swc_acis_station_variables,
                          KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  identical(sort(paste(data$year, data$variable)),
            sort(paste(expected$year, expected$variable)))
}

acis_station_coverage_summary <- function(candidates, coverage_dir,
                                          through_year = as.integer(format(Sys.Date(), "%Y")) - 1L) {
  selected <- candidates[candidates$selected, , drop = FALSE]
  selected$audit_status <- "PENDING"
  for (variable in swc_acis_station_variables) {
    selected[[paste0(variable, "_years_90pct")]] <- NA_integer_
    selected[[paste0(variable, "_normal_years_90pct")]] <- NA_integer_
    selected[[paste0(variable, "_recent10_years_90pct")]] <- NA_integer_
  }
  for (index in seq_len(nrow(selected))) {
    path <- file.path(coverage_dir, paste0(selected$uid[[index]], ".csv"))
    if (!acis_station_coverage_cache_current(path, through_year)) next
    coverage <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
    if (is.null(coverage)) next
    selected$audit_status[[index]] <- "AUDITED"
    for (variable in swc_acis_station_variables) {
      part <- coverage[coverage$variable == variable & coverage$coverage >= 0.9, , drop = FALSE]
      selected[[paste0(variable, "_years_90pct")]][[index]] <- nrow(part)
      selected[[paste0(variable, "_normal_years_90pct")]][[index]] <-
        sum(part$year >= 1991L & part$year <= 2020L)
      selected[[paste0(variable, "_recent10_years_90pct")]][[index]] <-
        sum(part$year >= through_year - 9L & part$year <= through_year)
    }
  }
  selected
}

run_acis_station_inventory <- function(max_stations = 5L, refresh_metadata = FALSE,
                                       today = Sys.Date(),
                                       directory = swc_acis_station_dir,
                                       fetch = acis_station_fetch) {
  stopifnot(length(max_stations) == 1L, is.finite(max_stations), max_stations >= 0,
            inherits(today, "Date"))
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  coverage_dir <- file.path(directory, "annual-coverage")
  dir.create(coverage_dir, recursive = TRUE, showWarnings = FALSE)
  metadata_path <- file.path(directory, "metadata.rds")
  cache_recent <- file.exists(metadata_path) &&
    as.numeric(difftime(Sys.time(), file.info(metadata_path)$mtime, units = "days")) < 7
  if (refresh_metadata || !cache_recent) {
    message("Reading ACIS station metadata for AZ/NM and the border footprint.")
    metadata <- acis_station_metadata(fetch)
    saveRDS(metadata, metadata_path)
  } else {
    metadata <- readRDS(metadata_path)
  }
  candidates <- acis_station_candidates(metadata, today = today)
  write.csv(candidates, file.path(directory, "metadata-screen.csv"), row.names = FALSE)
  selected <- candidates[candidates$selected, , drop = FALSE]
  through_year <- as.integer(format(today, "%Y")) - 1L
  paths <- file.path(coverage_dir, paste0(selected$uid, ".csv"))
  coverage_current <- vapply(paths, acis_station_coverage_cache_current,
                             logical(1), through_year = through_year)
  pending <- which(!coverage_current)
  scheduled <- head(pending, as.integer(max_stations))
  message(sprintf("ACIS inventory: %d metadata records; %d candidates; %d coverage audits pending; %d scheduled.",
                  nrow(candidates), nrow(selected), length(pending), length(scheduled)))
  failures <- character()
  for (index in scheduled) {
    station <- selected[index, , drop = FALSE]
    message(sprintf("Auditing %s (%s).", station$name, station$sid))
    tryCatch({
      coverage <- acis_station_annual_coverage(station, through_year, fetch)
      write.csv(coverage, paths[[index]], row.names = FALSE)
    }, error = function(e) {
      failures <<- c(failures, sprintf("%s: %s", station$sid, conditionMessage(e)))
      message("  Audit failed: ", conditionMessage(e))
    })
  }
  summary <- acis_station_coverage_summary(candidates, coverage_dir, through_year)
  write.csv(summary, file.path(directory, "station-shortlist.csv"), row.names = FALSE)
  list(candidates = candidates, shortlist = summary,
       audited_this_run = length(scheduled) - length(failures),
       pending = sum(summary$audit_status != "AUDITED"), failures = failures,
       directory = directory)
}
