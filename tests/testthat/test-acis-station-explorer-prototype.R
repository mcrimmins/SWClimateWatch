source(file.path(project_root, "R", "acis-station-inventory.R"))
source(file.path(project_root, "R", "acis-station-daily-pilot.R"))
source(file.path(project_root, "R", "acis-station-current-prototype.R"))
source(file.path(project_root, "R", "acis-station-explorer-prototype.R"))
source(file.path(project_root, "R", "acis-station-explorer-update-pilot.R"))

testthat::test_that("explorer page date follows the newest usable cache", {
  caches <- list(list(as_of = as.Date("2026-09-28")), NULL,
                 list(as_of = as.Date("2026-09-30")))
  testthat::expect_equal(acis_station_explorer_page_date(
    caches, as.Date("2026-09-30")), as.Date("2026-09-30"))
  testthat::expect_equal(acis_station_explorer_page_date(
    caches, as.Date("2026-09-29")), as.Date("2026-09-29"))
  testthat::expect_error(acis_station_explorer_page_date(
    list(NULL), as.Date("2026-09-30")), "No valid station")
})

testthat::test_that("one stale station does not delay fresh station values", {
  dates <- seq.Date(as.Date("2023-12-25"), as.Date("2023-12-31"), by = "day")
  daily <- do.call(rbind, lapply(c("maxt", "mint", "pcpn"), function(variable) {
    data.frame(date = dates, variable = variable,
               numeric_value = switch(variable, maxt = 70, mint = 50, pcpn = 0.1),
               observed = TRUE, flag = "", source = "TEST", trace = FALSE,
               accumulated = FALSE)
  }))
  stations <- data.frame(uid = 1:2, sid = c("A 6", "B 6"),
                         name = c("Fresh", "Stale"), state = "AZ",
                         role = "fixed", longitude = -111, latitude = 34)
  caches <- list(list(uid = 1L, as_of = dates[[7L]], daily = daily),
                 list(uid = 2L, as_of = dates[[6L]],
                      daily = daily[daily$date < dates[[7L]], ]))
  rows <- acis_station_explorer_rows(
    stations, as.Date("2023-12-31"), caches = caches, periods = "7day")
  testthat::expect_equal(rows$pcpn_status, c("AVAILABLE", "STALE"))
  testthat::expect_equal(rows$pcpn_value[[1L]], 0.7, tolerance = 1e-8)
  testthat::expect_true(is.na(rows$pcpn_value[[2L]]))
  testthat::expect_equal(rows$cache_as_of,
                         c("2023-12-31", "2023-12-30"))
  missing <- acis_station_explorer_daily_detail(
    stations[2, , drop = FALSE], NULL, as.Date("2023-12-31"))
  testthat::expect_true(is.na(missing$cache_as_of))
  testthat::expect_true(all(missing$daily$pcpn_status == "MISSING"))
  paths <- write_acis_station_explorer_details(
    stations, list(caches[[1L]], NULL), as.Date("2023-12-31"),
    output_dir = tempfile("missing-station-detail-"))
  saved <- jsonlite::fromJSON(paths[[2L]])
  testthat::expect_true(is.null(saved$cache_as_of))
  testthat::expect_equal(saved$record$pcpn$valid_days, 0L)
})

