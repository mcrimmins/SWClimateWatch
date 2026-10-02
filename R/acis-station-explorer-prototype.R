# Local, unpublished station explorer. Source config.R, acis-station-inventory.R,
# acis-station-daily-pilot.R, map-southwest.R, and
# acis-station-current-prototype.R before this file.

acis_station_explorer_periods <- c("7day", "30day", "90day", "6month", "12month")
acis_station_explorer_map_metrics <- c(
  "pcpn_value", "tmean_value", "pcpn_anomaly", "tmean_anomaly",
  "pcpn_percentile", "tmean_percentile")
acis_station_min_normal_years <- 15L
acis_station_standard_normal_years <- 20L
acis_station_min_rank_years <- 25L
acis_station_standard_rank_years <- 30L

acis_station_explorer_coverage <- function(rows) {
  required <- c("uid", "sid", "name", "state", "role", "longitude",
                "latitude", "as_of", "period", "period_days",
                acis_station_explorer_map_metrics,
                unlist(lapply(c("pcpn", "tmean"), function(variable) paste0(
                  variable, c("_status", "_missing_days", "_flagged_days",
                              "_normal_years", "_reference_years")))))
  if (!all(required %in% names(rows))) {
    stop("Explorer rows lack coverage-audit fields: ",
         paste(setdiff(required, names(rows)), collapse = ", "))
  }
  detail <- do.call(rbind, lapply(acis_station_explorer_map_metrics, function(metric) {
    variable <- sub("_.*", "", metric)
    status <- as.character(rows[[paste0(variable, "_status")]])
    missing <- rows[[paste0(variable, "_missing_days")]]
    flagged <- rows[[paste0(variable, "_flagged_days")]]
    normal_years <- rows[[paste0(variable, "_normal_years")]]
    reference_years <- rows[[paste0(variable, "_reference_years")]]
    available <- is.finite(rows[[metric]])
    code <- rep("UNCLASSIFIED", nrow(rows))
    code[available] <- "AVAILABLE"
    code[available & !is.na(status) & status == "PROVISIONAL"] <-
      "PROVISIONAL_TOTAL"
    code[available & !is.na(status) & status == "PARTIAL"] <-
      "PARTIAL_TEMPERATURE"
    code[available & !is.na(status) & status == "NEAR_COMPLETE"] <-
      "NEAR_COMPLETE_TEMPERATURE"
    code[!available & !is.na(status) & status == "STALE"] <- "CACHE_STALE"
    current_missing <- !available & status %in% c("INCOMPLETE", "FLAGGED") &
      !is.na(missing) & missing > 0L
    current_flagged <- !available & status %in% c("INCOMPLETE", "FLAGGED") &
      !is.na(flagged) & flagged > 0L
    code[current_missing] <- "CURRENT_MISSING"
    code[current_flagged] <- "CURRENT_FLAGGED"
    code[current_missing & current_flagged] <- "CURRENT_MISSING_AND_FLAGGED"
    code[!available & !is.na(status) & status == "PROVISIONAL"] <-
      "PRECIP_PENDING"
    code[!available & !is.na(status) & status == "FLAGGED" &
           code == "UNCLASSIFIED"] <-
      "CURRENT_FLAGGED"
    if (grepl("_anomaly$", metric)) {
      code[!available & !is.na(status) &
             status %in% c("AVAILABLE", "NEAR_COMPLETE", "PARTIAL") &
             !is.na(normal_years) & normal_years < acis_station_min_normal_years] <-
        "TOO_FEW_NORMAL_YEARS"
    } else if (grepl("_percentile$", metric)) {
      code[!available & !is.na(status) &
             status %in% c("AVAILABLE", "NEAR_COMPLETE", "PARTIAL") &
             !is.na(reference_years) & reference_years < acis_station_min_rank_years] <-
        "TOO_FEW_RANK_YEARS"
    }
    labels <- c(
      AVAILABLE = "Available",
      PROVISIONAL_TOTAL = "Observed precipitation total; recent reports pending",
      PARTIAL_TEMPERATURE = "Temperature mean from at least 95% paired days",
      NEAR_COMPLETE_TEMPERATURE = "Temperature mean from at least 98% paired days",
      CACHE_STALE = "Station cache is older than the page date",
      CURRENT_MISSING = "Missing days in the current period",
      CURRENT_FLAGGED = if (variable == "pcpn")
        "Quality flags or accumulated precipitation in the current period" else
        "Quality flags or invalid temperatures in the current period",
      CURRENT_MISSING_AND_FLAGGED = if (variable == "pcpn")
        "Missing days and quality flags or accumulated precipitation" else
        "Missing days and quality flags or invalid temperatures",
      PRECIP_PENDING = "Recent precipitation reports pending; comparison withheld",
      TOO_FEW_NORMAL_YEARS = "Fewer than 15 valid 1991-2020 comparison years",
      TOO_FEW_RANK_YEARS = "Fewer than 25 valid earlier comparison years",
      UNCLASSIFIED = "Unavailable; needs review")
    data.frame(
      as_of = rows$as_of, period = rows$period, period_days = rows$period_days,
      uid = rows$uid, sid = rows$sid, name = rows$name, state = rows$state,
      role = rows$role,
      mapped = rows$role == "fixed" & is.finite(rows$longitude) &
        is.finite(rows$latitude),
      metric = metric, value = rows[[metric]], current_status = status,
      missing_days = missing, flagged_days = flagged,
      normal_years = normal_years, reference_years = reference_years,
      reason_code = code, reason = unname(labels[code]),
      stringsAsFactors = FALSE)
  }))
  mapped <- detail[detail$mapped, , drop = FALSE]
  summary <- stats::aggregate(
    uid ~ period + metric + reason_code + reason, data = mapped, FUN = length)
  names(summary)[names(summary) == "uid"] <- "station_count"
  summary$mapped_stations <- length(unique(mapped$uid))
  summary <- summary[order(match(summary$period, acis_station_explorer_periods),
                           match(summary$metric, acis_station_explorer_map_metrics),
                           summary$reason_code), , drop = FALSE]
  rownames(summary) <- NULL
  list(detail = detail, summary = summary)
}

