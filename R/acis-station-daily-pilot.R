# Daily-data quality pilot. Source acis-station-inventory.R first.

swc_acis_pilot <- data.frame(
  uid = c(
    1349L, 1223L, 29687L, 1403L, 1564L, 1606L, 1599L,
    19376L, 19646L, 19466L, 19190L, 19404L, 19154L, 19146L, 19271L,
    32828L, 32878L, 32633L
  ),
  role = c(rep("fixed", 15L), rep("threadex_comparison", 3L)),
  area = c(
    "AZ southeast", "AZ south", "AZ south-central", "AZ central",
    "AZ central highlands", "AZ north highlands", "AZ northeast",
    "NM central", "NM north mountains", "NM northeast", "NM southeast",
    "NM east", "NM southwest", "NM southwest highlands", "NM east-central",
    "Phoenix area", "Tucson area", "Albuquerque area"
  ),
  stringsAsFactors = FALSE
)

acis_station_pilot_stations <- function(shortlist, selection = swc_acis_pilot) {
  index <- match(selection$uid, shortlist$uid)
  if (anyNA(index)) stop("Pilot station UID missing from ACIS shortlist: ",
                         paste(selection$uid[is.na(index)], collapse = ", "))
  stations <- cbind(shortlist[index, , drop = FALSE],
                    selection[, c("role", "area"), drop = FALSE])
  if (any(stations$audit_status != "AUDITED")) {
    stop("All pilot stations require completed annual coverage audits.")
  }
  if (any(stations$role == "fixed" &
          (!is.finite(stations$longitude) | !is.finite(stations$latitude)))) {
    stop("A fixed pilot station lacks map coordinates.")
  }
  if (any(stations$role == "threadex_comparison" & !stations$threadex)) {
    stop("ThreadEx comparison selection contains a non-ThreadEx station.")
  }
  for (variable in swc_acis_station_variables) {
    if (any(stations$role == "fixed" &
            (stations[[paste0(variable, "_normal_years_90pct")]] < 27L |
             stations[[paste0(variable, "_recent10_years_90pct")]] < 9L))) {
      stop("A fixed pilot station no longer meets the annual coverage screen.")
    }
  }
  rownames(stations) <- NULL
  stations
}