testthat::test_that("daily pilot resumes and isolates station refresh failures", {
  root <- tempfile("acis-explorer-pilot-")
  dir.create(root)
  cache_dir <- file.path(root, "caches")
  dir.create(cache_dir)
  stations <- data.frame(
    uid = 1:2, sid = c("A 6", "B 6"), name = c("Fresh", "Failed"),
    state = "AZ", role = "fixed", longitude = -111, latitude = 34,
    daily_status = "AUDITED", maxt_start = "2023-12-30",
    mint_start = "2023-12-30", pcpn_start = "2023-12-30")
  stations_path <- file.path(root, "stations.csv")
  write.csv(stations, stations_path, row.names = FALSE)
  dates <- as.Date(c("2023-12-30", "2023-12-31"))
  daily <- do.call(rbind, lapply(c("maxt", "mint", "pcpn"), function(variable) {
    data.frame(date = dates, variable = variable,
               numeric_value = switch(variable, maxt = 70, mint = 50, pcpn = 0.1),
               observed = TRUE, flag = "", source = "TEST", trace = FALSE,
               accumulated = FALSE)
  }))
  for (uid in stations$uid) saveRDS(
    list(schema_version = 1L, uid = as.integer(uid), sid = stations$sid[[uid]],
         as_of = dates[[2L]], daily = daily),
    acis_station_daily_cache_path(uid, cache_dir))
  fetch <- function(endpoint, request) {
    if (request$sid == "B 6") stop("Simulated station outage")
    list(meta = list(uid = 1L), data = list(list(
      "2024-01-01", c("70", "", "TEST"), c("50", "", "TEST"),
      c("0.1", "", "TEST"))))
  }
  preview <- run_acis_station_explorer_update_pilot(
    as_of = as.Date("2024-01-01"), max_requests = 0L,
    fetch = fetch, stations_path = stations_path, cache_dir = cache_dir,
    build_page = FALSE)
  testthat::expect_equal(sum(preview$after$pending), 2L)
  testthat::expect_equal(preview$page_as_of, as.Date("2023-12-31"))
  result <- run_acis_station_explorer_update_pilot(
    as_of = as.Date("2024-01-01"), max_requests = 2L,
    refresh_days = 1L,
    fetch = fetch, stations_path = stations_path, cache_dir = cache_dir,
    build_page = FALSE)
  testthat::expect_equal(result$after$pending, c(FALSE, TRUE))
  testthat::expect_length(result$failures, 1L)
  testthat::expect_match(result$failures[[1L]], "Simulated station outage")
  testthat::expect_equal(acis_station_read_daily_cache(
    acis_station_daily_cache_path(1L, cache_dir), 1L)$as_of,
    as.Date("2024-01-01"))
  testthat::expect_equal(acis_station_read_daily_cache(
    acis_station_daily_cache_path(2L, cache_dir), 2L)$as_of,
    as.Date("2023-12-31"))
})

testthat::test_that("rolling calendar periods preserve real month lengths", {
  six <- acis_station_period_dates(as.Date("2026-09-28"), "6month")
  twelve <- acis_station_period_dates(as.Date("2024-02-29"), "12month")
  testthat::expect_equal(six$start, as.Date("2026-03-29"))
  testthat::expect_equal(six$days, 184L)
  testthat::expect_equal(twelve$start, as.Date("2023-03-01"))
  testthat::expect_equal(twelve$days, 366L)
  testthat::expect_equal(acis_station_period_dates(
    as.Date("2026-08-30"), "6month")$start, as.Date("2026-03-01"))
  testthat::expect_equal(acis_station_period_dates(
    as.Date("2026-09-28"), "90day")$days, 90L)
})

testthat::test_that("station reference uses complete calendar-matched windows", {
  dates <- seq.Date(as.Date("2017-01-01"), as.Date("2020-01-31"), by = "day")
  daily <- do.call(rbind, lapply(c("maxt", "mint", "pcpn"), function(variable) {
    data.frame(date = dates, variable = variable,
               numeric_value = switch(variable, maxt = 70, mint = 50, pcpn = 0.1),
               observed = TRUE, flag = "", source = "TEST", trace = FALSE,
               accumulated = FALSE)
  }))
  daily$observed[daily$variable == "pcpn" &
                   daily$date == as.Date("2018-01-15")] <- FALSE
  p <- acis_station_reference_windows(daily, "pcpn", as.Date("2020-01-30"))
  t <- acis_station_reference_windows(daily, "tmean", as.Date("2020-01-30"))
  testthat::expect_equal(p$year, c(2017L, 2019L))
  testthat::expect_equal(p$end_date, c("2017-01-30", "2019-01-30"))
  testthat::expect_equal(p$value, c(3, 3), tolerance = 1e-8)
  testthat::expect_equal(t$year, 2017:2019)
  testthat::expect_equal(t$value, rep(60, 3))
})