acis_station_period_dates <- function(as_of, period) {
  as_of <- as.Date(as_of)
  if (length(as_of) != 1L || is.na(as_of) ||
      length(period) != 1L || is.na(period) ||
      !period %in% acis_station_explorer_periods) {
    stop("Invalid station explorer period or end date.")
  }
  start <- switch(period,
                  `7day` = as_of - 6L,
                  `30day` = as_of - 29L,
                  `90day` = as_of - 89L,
                  `6month` = lubridate::`%m-%`(
                    as_of, lubridate::period(6L, units = "month")) + 1L,
                  `12month` = lubridate::`%m-%`(
                    as_of, lubridate::period(12L, units = "month")) + 1L)
  list(start = as.Date(start), end = as_of,
       days = as.integer(as_of - start) + 1L)
}

acis_station_reference_windows <- function(daily, variable, as_of,
                                           days = 30L, period = NULL) {
  as_of <- as.Date(as_of)
  variables <- if (variable == "tmean") c("maxt", "mint") else variable
  if (!nrow(daily)) {
    return(data.frame(year = integer(), value = numeric(),
                      end_date = character(), valid_days = integer(),
                      period_days = integer()))
  }
  dates <- seq.Date(min(daily$date), as_of, by = "day")
  aligned <- lapply(variables, function(v) {
    rows <- daily[daily$variable == v, , drop = FALSE]
    rows[match(dates, rows$date), , drop = FALSE]
  })
  if (!all(vapply(aligned, nrow, integer(1)) == length(dates))) {
    stop("Could not align historical station dates.")
  }
  valid_one <- function(x, precipitation = FALSE) {
    good <- !is.na(x$observed) & x$observed &
      is.finite(x$numeric_value) &
      (is.na(x$flag) | x$flag == "" |
         (precipitation & x$flag == "T"))
    if (precipitation) {
      good <- good & (is.na(x$accumulated) | !x$accumulated) &
        x$numeric_value >= 0 & x$numeric_value <= 100
    } else {
      good <- good & abs(x$numeric_value) <= 150
    }
    good[is.na(good)] <- FALSE
    good
  }
  if (variable == "pcpn") {
    values <- aligned[[1L]]$numeric_value
    valid <- valid_one(aligned[[1L]], TRUE)
  } else {
    maximum <- aligned[[1L]]$numeric_value
    minimum <- aligned[[2L]]$numeric_value
    values <- (maximum + minimum) / 2
    valid <- valid_one(aligned[[1L]]) & valid_one(aligned[[2L]]) &
      maximum >= minimum
    valid[is.na(valid)] <- FALSE
  }
  count_cumulative <- c(0, cumsum(as.integer(valid)))
  value_cumulative <- c(0, cumsum(ifelse(valid, values, 0)))
  first_year <- as.integer(format(min(daily$date), "%Y"))
  last_year <- as.integer(format(as_of, "%Y")) - 1L
  if (first_year > last_year) {
    return(data.frame(year = integer(), value = numeric(),
                      end_date = character(), valid_days = integer(),
                      period_days = integer()))
  }
  month_day <- format(as_of, "%m-%d")
  years <- seq.int(first_year, last_year)
  ends <- as.Date(sprintf("%04d-%s", years, month_day))
  starts <- if (is.null(period)) ends - as.integer(days) + 1L else
    as.Date(vapply(ends, function(end) {
      if (is.na(end)) return(NA_character_)
      as.character(acis_station_period_dates(end, period)$start)
    }, character(1)))
  required_days <- as.integer(ends - starts) + 1L
  indices <- match(ends, dates)
  start_indices <- match(starts, dates)
  candidate <- which(!is.na(indices) & !is.na(start_indices) &
                       indices >= required_days)
  if (!length(candidate)) {
    return(data.frame(year = integer(), value = numeric(),
                      end_date = character(), valid_days = integer(),
                      period_days = integer()))
  }
  end_index <- indices[candidate]
  start_index <- start_indices[candidate]
  count <- count_cumulative[end_index + 1L] - count_cumulative[start_index]
  keep <- if (variable == "pcpn") count == required_days[candidate] else
    vapply(seq_along(candidate), function(i) {
      if (count[[i]] / required_days[candidate[[i]]] < 0.95) return(FALSE)
      gaps <- rle(!valid[start_index[[i]]:end_index[[i]]])
      !any(gaps$values & gaps$lengths > 2L)
    }, logical(1))
  if (!any(keep)) return(data.frame(year = integer(), value = numeric(),
                                   end_date = character(),
                                   valid_days = integer(),
                                   period_days = integer()))
  totals <- value_cumulative[end_index[keep] + 1L] -
    value_cumulative[start_index[keep]]
  data.frame(year = years[candidate[keep]],
             value = if (variable == "pcpn") totals else
               totals / count[keep],
             end_date = as.character(ends[candidate[keep]]),
             valid_days = count[keep],
             period_days = required_days[candidate[keep]])
}