acis_station_daily_values <- function(station, today = Sys.Date(),
                                      fetch = acis_station_fetch,
                                      start_date = NULL, end_date = today - 1L) {
  starts <- as.Date(unlist(station[c("maxt_start", "mint_start", "pcpn_start")],
                           use.names = FALSE))
  if (is.null(start_date)) start_date <- min(starts, na.rm = TRUE)
  start_date <- as.Date(start_date)
  end_date <- as.Date(end_date)
  if (is.na(start_date) || is.na(end_date) || start_date > end_date) {
    stop("Invalid station daily date range.")
  }
  elements <- lapply(swc_acis_station_variables,
                     function(variable) list(name = variable, add = "f,i"))
  response <- fetch("StnData", list(
    sid = station$sid, sdate = as.character(start_date),
    edate = as.character(end_date), elems = elements
  ))
  if (is.null(response$data)) stop("No daily data returned for ", station$sid)
  if (!is.null(response$meta$uid) && as.integer(response$meta$uid) != station$uid) {
    stop("ACIS UID mismatch for ", station$sid)
  }
  dates <- as.Date(vapply(response$data, function(row) as.character(row[[1L]]), character(1)))
  expected <- seq.Date(start_date, end_date, by = "day")
  if (length(dates) != length(expected) || anyNA(dates) || !all(dates == expected)) {
    stop("ACIS returned missing, repeated, or out-of-order dates for ", station$sid)
  }
  parts <- lapply(seq_along(swc_acis_station_variables), function(index) {
    cells <- lapply(response$data, function(row) row[[index + 1L]])
    field <- function(position) vapply(cells, function(cell) {
      value <- unlist(cell, use.names = FALSE)
      if (length(value) < position) "" else as.character(value[[position]])
    }, character(1))
    value <- trimws(field(1L))
    flag <- trimws(field(2L))
    source <- trimws(field(3L))
    observed <- !(value %in% c("", "M"))
    numeric_value <- suppressWarnings(as.numeric(sub("A$", "", value)))
    if (swc_acis_station_variables[[index]] == "pcpn") numeric_value[value == "T"] <- 0
    data.frame(
      date = dates, variable = swc_acis_station_variables[[index]],
      value = value, flag = flag, source = source, observed = observed,
      numeric_value = numeric_value, trace = value == "T" | flag == "T",
      accumulated = grepl("A", flag, fixed = TRUE) | grepl("A$", value),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, parts)
}

acis_station_longest_gap <- function(dates, missing) {
  if (!length(dates)) return(list(days = NA_integer_, start = NA_character_, end = NA_character_))
  runs <- rle(missing)
  lengths <- ifelse(runs$values, runs$lengths, 0L)
  if (!any(lengths > 0L)) return(list(days = 0L, start = NA_character_, end = NA_character_))
  index <- which.max(lengths)
  run_end <- cumsum(runs$lengths)[[index]]
  run_start <- run_end - runs$lengths[[index]] + 1L
  list(days = as.integer(runs$lengths[[index]]),
       start = as.character(dates[[run_start]]),
       end = as.character(dates[[run_end]]))
}

acis_station_daily_summaries <- function(daily, station, today = Sys.Date()) {
  as_of <- today - 1L
  recent_start <- as.Date(sprintf("%04d-01-01", as.integer(format(today, "%Y")) - 10L))
  daily$year <- as.integer(format(daily$date, "%Y"))
  daily$month <- format(daily$date, "%Y-%m")
  by_group <- function(keys) {
    labels <- do.call(interaction, c(daily[keys], list(drop = TRUE, lex.order = TRUE)))
    groups <- split(daily, labels)
    do.call(rbind, lapply(groups, function(x) {
      result <- x[1L, keys, drop = FALSE]
      result$days <- nrow(x)
      result$observed_days <- sum(x$observed)
      result$missing_days <- result$days - result$observed_days
      result$coverage <- result$observed_days / result$days
      result$trace_days <- sum(x$trace)
      result$special_flag_days <- sum(nzchar(x$flag) & !x$flag %in% c("M", "T"))
      result$accumulated_days <- sum(x$accumulated)
      result
    }))
  }
  annual <- by_group(c("variable", "year"))
  monthly <- by_group(c("variable", "month"))
  monthly <- monthly[(as.integer(substr(monthly$month, 1L, 4L)) >= 1991L &
                        as.integer(substr(monthly$month, 1L, 4L)) <= 2020L) |
                       as.integer(substr(monthly$month, 1L, 4L)) >=
                       as.integer(format(recent_start, "%Y")), , drop = FALSE]
  summary <- do.call(rbind, lapply(swc_acis_station_variables, function(variable) {
    x <- daily[daily$variable == variable, , drop = FALSE]
    baseline <- x[x$date >= as.Date("1991-01-01") & x$date <= as.Date("2020-12-31"), ]
    recent <- x[x$date >= recent_start & x$date < as.Date(sprintf("%04d-01-01",
                                                     as.integer(format(today, "%Y")))), ]
    last_date <- if (any(x$observed)) max(x$date[x$observed]) else as.Date(NA)
    baseline_gap <- acis_station_longest_gap(baseline$date, !baseline$observed)
    recent_gap <- acis_station_longest_gap(recent$date, !recent$observed)
    valid_source <- x$source[x$observed & nzchar(x$source) & x$source != "M"]
    data.frame(
      uid = station$uid, sid = station$sid, name = station$name,
      state = station$state, role = station$role, variable = variable,
      as_of = as.character(as_of), first_observed = if (any(x$observed))
        as.character(min(x$date[x$observed])) else NA_character_,
      latest_observed = as.character(last_date),
      latest_lag_days = as.integer(as_of - last_date),
      baseline_coverage = if (nrow(baseline)) mean(baseline$observed) else NA_real_,
      baseline_longest_gap_days = baseline_gap$days,
      baseline_longest_gap_start = baseline_gap$start,
      baseline_longest_gap_end = baseline_gap$end,
      recent10_coverage = if (nrow(recent)) mean(recent$observed) else NA_real_,
      recent10_longest_gap_days = recent_gap$days,
      recent10_longest_gap_start = recent_gap$start,
      recent10_longest_gap_end = recent_gap$end,
      trace_days = sum(x$trace),
      special_flag_days = sum(nzchar(x$flag) & !x$flag %in% c("M", "T")),
      accumulated_days = sum(x$accumulated),
      unparsed_observed_days = sum(x$observed & is.na(x$numeric_value)),
      distinct_source_ids = length(unique(valid_source)),
      source_id_transitions = if (length(valid_source) < 2L) 0L else
        sum(valid_source[-1L] != valid_source[-length(valid_source)]),
      stringsAsFactors = FALSE
    )
  }))
  source_rows <- daily[daily$observed & nzchar(daily$source) & daily$source != "M", ]
  sources <- if (nrow(source_rows)) {
    groups <- split(source_rows, interaction(source_rows$variable, source_rows$source,
                                             drop = TRUE, lex.order = TRUE))
    do.call(rbind, lapply(groups, function(x) data.frame(
      variable = x$variable[[1L]], source_id = x$source[[1L]],
      days = nrow(x), first_date = as.character(min(x$date)),
      last_date = as.character(max(x$date))
    )))
  } else data.frame(variable = character(), source_id = character(),
                    days = integer(), first_date = character(), last_date = character())
  flagged <- daily[nzchar(daily$flag), ]
  flags <- if (nrow(flagged)) {
    groups <- split(flagged, interaction(flagged$variable, flagged$flag,
                                         drop = TRUE, lex.order = TRUE))
    do.call(rbind, lapply(groups, function(x) data.frame(
      variable = x$variable[[1L]], flag = x$flag[[1L]], days = nrow(x)
    )))
  } else data.frame(variable = character(), flag = character(), days = integer())
  maximum <- daily[daily$variable == "maxt", "numeric_value"]
  minimum <- daily[daily$variable == "mint", "numeric_value"]
  checks <- data.frame(uid = station$uid, sid = station$sid, name = station$name,
                       state = station$state, role = station$role,
                       maxt_below_mint_days = sum(maximum < minimum, na.rm = TRUE),
                       negative_pcpn_days = sum(daily$variable == "pcpn" &
                                                  daily$numeric_value < 0, na.rm = TRUE),
                       stringsAsFactors = FALSE)
  for (table in c("annual", "monthly", "sources", "flags")) {
    value <- get(table)
    value$uid <- rep(station$uid, nrow(value))
    assign(table, value)
  }
  list(summary = summary, annual = annual, monthly = monthly,
       sources = sources, flags = flags, checks = checks)
}

run_acis_station_daily_pilot <- function(max_stations = 2L, today = Sys.Date(),
                                         directory = file.path(swc_acis_station_dir, "daily-pilot"),
                                         shortlist_path = file.path(swc_acis_station_dir, "station-shortlist.csv"),
                                         selection = swc_acis_pilot, fetch = acis_station_fetch,
                                         refresh_uids = integer()) {
  stopifnot(inherits(today, "Date"), length(max_stations) == 1L,
            is.finite(max_stations), max_stations >= 0L)
  if (!file.exists(shortlist_path)) stop("Run the annual ACIS station inventory first.")
  shortlist <- read.csv(shortlist_path, stringsAsFactors = FALSE)
  stations <- acis_station_pilot_stations(shortlist, selection)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  cache_dir <- file.path(directory, "station-summaries")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- file.path(cache_dir, paste0(stations$uid, ".rds"))
  valid_cache <- function(path) {
    if (!file.exists(path)) return(FALSE)
    value <- tryCatch(readRDS(path), error = function(e) NULL)
    is.list(value) && identical(value$schema_version, 1L)
  }
  pending <- which(!vapply(paths, valid_cache, logical(1)) |
                     stations$uid %in% refresh_uids)
  scheduled <- head(pending, as.integer(max_stations))
  message(sprintf("ACIS daily pilot: %d stations; %d pending; %d scheduled.",
                  nrow(stations), length(pending), length(scheduled)))
  failures <- character()
  for (index in scheduled) {
    station <- stations[index, , drop = FALSE]
    message(sprintf("Daily review %s (%s).", station$name, station$sid))
    tryCatch({
      daily <- acis_station_daily_values(station, today, fetch)
      result <- acis_station_daily_summaries(daily, station, today)
      result$schema_version <- 1L
      saveRDS(result, paths[[index]])
      rm(daily, result)
    }, error = function(e) {
      failures <<- c(failures, sprintf("%s: %s", station$sid, conditionMessage(e)))
      message("  Daily review failed: ", conditionMessage(e))
    })
  }
  available <- which(vapply(paths, valid_cache, logical(1)))
  results <- lapply(paths[available], readRDS)
  for (table in c("summary", "annual", "monthly", "sources", "flags", "checks")) {
    data <- if (length(results)) do.call(rbind, lapply(results, `[[`, table)) else data.frame()
    write.csv(data, file.path(directory, paste0(table, ".csv")), row.names = FALSE)
  }
  stations$daily_status <- ifelse(vapply(paths, valid_cache, logical(1)),
                                  "AUDITED", "PENDING")
  write.csv(stations, file.path(directory, "pilot-stations.csv"), row.names = FALSE)
  list(stations = stations, audited_this_run = length(scheduled) - length(failures),
       pending = sum(stations$daily_status == "PENDING"), failures = failures,
       directory = directory)
}