testthat::test_that("temperature references use the same partial-window rule", {
  dates <- seq.Date(as.Date("2017-01-01"), as.Date("2020-01-31"), by = "day")
  daily <- do.call(rbind, lapply(c("maxt", "mint"), function(variable) {
    data.frame(date = dates, variable = variable,
               numeric_value = if (variable == "maxt") 70 else 50,
               observed = TRUE, flag = "", source = "TEST", trace = FALSE,
               accumulated = FALSE)
  }))
  daily$observed[daily$variable == "mint" &
                   daily$date == as.Date("2018-01-15")] <- FALSE
  samples <- acis_station_reference_windows(
    daily, "tmean", as.Date("2020-01-30"))
  testthat::expect_equal(samples$year, 2017:2019)
  testthat::expect_equal(samples$value, rep(60, 3))
  testthat::expect_equal(samples$valid_days, c(30L, 29L, 30L))
  testthat::expect_equal(acis_station_reference_summary(
    60, samples)$reference_partial_years, 1L)
  daily$observed[daily$variable == "mint" &
                   daily$date == as.Date("2018-01-16")] <- FALSE
  testthat::expect_equal(acis_station_reference_windows(
    daily, "tmean", as.Date("2020-01-30"))$year, c(2017L, 2019L))
})

testthat::test_that("historical calendar-month totals respect leap years", {
  dates <- seq.Date(as.Date("2019-01-01"), as.Date("2023-09-28"), by = "day")
  daily <- data.frame(date = dates, variable = "pcpn", numeric_value = 0.1,
                      observed = TRUE, flag = "", source = "TEST",
                      trace = FALSE, accumulated = FALSE)
  samples <- acis_station_reference_windows(
    daily, "pcpn", as.Date("2023-09-28"), period = "12month")
  testthat::expect_equal(samples$year, 2020:2022)
  testthat::expect_equal(samples$value, c(36.6, 36.5, 36.5),
                         tolerance = 1e-7)
  daily$flag[daily$date == as.Date("2020-02-29")] <- "M"
  incomplete <- acis_station_reference_windows(
    daily, "pcpn", as.Date("2023-09-28"), period = "12month")
  testthat::expect_equal(incomplete$year, 2021:2022)
})

testthat::test_that("station ranks use full samples and handle ties", {
  samples <- data.frame(year = 2015:2018, value = c(0, 0, 2, 4),
                        end_date = paste0(2015:2018, "-01-30"))
  result <- acis_station_reference_summary(
    current = 0, samples = samples, normal_years = 2015:2018,
    min_rank_years = 4L, min_normal_years = 4L,
    as_of = as.Date("2019-01-30"))
  testthat::expect_equal(result$percentile, 25)
  testthat::expect_equal(result$rank_high, 3L)
  testthat::expect_equal(result$departure, -1.5)
  testthat::expect_equal(result$reference_start, 2015L)
  testthat::expect_equal(result$record_high, 4)
  testthat::expect_equal(result$record_high_end, "2018-01-30")
  testthat::expect_equal(result$record_high_ties, 1L)
  new_high <- acis_station_reference_summary(
    5, samples, min_rank_years = 4L, as_of = as.Date("2019-01-30"))
  testthat::expect_equal(new_high$record_high, 5)
  testthat::expect_equal(new_high$record_high_end, "2019-01-30")
  tied_high <- acis_station_reference_summary(
    4, samples, min_rank_years = 4L, as_of = as.Date("2019-01-30"))
  testthat::expect_equal(tied_high$record_high_ties, 2L)
  testthat::expect_equal(tied_high$record_high_end, "2019-01-30")
  testthat::expect_true(is.na(acis_station_reference_summary(
    0, samples, min_rank_years = 5L)$percentile))
  testthat::expect_true(is.na(acis_station_reference_summary(
    0, samples, min_rank_years = 5L)$record_high))
})