acis_station_reference_summary <- function(current, samples,
                                           normal_years = 1991:2020,
                                           min_rank_years = acis_station_min_rank_years,
                                           min_normal_years = acis_station_min_normal_years,
                                           as_of = NA) {
  valid <- samples[is.finite(samples$value), , drop = FALSE]
  normal <- valid$value[valid$year %in% normal_years]
  normal_value <- if (length(normal) >= min_normal_years)
    mean(normal) else NA_real_
  n <- nrow(valid)
  rank <- percentile <- NA_real_
  record_high <- NA_real_
  record_high_end <- NA_character_
  record_high_ties <- NA_integer_
  if (is.finite(current) && n >= min_rank_years) {
    # Midrank handles tied dry precipitation periods without making
    # every zero-total window either strictly first or strictly last.
    percentile <- 100 * (sum(valid$value < current) +
                           0.5 * sum(valid$value == current)) / n
    rank <- 1L + sum(valid$value > current)
  }
  if (n >= min_rank_years) {
    values <- c(valid$value, if (is.finite(current)) current)
    ends <- c(if ("end_date" %in% names(valid))
      as.character(valid$end_date) else rep(NA_character_, n),
      if (is.finite(current)) as.character(as.Date(as_of)))
    record_high <- max(values)
    tied <- which(abs(values - record_high) <= 1e-8)
    record_high_ties <- length(tied)
    record_high_end <- ends[[tail(tied, 1L)]]
  }
  list(reference_years = n,
       reference_partial_years = if (all(c("valid_days", "period_days") %in%
                                          names(valid)))
         sum(valid$valid_days < valid$period_days) else 0L,
       reference_start = if (n) min(valid$year) else NA_integer_,
       reference_end = if (n) max(valid$year) else NA_integer_,
       normal_years = length(normal), normal = normal_value,
       normal_partial_years = if (all(c("valid_days", "period_days") %in%
                                       names(valid)))
         sum(valid$year %in% normal_years &
               valid$valid_days < valid$period_days) else 0L,
       departure = if (is.finite(current) && is.finite(normal_value))
         current - normal_value else NA_real_,
       percentile = percentile, rank_high = rank,
       record_high = record_high, record_high_end = record_high_end,
       record_high_ties = record_high_ties)
}

acis_station_recent_extreme <- function(daily, variable, as_of,
                                        days = 30L,
                                        period = NULL,
                                        direction = c("max", "min")) {
  direction <- match.arg(direction)
  if (!is.null(period)) days <- acis_station_period_dates(as_of, period)$days
  metric <- acis_station_window_metric(daily, variable, as_of, days)
  if (metric$status != "AVAILABLE") {
    return(list(value = NA_real_, date = NA_character_, status = metric$status))
  }
  recent <- daily[daily$variable == variable &
                    daily$date >= as.Date(as_of) - as.integer(days) + 1L &
                    daily$date <= as.Date(as_of), , drop = FALSE]
  index <- if (direction == "max") which.max(recent$numeric_value) else
    which.min(recent$numeric_value)
  list(value = recent$numeric_value[[index]],
       date = as.character(recent$date[[index]]), status = "AVAILABLE")
}

acis_station_recent_three_day_precip <- function(daily, as_of, days = 30L,
                                                 period = NULL) {
  if (!is.null(period)) days <- acis_station_period_dates(as_of, period)$days
  metric <- acis_station_window_metric(daily, "pcpn", as_of, days)
  unavailable <- list(value = NA_real_, start_date = NA_character_,
                      end_date = NA_character_, status = metric$status)
  if (metric$status != "AVAILABLE" || days < 3L) return(unavailable)
  recent <- daily[daily$variable == "pcpn" &
                    daily$date >= as.Date(as_of) - as.integer(days) + 1L &
                    daily$date <= as.Date(as_of), , drop = FALSE]
  recent <- recent[order(recent$date), , drop = FALSE]
  expected <- seq.Date(as.Date(as_of) - as.integer(days) + 1L,
                       as.Date(as_of), by = "day")
  if (nrow(recent) != length(expected) || anyNA(recent$date) ||
      !all(as.Date(recent$date) == expected)) {
    return(unavailable)
  }
  totals <- round(recent$numeric_value[-c(1L, 2L)] +
                    recent$numeric_value[-c(1L, length(expected))] +
                    recent$numeric_value[-c(length(expected) - 1L,
                                             length(expected))], 2L)
  index <- which.max(totals)
  list(value = totals[[index]],
       start_date = as.character(recent$date[[index]]),
       end_date = as.character(recent$date[[index + 2L]]),
       status = "AVAILABLE")
}