testthat::test_that("one selected period controls summaries and extremes", {
  dates <- seq.Date(as.Date("2022-01-01"), as.Date("2023-12-31"), by = "day")
  daily <- do.call(rbind, lapply(c("maxt", "mint", "pcpn"), function(variable) {
    data.frame(date = dates, variable = variable,
               numeric_value = switch(variable, maxt = 70, mint = 50, pcpn = 0.1),
               observed = TRUE, flag = "", source = "TEST", trace = FALSE,
               accumulated = FALSE)
  }))
  stations <- data.frame(uid = 1L, sid = "TEST 6", name = "Test", state = "AZ",
                         role = "fixed", longitude = -111, latitude = 34)
  cache <- list(uid = 1L, as_of = as.Date("2023-12-31"), daily = daily)
  rows <- acis_station_explorer_rows(stations, as.Date("2023-12-31"),
                                     caches = list(cache))
  testthat::expect_equal(rows$period, acis_station_explorer_periods)
  testthat::expect_equal(rows$period_days, c(7L, 30L, 90L, 184L, 365L))
  testthat::expect_equal(rows$pcpn_value, rows$period_days * 0.1,
                         tolerance = 1e-8)
  testthat::expect_equal(rows$tmean_value, rep(60, 5))
  testthat::expect_equal(rows$max_daily_pcpn_date,
                         as.character(rows$period_start))
  testthat::expect_equal(rows$max_3day_pcpn, rep(0.3, 5), tolerance = 1e-8)
  testthat::expect_equal(rows$max_3day_pcpn_start_date,
                         as.character(rows$period_start))
  testthat::expect_equal(rows$max_3day_pcpn_end_date,
                         as.character(as.Date(rows$period_start) + 2L))
})

testthat::test_that("provisional precipitation is not ranked; partial temperature is", {
  dates <- seq.Date(as.Date("1990-01-01"), as.Date("2026-09-30"), by = "day")
  daily <- do.call(rbind, lapply(c("maxt", "mint", "pcpn"), function(variable) {
    data.frame(date = dates, variable = variable,
               numeric_value = switch(variable, maxt = 70, mint = 50, pcpn = 0.1),
               observed = TRUE, flag = "", source = "TEST", trace = FALSE,
               accumulated = FALSE)
  }))
  daily$observed[daily$variable == "pcpn" &
                   daily$date == as.Date("2026-09-30")] <- FALSE
  daily$observed[daily$variable == "mint" &
                   daily$date == as.Date("2026-09-29")] <- FALSE
  station <- data.frame(uid = 1L, sid = "TEST 6", name = "Test", state = "AZ",
                        role = "fixed", longitude = -111, latitude = 34)
  cache <- list(uid = 1L, as_of = as.Date("2026-09-30"), daily = daily)
  result <- acis_station_explorer_rows(station, cache$as_of,
                                       caches = list(cache), periods = "30day")
  testthat::expect_equal(result$pcpn_status, "PROVISIONAL")
  testthat::expect_equal(result$pcpn_pending_days, 1L)
  testthat::expect_equal(result$pcpn_value, 2.9, tolerance = 1e-8)
  testthat::expect_true(is.na(result$pcpn_anomaly))
  testthat::expect_true(is.na(result$pcpn_percentile))
  testthat::expect_true(is.na(result$pcpn_rank))
  testthat::expect_equal(result$tmean_status, "PARTIAL")
  testthat::expect_equal(result$tmean_value, 60)
  testthat::expect_true(is.finite(result$tmean_anomaly))
  testthat::expect_true(is.finite(result$tmean_percentile))
})

testthat::test_that("recent extremes require a complete valid window", {
  dates <- seq.Date(as.Date("2020-01-01"), as.Date("2020-01-30"), by = "day")
  daily <- data.frame(date = dates, variable = "maxt", numeric_value = 80,
                      observed = TRUE, flag = "", source = "TEST",
                      trace = FALSE, accumulated = FALSE)
  result <- acis_station_recent_extreme(daily, "maxt", as.Date("2020-01-30"))
  testthat::expect_equal(result$value, 80)
  testthat::expect_equal(result$date, "2020-01-01")
  daily$flag[daily$variable == "maxt" & daily$date == as.Date("2020-01-03")] <- "S"
  flagged <- acis_station_recent_extreme(daily, "maxt", as.Date("2020-01-30"))
  testthat::expect_equal(flagged$status, "FLAGGED")
  testthat::expect_true(is.na(flagged$value))
})