# A station-specific seasonal threshold, using the same centered five-day
# 1991-2020 convention as the gridded percentile products. Keep Feb 29 in the
# calendar so its neighbors contribute even in non-leap reference years.
acis_station_temperature_thresholds <- function(daily, variable,
                                                dates, percentile = 0.9,
                                                min_years = acis_station_min_normal_years) {
  calendar <- format(seq.Date(as.Date("2000-01-01"),
                              as.Date("2000-12-31"), by = "day"), "%m-%d")
  reference <- daily[daily$variable == variable &
                       as.integer(format(daily$date, "%Y")) %in% 1991:2020 &
                       !is.na(daily$observed) & daily$observed &
                       is.finite(daily$numeric_value) &
                       (is.na(daily$flag) | daily$flag == "") &
                       abs(daily$numeric_value) <= 150, , drop = FALSE]
  reference$calendar_index <- match(format(reference$date, "%m-%d"), calendar)
  reference$year <- as.integer(format(reference$date, "%Y"))
  calendar_bins <- split(seq_len(nrow(reference)), reference$calendar_index)
  target_index <- match(format(as.Date(dates), "%m-%d"), calendar)
  thresholds <- rep(NA_real_, length(dates))
  for (index in unique(target_index[!is.na(target_index)])) {
    neighbors <- ((index + (-2L:2L) - 1L) %% length(calendar)) + 1L
    sample_index <- unlist(calendar_bins[as.character(neighbors)],
                           use.names = FALSE)
    if (length(unique(reference$year[sample_index])) >= min_years) {
      thresholds[target_index == index] <- as.numeric(stats::quantile(
        reference$numeric_value[sample_index], percentile, names = FALSE))
    }
  }
  thresholds
}

acis_station_recent_streak <- function(daily, variable, as_of, days,
                                       threshold = NULL, threshold_values = NULL,
                                       below = FALSE) {
  metric <- acis_station_window_metric(daily, variable, as_of, days)
  empty <- list(count = NA_integer_, longest = NA_integer_,
                start_date = NA_character_, end_date = NA_character_)
  if (metric$status != "AVAILABLE") return(empty)
  dates <- seq.Date(as.Date(as_of) - as.integer(days) + 1L,
                    as.Date(as_of), by = "day")
  rows <- daily[daily$variable == variable & daily$date %in% dates, , drop = FALSE]
  rows <- rows[match(dates, rows$date), , drop = FALSE]
  if (anyNA(rows$date)) return(empty)
  thresholds <- if (is.null(threshold_values)) rep(threshold, days) else
    threshold_values
  if (length(thresholds) != days || any(!is.finite(thresholds))) return(empty)
  event <- if (below) rows$numeric_value < thresholds else
    rows$numeric_value > thresholds
  runs <- rle(event)
  event_runs <- which(runs$values)
  if (!length(event_runs)) return(list(count = 0L, longest = 0L,
                                      start_date = NA_character_,
                                      end_date = NA_character_))
  winner <- event_runs[[which.max(runs$lengths[event_runs])]]
  end_index <- cumsum(runs$lengths)[[winner]]
  start_index <- end_index - runs$lengths[[winner]] + 1L
  list(count = sum(event), longest = runs$lengths[[winner]],
       start_date = as.character(dates[[start_index]]),
       end_date = as.character(dates[[end_index]]))
}

acis_station_cool_season_dates <- function(as_of) {
  as_of <- as.Date(as_of)
  year <- as.integer(format(as_of, "%Y"))
  month <- as.integer(format(as_of, "%m"))
  season_year <- if (month >= 10L) year + 1L else year
  start <- as.Date(sprintf("%04d-10-01", season_year - 1L))
  finish <- as.Date(sprintf("%04d-03-31", season_year))
  list(start = start, end = min(as_of, finish), season_year = season_year)
}

acis_station_freeze_season <- function(daily, as_of,
                                      normal_years = 1991:2020,
                                      min_years = acis_station_min_normal_years) {
  season <- acis_station_cool_season_dates(as_of)
  days <- as.integer(season$end - season$start) + 1L
  empty <- list(count = NA_integer_, normal = NA_real_, anomaly = NA_real_,
                normal_years = 0L, start = as.character(season$start),
                end = as.character(season$end))
  current <- acis_station_window_metric(daily, "mint", season$end, days)
  if (current$status != "AVAILABLE") return(empty)
  values <- daily[daily$variable == "mint" & daily$date >= season$start &
                    daily$date <= season$end, "numeric_value"]
  count <- sum(values <= 32)
  prior <- vapply(normal_years, function(year) {
    start <- as.Date(sprintf("%04d-10-01", year - 1L))
    end <- as.Date(sprintf("%04d-%s", year, format(season$end, "%m-%d")))
    if (format(season$end, "%m") %in% c("10", "11", "12")) {
      end <- as.Date(sprintf("%04d-%s", year - 1L,
                             format(season$end, "%m-%d")))
    }
    # A non-leap reference season has no February 29. March 1 gives the
    # same number of elapsed cool-season days as the leap-year target.
    if (is.na(end)) end <- as.Date(sprintf("%04d-03-01", year))
    length_days <- as.integer(end - start) + 1L
    if (acis_station_window_metric(daily, "mint", end,
                                   length_days)$status != "AVAILABLE") return(NA_real_)
    sum(daily$numeric_value[daily$variable == "mint" &
                              daily$date >= start & daily$date <= end] <= 32)
  }, numeric(1))
  usable <- prior[is.finite(prior)]
  normal <- if (length(usable) >= min_years) mean(usable) else NA_real_
  list(count = count, normal = normal,
       anomaly = if (is.finite(normal)) count - normal else NA_real_,
       normal_years = length(usable), start = as.character(season$start),
       end = as.character(season$end))
}

acis_station_explorer_rows <- function(stations, as_of,
                                       cache_dir = file.path(
                                         "data", "processed", "acis-stations",
                                         "reference-network", "daily"),
                                       caches = NULL,
                                       periods = acis_station_explorer_periods) {
  as_of <- as.Date(as_of)
  if (!length(periods) || anyDuplicated(periods) ||
      !all(periods %in% acis_station_explorer_periods)) {
    stop("Invalid explorer period selection.")
  }
  if (is.null(caches)) caches <- lapply(seq_len(nrow(stations)), function(i) {
    acis_station_read_daily_cache(
      acis_station_daily_cache_path(stations$uid[[i]], cache_dir),
      stations$uid[[i]])
  })
  if (length(caches) != nrow(stations)) stop("Station cache count mismatch.")
  results <- lapply(seq_len(nrow(stations)), function(i) {
    if (nrow(stations) > 10L && (i %% 10L == 0L || i == nrow(stations))) {
      message(sprintf("Station explorer: %d/%d records summarized.",
                      i, nrow(stations)))
    }
    station <- stations[i, , drop = FALSE]
    cache <- caches[[i]]
    fresh_cache <- !is.null(cache) && as.Date(cache$as_of) >= as_of
    threshold_start <- min(vapply(periods, function(period) as.numeric(
      acis_station_period_dates(as_of, period)$start), numeric(1)))
    threshold_dates <- if (fresh_cache) seq.Date(
      as.Date(threshold_start, origin = "1970-01-01"), as_of,
      by = "day") else as.Date(character())
    hot_thresholds <- if (fresh_cache) acis_station_temperature_thresholds(
      cache$daily, "maxt", threshold_dates) else numeric()
    warm_thresholds <- if (fresh_cache) acis_station_temperature_thresholds(
      cache$daily, "mint", threshold_dates) else numeric()
    freeze <- if (fresh_cache) acis_station_freeze_season(
      cache$daily, as_of) else list(count = NA_integer_, normal = NA_real_,
                                   anomaly = NA_real_, normal_years = 0L,
                                   start = NA_character_, end = NA_character_)
    lapply(periods, function(period) {
      window <- acis_station_period_dates(as_of, period)
      fresh <- !is.null(cache) && as.Date(cache$as_of) >= as_of
      recent <- if (fresh) cache$daily[
        cache$daily$date >= window$start & cache$daily$date <= as_of,
        , drop = FALSE] else NULL
      metric <- function(variable) {
        if (!fresh) return(list(value = NA_real_, status = "STALE",
                                missing_days = NA_integer_,
                                flagged_days = NA_integer_,
                                trailing_missing_days = NA_integer_))
        acis_station_window_metric(recent, variable, as_of, window$days)
      }
      precip <- metric("pcpn")
      temperature <- metric("tmean")
      reference <- function(variable, value) {
        if (!fresh) return(acis_station_reference_summary(
          NA_real_, data.frame(year = integer(), value = numeric())))
        samples <- acis_station_reference_windows(cache$daily, variable,
                                                   as_of, period = period)
        acis_station_reference_summary(value, samples, as_of = as_of)
      }
      p <- reference("pcpn", if (precip$status == "AVAILABLE")
        precip$value else NA_real_)
      t <- reference("tmean", temperature$value)
      extreme <- function(variable, direction = "max") {
        if (!fresh) return(list(value = NA_real_, date = NA_character_))
        acis_station_recent_extreme(recent, variable, as_of,
                                    days = window$days, direction = direction)
      }
      wettest <- extreme("pcpn")
      wettest_three_day <- if (fresh)
        acis_station_recent_three_day_precip(recent, as_of,
                                             days = window$days) else
        list(value = NA_real_, start_date = NA_character_,
             end_date = NA_character_)
      hottest <- extreme("maxt")
      coldest <- extreme("mint", "min")
      selected_dates <- seq.Date(window$start, as_of, by = "day")
      threshold_index <- match(selected_dates, threshold_dates)
      hot <- if (fresh) acis_station_recent_streak(
        recent, "maxt", as_of, window$days,
        threshold_values = hot_thresholds[threshold_index]) else
          list(count = NA_integer_, longest = NA_integer_,
               start_date = NA_character_, end_date = NA_character_)
      warm <- if (fresh) acis_station_recent_streak(
        recent, "mint", as_of, window$days,
        threshold_values = warm_thresholds[threshold_index]) else
          list(count = NA_integer_)
      dry <- if (fresh) acis_station_recent_streak(
        recent, "pcpn", as_of, window$days, threshold = 0.04,
        below = TRUE) else list(longest = NA_integer_,
                                 start_date = NA_character_,
                                 end_date = NA_character_)
      data.frame(
        uid = station$uid, sid = station$sid,
        name = station$name, state = station$state,
        role = station$role, longitude = station$longitude,
        latitude = station$latitude, as_of = as.character(as_of),
        cache_as_of = if (is.null(cache)) NA_character_ else
          as.character(cache$as_of),
        period = period, period_start = as.character(window$start),
        period_days = window$days,
        pcpn_value = precip$value, pcpn_status = precip$status,
        pcpn_missing_days = precip$missing_days,
        pcpn_flagged_days = precip$flagged_days,
        pcpn_pending_days = precip$trailing_missing_days,
        tmean_value = temperature$value, tmean_status = temperature$status,
        tmean_missing_days = temperature$missing_days,
        tmean_flagged_days = temperature$flagged_days,
        pcpn_anomaly = p$departure, tmean_anomaly = t$departure,
        pcpn_percentile = p$percentile,
        tmean_percentile = t$percentile,
        pcpn_rank = p$rank_high, tmean_rank = t$rank_high,
        pcpn_record_high = p$record_high,
        tmean_record_high = t$record_high,
        pcpn_record_high_end = p$record_high_end,
        tmean_record_high_end = t$record_high_end,
        pcpn_record_high_ties = p$record_high_ties,
        tmean_record_high_ties = t$record_high_ties,
        pcpn_reference_years = p$reference_years,
        tmean_reference_years = t$reference_years,
        tmean_reference_partial_years = t$reference_partial_years,
        pcpn_reference_start = p$reference_start,
        tmean_reference_start = t$reference_start,
        pcpn_reference_end = p$reference_end,
        tmean_reference_end = t$reference_end,
        pcpn_normal_years = p$normal_years,
        tmean_normal_years = t$normal_years,
        tmean_normal_partial_years = t$normal_partial_years,
        max_daily_pcpn = wettest$value,
        max_daily_pcpn_date = wettest$date,
        max_3day_pcpn = wettest_three_day$value,
        max_3day_pcpn_start_date = wettest_three_day$start_date,
        max_3day_pcpn_end_date = wettest_three_day$end_date,
        hottest_day = hottest$value,
        hottest_day_date = hottest$date,
        coldest_night = coldest$value,
        coldest_night_date = coldest$date,
        unusually_hot_days = hot$count,
        warm_nights = warm$count,
        longest_hot_spell = hot$longest,
        longest_hot_spell_start_date = hot$start_date,
        longest_hot_spell_end_date = hot$end_date,
        longest_dry_spell = dry$longest,
        longest_dry_spell_start_date = dry$start_date,
        longest_dry_spell_end_date = dry$end_date,
        freeze_nights = freeze$count,
        freeze_nights_normal = freeze$normal,
        freeze_nights_anomaly = freeze$anomaly,
        freeze_normal_years = freeze$normal_years,
        freeze_season_start = freeze$start,
        freeze_season_end = freeze$end,
        stringsAsFactors = FALSE)
    })
  })
  do.call(rbind, unlist(results, recursive = FALSE))
}