testthat::test_that("three-day precipitation extreme uses complete consecutive days", {
  dates <- seq.Date(as.Date("2020-01-01"), as.Date("2020-01-07"), by = "day")
  daily <- data.frame(date = dates, variable = "pcpn",
                      numeric_value = c(0.1, 0.2, 0, 1, 1, 1, 0),
                      observed = TRUE, flag = "", source = "TEST",
                      trace = FALSE, accumulated = FALSE)
  result <- acis_station_recent_three_day_precip(
    daily, as.Date("2020-01-07"), days = 7L)
  testthat::expect_equal(result$value, 3)
  testthat::expect_equal(result$start_date, "2020-01-04")
  testthat::expect_equal(result$end_date, "2020-01-06")
  daily$numeric_value[] <- 0
  tied <- acis_station_recent_three_day_precip(
    daily, as.Date("2020-01-07"), days = 7L)
  testthat::expect_equal(tied$start_date, "2020-01-01")
  daily$flag[[3L]] <- "T"
  testthat::expect_equal(acis_station_recent_three_day_precip(
    daily, as.Date("2020-01-07"), days = 7L)$value, 0)
  daily$observed[[3L]] <- FALSE
  incomplete <- acis_station_recent_three_day_precip(
    daily, as.Date("2020-01-07"), days = 7L)
  testthat::expect_true(is.na(incomplete$value))
  testthat::expect_equal(incomplete$status, "INCOMPLETE")
})

testthat::test_that("hot and dry spell metrics use complete daily windows", {
  dates <- seq.Date(as.Date("2026-01-01"), as.Date("2026-01-07"), by = "day")
  daily <- do.call(rbind, lapply(c("maxt", "mint", "pcpn"), function(variable) {
    data.frame(date = dates, variable = variable,
               numeric_value = switch(variable,
                                      maxt = c(80, 81, 70, 82, 83, 84, 70),
                                      mint = c(50, 60, 60, 60, 50, 50, 50),
                                      pcpn = c(0, 0, 0.1, 0, 0, 0, 0.1)),
               observed = TRUE, flag = "", accumulated = FALSE)
  }))
  hot <- acis_station_recent_streak(daily, "maxt", dates[[7L]], 7L,
                                    threshold_values = rep(75, 7))
  testthat::expect_equal(hot$count, 5L)
  testthat::expect_equal(hot$longest, 3L)
  testthat::expect_equal(hot$start_date, "2026-01-04")
  dry <- acis_station_recent_streak(daily, "pcpn", dates[[7L]], 7L,
                                    threshold = 0.04, below = TRUE)
  testthat::expect_equal(dry$longest, 3L)
  testthat::expect_equal(dry$start_date, "2026-01-04")
  daily$observed[daily$variable == "pcpn" & daily$date == dates[[5L]]] <- FALSE
  testthat::expect_true(is.na(acis_station_recent_streak(
    daily, "pcpn", dates[[7L]], 7L, threshold = 0.04,
    below = TRUE)$longest))
})

testthat::test_that("station heat thresholds use the seasonal baseline and coverage gate", {
  dates <- seq.Date(as.Date("1991-01-01"), as.Date("2026-01-07"), by = "day")
  daily <- data.frame(date = dates, variable = "maxt", numeric_value = 70,
                      observed = TRUE, flag = "", accumulated = FALSE)
  current <- seq.Date(as.Date("2026-01-01"), as.Date("2026-01-07"), by = "day")
  testthat::expect_equal(acis_station_temperature_thresholds(
    daily, "maxt", current), rep(70, 7))
  daily$flag[as.integer(format(daily$date, "%Y")) %in% 1991:2010] <- "S"
  testthat::expect_true(all(is.na(acis_station_temperature_thresholds(
    daily, "maxt", current))))
})

testthat::test_that("freeze departure compares matching cool-season dates", {
  dates <- seq.Date(as.Date("1990-10-01"), as.Date("2026-10-02"), by = "day")
  daily <- data.frame(date = dates, variable = "mint", numeric_value = 40,
                      observed = TRUE, flag = "", accumulated = FALSE)
  daily$numeric_value[daily$date %in% as.Date(c("2026-10-01", "2026-10-02"))] <- 32
  freeze <- acis_station_freeze_season(daily, as.Date("2026-10-02"))
  testthat::expect_equal(freeze$count, 2L)
  testthat::expect_equal(freeze$normal, 0)
  testthat::expect_equal(freeze$anomaly, 2)
  testthat::expect_equal(freeze$normal_years, 30L)
  testthat::expect_equal(freeze$start, "2026-10-01")
  daily$observed[daily$date == as.Date("2026-10-02")] <- FALSE
  testthat::expect_true(is.na(acis_station_freeze_season(
    daily, as.Date("2026-10-02"))$count))
})

testthat::test_that("coverage audit separates current gaps from reference shortages", {
  rows <- data.frame(
    uid = 1:6, sid = paste0("TEST", 1:6), name = paste("Station", 1:6),
    state = "AZ", role = "fixed", longitude = -111, latitude = 34,
    as_of = "2026-09-28", period = "6month", period_days = 184L,
    pcpn_value = c(2, NA, 3, 4, NA, NA), tmean_value = 70,
    pcpn_anomaly = c(1, NA, NA, 2, NA, NA), tmean_anomaly = 1,
    pcpn_percentile = c(80, NA, 45, NA, NA, NA), tmean_percentile = 60,
    pcpn_status = c("AVAILABLE", "INCOMPLETE", "AVAILABLE", "AVAILABLE",
                    "STALE", "FLAGGED"),
    tmean_status = "AVAILABLE",
    pcpn_missing_days = c(0L, 2L, 0L, 0L, NA, 0L), tmean_missing_days = 0L,
    pcpn_flagged_days = c(0L, 1L, 0L, 0L, NA, 1L), tmean_flagged_days = 0L,
    pcpn_normal_years = c(30L, 30L, 12L, 30L, 0L, 30L),
    tmean_normal_years = 30L,
    pcpn_reference_years = c(80L, 80L, 40L, 24L, 0L, 60L),
    tmean_reference_years = 80L)
  coverage <- acis_station_explorer_coverage(rows)
  anomaly <- subset(coverage$detail, metric == "pcpn_anomaly")
  percentile <- subset(coverage$detail, metric == "pcpn_percentile")
  testthat::expect_equal(anomaly$reason_code,
                         c("AVAILABLE", "CURRENT_MISSING_AND_FLAGGED",
                           "TOO_FEW_NORMAL_YEARS", "AVAILABLE",
                           "CACHE_STALE", "CURRENT_FLAGGED"))
  testthat::expect_equal(percentile$reason_code[[4L]], "TOO_FEW_RANK_YEARS")
  testthat::expect_equal(unique(coverage$summary$mapped_stations), 6L)
})

testthat::test_that("station detail keeps daily gaps, traces, and invalid pairs explicit", {
  dates <- seq.Date(as.Date("2026-09-22"), as.Date("2026-09-28"), by = "day")
  daily <- do.call(rbind, lapply(c("pcpn", "maxt", "mint"), function(variable) {
    data.frame(date = dates, variable = variable,
               numeric_value = switch(variable, pcpn = 0.2, maxt = 80, mint = 50),
               observed = TRUE, flag = "", source = "TEST",
               trace = FALSE, accumulated = FALSE)
  }))
  daily$numeric_value[daily$variable == "pcpn" & daily$date == dates[[1L]]] <- 0
  daily$flag[daily$variable == "pcpn" & daily$date == dates[[1L]]] <- "T"
  daily$observed[daily$variable == "pcpn" & daily$date == dates[[2L]]] <- FALSE
  daily$flag[daily$variable == "pcpn" & daily$date == dates[[3L]]] <- "A"
  daily$numeric_value[daily$variable == "maxt" & daily$date == dates[[4L]]] <- 40
  station <- data.frame(uid = 7L, sid = "TEST 6", name = "Test station",
                        state = "AZ", role = "fixed")
  cache <- list(uid = 7L, as_of = dates[[7L]], daily = daily)
  detail <- acis_station_explorer_daily_detail(station, cache, dates[[7L]])
  testthat::expect_equal(detail$daily$pcpn_status[1:3],
                         c("TRACE", "MISSING", "FLAGGED"))
  testthat::expect_equal(detail$daily$maxt_status[[4L]], "FLAGGED")
  testthat::expect_equal(detail$daily$mint_status[[4L]], "FLAGGED")
  testthat::expect_true(is.na(detail$daily$maxt[[4L]]))
  testthat::expect_equal(detail$record$pcpn$valid_days, 5L)
  output <- tempfile("station-details-")
  paths <- write_acis_station_explorer_details(station, list(cache),
                                                dates[[7L]], output)
  saved <- jsonlite::fromJSON(paths[[1L]])
  testthat::expect_equal(saved$uid, 7L)
  testthat::expect_equal(nrow(saved$daily), 7L)
})