acis_station_explorer_daily_detail <- function(station, cache, as_of) {
  as_of <- as.Date(as_of)
  if (length(as_of) != 1L || is.na(as_of) ||
      (!is.null(cache) &&
       (as.integer(cache$uid) != as.integer(station$uid) ||
        !nrow(cache$daily)))) {
    stop("Invalid station cache for detail view: ", station$uid)
  }
  if (is.null(cache)) {
    first <- min(vapply(acis_station_explorer_periods, function(period)
      as.numeric(acis_station_period_dates(as_of, period)$start), numeric(1)))
    dates <- seq.Date(as.Date(first, origin = "1970-01-01"), as_of, by = "day")
    empty_record <- list(first_valid = NA_character_, last_valid = NA_character_,
                         valid_days = 0L)
    return(list(
      uid = as.integer(station$uid), sid = station$sid, name = station$name,
      state = station$state, role = station$role,
      as_of = as.character(as_of), cache_as_of = NA_character_,
      record = list(pcpn = empty_record, maxt = empty_record,
                    mint = empty_record, tmean = empty_record),
      daily = data.frame(
        date = as.character(dates), pcpn = NA_real_, pcpn_status = "MISSING",
        maxt = NA_real_, maxt_status = "MISSING",
        mint = NA_real_, mint_status = "MISSING",
        stringsAsFactors = FALSE)))
  }
  dates <- seq.Date(min(cache$daily$date), as_of, by = "day")
  aligned <- lapply(c("pcpn", "maxt", "mint"), function(variable) {
    source <- cache$daily[cache$daily$variable == variable &
                            cache$daily$date <= as_of, , drop = FALSE]
    source[match(dates, source$date), , drop = FALSE]
  })
  names(aligned) <- c("pcpn", "maxt", "mint")
  classify <- function(x, variable) {
    missing <- is.na(x$observed) | !x$observed |
      !is.finite(x$numeric_value)
    flagged <- !is.na(x$flag) & nzchar(x$flag) &
      if (variable == "pcpn") x$flag != "T" else TRUE
    if (variable == "pcpn") {
      flagged <- flagged | (!is.na(x$accumulated) & x$accumulated) |
        (!is.na(x$numeric_value) &
           (x$numeric_value < 0 | x$numeric_value > 100))
    } else {
      flagged <- flagged | (!is.na(x$numeric_value) &
                              abs(x$numeric_value) > 150)
    }
    missing[is.na(missing)] <- TRUE
    flagged[is.na(flagged)] <- FALSE
    status <- ifelse(missing, "MISSING", ifelse(flagged, "FLAGGED", "AVAILABLE"))
    if (variable == "pcpn") {
      trace <- status == "AVAILABLE" & !is.na(x$flag) & x$flag == "T"
      status[trace] <- "TRACE"
    }
    list(value = ifelse(status %in% c("AVAILABLE", "TRACE"),
                        x$numeric_value, NA_real_), status = status)
  }
  pcpn <- classify(aligned$pcpn, "pcpn")
  maxt <- classify(aligned$maxt, "maxt")
  mint <- classify(aligned$mint, "mint")
  inversion <- is.finite(maxt$value) & is.finite(mint$value) &
    maxt$value < mint$value
  inversion[is.na(inversion)] <- FALSE
  maxt$value[inversion] <- NA_real_
  mint$value[inversion] <- NA_real_
  maxt$status[inversion] <- "FLAGGED"
  mint$status[inversion] <- "FLAGGED"
  tmean_status <- ifelse(maxt$status == "MISSING" | mint$status == "MISSING",
                         "MISSING", ifelse(maxt$status == "FLAGGED" |
                                               mint$status == "FLAGGED",
                                             "FLAGGED", "AVAILABLE"))
  tmean_value <- ifelse(tmean_status == "AVAILABLE",
                        (maxt$value + mint$value) / 2, NA_real_)
  record <- function(value, status) {
    good <- status %in% c("AVAILABLE", "TRACE") & is.finite(value)
    list(first_valid = if (any(good)) as.character(min(dates[good])) else NA_character_,
         last_valid = if (any(good)) as.character(max(dates[good])) else NA_character_,
         valid_days = sum(good))
  }
  first <- min(vapply(acis_station_explorer_periods, function(period)
    as.numeric(acis_station_period_dates(as_of, period)$start), numeric(1)))
  recent <- dates >= as.Date(first, origin = "1970-01-01")
  list(
    uid = as.integer(station$uid), sid = station$sid, name = station$name,
    state = station$state, role = station$role,
    as_of = as.character(as_of), cache_as_of = as.character(cache$as_of),
    record = list(pcpn = record(pcpn$value, pcpn$status),
                  maxt = record(maxt$value, maxt$status),
                  mint = record(mint$value, mint$status),
                  tmean = record(tmean_value, tmean_status)),
    daily = data.frame(date = as.character(dates[recent]),
                       pcpn = pcpn$value[recent], pcpn_status = pcpn$status[recent],
                       maxt = maxt$value[recent], maxt_status = maxt$status[recent],
                       mint = mint$value[recent], mint_status = mint$status[recent],
                       stringsAsFactors = FALSE))
}