testthat::test_that("explorer HTML embeds parseable local data", {
  testthat::skip_if_not_installed("leaflet")
  polygon <- sf::st_polygon(list(matrix(c(-112, 33, -111, 33, -111, 34,
                                          -112, 34, -112, 33), ncol = 2,
                                        byrow = TRUE)))
  boundaries <- sf::st_sf(id = 1L, geometry = sf::st_sfc(polygon, crs = 4326))
  output <- tempfile("station-explorer-")
  screened <- data.frame(
    uid = 7L, period = "30day",
    metric = acis_station_explorer_map_metrics,
    publication_status = c("HIDE_INVALID", "DISPLAY_CAUTION",
                           rep("DISPLAY", 4L)),
    caution_codes = c("", "LOW_BASELINE_COVERAGE", rep("", 4L)))
  path <- write_acis_station_explorer_prototype(
    data.frame(uid = 7L, sid = "TEST 6", as_of = "2026-09-28", period = "30day",
               period_start = "2026-08-30", period_days = 30L,
               name = "Test <station>", state = "AZ", role = "fixed",
               longitude = -111, latitude = 34,
               pcpn_value = 1, tmean_value = 60,
               pcpn_anomaly = 0, tmean_anomaly = 0,
               pcpn_percentile = 50, tmean_percentile = 50,
               pcpn_status = "AVAILABLE", tmean_status = "AVAILABLE",
               pcpn_missing_days = 0L, tmean_missing_days = 0L,
               pcpn_flagged_days = 0L, tmean_flagged_days = 0L,
               pcpn_normal_years = 30L, tmean_normal_years = 30L,
               pcpn_reference_years = 60L, tmean_reference_years = 60L),
    output_dir = output,
    asset_dir = file.path(project_root, "scripts", "station-explorer-assets"),
    states = boundaries, counties = boundaries,
    publication_products = screened)
  html <- paste(readLines(path, warn = FALSE), collapse = "\n")
  embedded <- strsplit(strsplit(html,
    '<script id="explorer-data" type="application/json">',
    fixed = TRUE)[[1L]][[2L]], "</script>", fixed = TRUE)[[1L]][[1L]]
  parsed <- jsonlite::fromJSON(embedded)
  testthat::expect_equal(parsed$stations$name, "Test <station>")
  testthat::expect_equal(parsed$states$type, "FeatureCollection")
  testthat::expect_equal(parsed$basemap$url,
                         "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
  testthat::expect_true(file.exists(file.path(output, "leaflet.js")))
  testthat::expect_true(file.exists(file.path(output, "coverage-by-station.csv")))
  testthat::expect_true(file.exists(file.path(output, "coverage-summary.csv")))
  testthat::expect_equal(parsed$stations$pcpn_anomaly_reason_code, "AVAILABLE")
  testthat::expect_true(is.na(parsed$stations$pcpn_value))
  testthat::expect_equal(parsed$stations$pcpn_value_publication_status,
                         "HIDE_INVALID")
  testthat::expect_equal(parsed$stations$tmean_value_caution_codes,
                         "LOW_BASELINE_COVERAGE")
  testthat::expect_equal(read.csv(file.path(output, "station-explorer-data.csv"))$pcpn_value,
                         1)
})

testthat::test_that("state context is not cropped to the climate-grid footprint", {
  testthat::expect_gt(nrow(southwest_state_boundaries(regions = NULL)), 40L)
  polygon <- sf::st_polygon(list(matrix(c(-121, 38, -120, 38, -120, 39,
                                          -121, 39, -121, 38), ncol = 2,
                                        byrow = TRUE)))
  outside <- sf::st_sf(ID = "california",
                       geometry = sf::st_sfc(polygon, crs = 4326))
  full <- jsonlite::fromJSON(acis_station_explorer_geojson(
    outside, clip_to_region = FALSE), simplifyVector = FALSE)
  clipped <- jsonlite::fromJSON(acis_station_explorer_geojson(
    outside), simplifyVector = FALSE)
  testthat::expect_length(full$features, 1L)
  testthat::expect_length(clipped$features, 0L)
})