write_acis_station_explorer_details <- function(
    stations, caches, as_of,
    output_dir = file.path(swc_acis_station_dir, "station-explorer-prototype")) {
  if (length(caches) != nrow(stations) || anyDuplicated(stations$uid)) {
    stop("Station detail caches do not match the station list.")
  }
  directory <- file.path(output_dir, "station-details")
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  paths <- vapply(seq_len(nrow(stations)), function(i) {
    detail <- acis_station_explorer_daily_detail(
      stations[i, , drop = FALSE], caches[[i]], as_of)
    path <- file.path(directory, paste0(as.integer(stations$uid[[i]]), ".json"))
    writeLines(as.character(jsonlite::toJSON(
      detail, dataframe = "rows", na = "null", auto_unbox = TRUE,
      digits = 7)), path, useBytes = TRUE)
    path
  }, character(1))
  unname(paths)
}

acis_station_explorer_geojson <- function(boundaries, clip_to_region = TRUE) {
  # The maps package's legacy polygons include self-intersections that s2
  # rejects. Repair them with planar GEOS; clip only the regional county layer.
  previous_s2 <- sf::sf_use_s2()
  on.exit(sf::sf_use_s2(previous_s2), add = TRUE)
  sf::sf_use_s2(FALSE)
  boundaries <- sf::st_make_valid(sf::st_transform(boundaries, 4326))
  if (isTRUE(clip_to_region)) {
    bbox <- sf::st_bbox(c(xmin = swc_region$bbox[["west"]],
                          ymin = swc_region$bbox[["south"]],
                          xmax = swc_region$bbox[["east"]],
                          ymax = swc_region$bbox[["north"]]), crs = 4326)
    boundaries <- suppressWarnings(sf::st_crop(boundaries, bbox))
  }
  boundaries <- suppressWarnings(sf::st_simplify(
    boundaries, dTolerance = 0.02, preserveTopology = TRUE))
  path <- tempfile(fileext = ".geojson")
  on.exit(unlink(path), add = TRUE)
  sf::st_write(boundaries, path, quiet = TRUE)
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

write_acis_station_explorer_prototype <- function(
    rows,
    output_dir = file.path(swc_acis_station_dir, "station-explorer-prototype"),
    asset_dir = file.path("scripts", "station-explorer-assets"),
    states = southwest_state_boundaries(regions = NULL),
    counties = southwest_county_boundaries(),
    publication_products = NULL) {
  if (!nrow(rows) ||
      !all(c("uid", "period", "period_start", "as_of") %in% names(rows)) ||
      anyDuplicated(rows[c("uid", "period")]) ||
      length(unique(rows$as_of)) != 1L) stop("Invalid explorer rows.")
  coverage <- acis_station_explorer_coverage(rows)
  for (metric in acis_station_explorer_map_metrics) {
    part <- coverage$detail[coverage$detail$metric == metric, , drop = FALSE]
    rows[[paste0(metric, "_reason_code")]] <- part$reason_code
    rows[[paste0(metric, "_reason")]] <- part$reason
  }
  display_rows <- rows
  if (!is.null(publication_products)) {
    needed <- c("uid", "period", "metric", "publication_status", "caution_codes")
    if (!all(needed %in% names(publication_products)) ||
        anyDuplicated(publication_products[needed[1:3]]) ||
        nrow(publication_products) != nrow(rows) *
          length(acis_station_explorer_map_metrics))
      stop("Publication products do not match explorer rows.")
    for (metric in acis_station_explorer_map_metrics) {
      part <- publication_products[publication_products$metric == metric, ]
      ix <- match(paste(rows$uid, rows$period),
                  paste(part$uid, part$period))
      if (anyNA(ix) || nrow(part) != nrow(rows))
        stop("Publication products have missing station-period keys.")
      status <- as.character(part$publication_status[ix])
      display_rows[[paste0(metric, "_publication_status")]] <- status
      display_rows[[paste0(metric, "_caution_codes")]] <-
        as.character(part$caution_codes[ix])
      invalid <- status == "HIDE_INVALID"
      excluded <- status == "HIDE_EXCLUDED"
      if (any(invalid | excluded)) {
        display_rows[[metric]][invalid | excluded] <- NA_real_
        display_rows[[paste0(metric, "_reason")]][invalid] <-
          "Value failed the automatic range check"
        display_rows[[paste0(metric, "_reason")]][excluded] <-
          "Station excluded by a saved decision"
      }
    }
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  for (name in c("explorer.css", "explorer.js")) {
    if (!file.copy(file.path(asset_dir, name), file.path(output_dir, name),
                   overwrite = TRUE)) stop("Could not copy explorer asset: ", name)
  }
  leaflet_dir <- system.file("htmlwidgets", "lib", "leaflet", package = "leaflet")
  if (!nzchar(leaflet_dir)) stop("Install the R leaflet package for local assets.")
  for (name in c("leaflet.js", "leaflet.css")) {
    if (!file.copy(file.path(leaflet_dir, name), file.path(output_dir, name),
                   overwrite = TRUE)) stop("Could not copy Leaflet asset: ", name)
  }
  file.copy(system.file("LICENSE", package = "leaflet"),
            file.path(output_dir, "leaflet-package-LICENSE"), overwrite = TRUE)
  write.csv(rows, file.path(output_dir, "station-explorer-data.csv"),
            row.names = FALSE)
  write.csv(coverage$detail, file.path(output_dir, "coverage-by-station.csv"),
            row.names = FALSE)
  write.csv(coverage$summary, file.path(output_dir, "coverage-summary.csv"),
            row.names = FALSE)
  data <- list(as_of = rows$as_of[[1L]],
               bbox = unname(swc_region$bbox),
               basemap = list(
                 url = "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                 attribution = paste0(
                   "&copy; <a href=\"https://www.openstreetmap.org/copyright\" ",
                   "target=\"_blank\" rel=\"noopener\">OpenStreetMap contributors</a>")),
               periods = lapply(acis_station_explorer_periods, function(period) {
                 window <- acis_station_period_dates(rows$as_of[[1L]], period)
                 list(id = period, start = as.character(window$start),
                      days = window$days)
               }),
               stations = display_rows,
               states = jsonlite::fromJSON(acis_station_explorer_geojson(
                 states, clip_to_region = FALSE),
                                            simplifyVector = FALSE),
               counties = jsonlite::fromJSON(acis_station_explorer_geojson(counties),
                                              simplifyVector = FALSE))
  json <- as.character(jsonlite::toJSON(data, dataframe = "rows", na = "null",
                                         auto_unbox = TRUE, digits = 7))
  json <- gsub("<", "\\u003c", json, fixed = TRUE)
  template <- paste(readLines(file.path(asset_dir, "index.html"), warn = FALSE,
                              encoding = "UTF-8"), collapse = "\n")
  parts <- strsplit(template, "__EXPLORER_DATA__", fixed = TRUE)[[1L]]
  if (length(parts) != 2L) stop("Explorer template data placeholder is missing.")
  template <- paste0(parts[[1L]], json, parts[[2L]])
  path <- file.path(output_dir, "index.html")
  writeLines(enc2utf8(template), path, useBytes = TRUE)
  path
}

acis_station_explorer_page_date <- function(caches,
                                            latest_allowed = Sys.Date() - 1L) {
  latest_allowed <- as.Date(latest_allowed)
  if (length(latest_allowed) != 1L || is.na(latest_allowed)) {
    stop("Invalid station explorer latest allowed date.")
  }
  dates <- vapply(caches, function(cache) {
    if (is.null(cache)) NA_character_ else as.character(cache$as_of)
  }, character(1))
  dates <- as.Date(dates[!is.na(dates)])
  if (!length(dates)) stop("No valid station daily caches are available.")
  min(max(dates), latest_allowed)
}

build_acis_station_explorer_prototype <- function(
    as_of = NULL,
    stations_path = file.path(swc_acis_station_dir, "reference-network",
                              "daily-audit", "stations.csv"),
    cache_dir = file.path("data", "processed", "acis-stations",
                          "reference-network", "daily"),
    output_dir = file.path(swc_acis_station_dir, "station-explorer-prototype"),
    stations = NULL, cached = NULL) {
  if (is.null(stations)) stations <- acis_reference_station_table(stations_path)
  if (is.null(cached)) cached <- lapply(seq_len(nrow(stations)), function(i) {
    acis_station_read_daily_cache(acis_station_daily_cache_path(
      stations$uid[[i]], cache_dir), stations$uid[[i]])
  })
  if (length(cached) != nrow(stations)) stop("Station cache count mismatch.")
  if (is.null(as_of)) as_of <- acis_station_explorer_page_date(cached)
  as_of <- as.Date(as_of)
  if (length(as_of) != 1L || is.na(as_of)) {
    stop("Invalid station explorer page date.")
  }
  rows <- acis_station_explorer_rows(stations, as_of, cache_dir, cached)
  details <- write_acis_station_explorer_details(
    stations, cached, as_of, output_dir)
  page <- write_acis_station_explorer_prototype(rows, output_dir)
  list(page = page, detail_paths = details, rows = rows, as_of = as.Date(as_of))
}
