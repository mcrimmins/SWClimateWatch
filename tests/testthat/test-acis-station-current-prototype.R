source(file.path(project_root, "R", "acis-station-inventory.R"))
source(file.path(project_root, "R", "acis-station-daily-pilot.R"))
source(file.path(project_root, "R", "acis-station-current-prototype.R"))

acis_prototype_daily <- function(days = 30L) {
  dates <- seq.Date(as.Date("2020-01-01"), by = "day", length.out = days)
  do.call(rbind, lapply(c("maxt", "mint", "pcpn"), function(variable) {
    data.frame(date = dates, variable = variable,
               numeric_value = switch(variable, maxt = 80, mint = 60, pcpn = 0.1),
               observed = TRUE, flag = "", source = "TEST",
               trace = FALSE, accumulated = FALSE)
  }))
}

testthat::test_that("30-day station metrics require valid individual days", {
  daily <- acis_prototype_daily()
  as_of <- as.Date("2020-01-30")
  testthat::expect_equal(acis_station_window_metric(daily, "pcpn", as_of)$value,
                         3, tolerance = 1e-8)
  testthat::expect_equal(acis_station_window_metric(daily, "tmean", as_of)$value,
                         70)
  gap <- daily
  gap$observed[gap$variable == "pcpn" & gap$date == as.Date("2020-01-15")] <- FALSE
  testthat::expect_equal(acis_station_window_metric(gap, "pcpn", as_of)$status,
                         "INCOMPLETE")
  testthat::expect_true(is.na(acis_station_window_metric(gap, "pcpn", as_of)$value))
  gap$flag[gap$variable == "pcpn" & gap$date == as.Date("2020-01-15")] <- "M"
  testthat::expect_equal(acis_station_window_metric(gap, "pcpn", as_of)$flagged_days,
                         0L)
  flagged <- daily
  flagged$flag[flagged$variable == "pcpn" &
                 flagged$date == as.Date("2020-01-15")] <- "A"
  testthat::expect_equal(acis_station_window_metric(flagged, "pcpn", as_of)$status,
                         "FLAGGED")
  trace <- daily
  trace$numeric_value[trace$variable == "pcpn" &
                        trace$date == as.Date("2020-01-15")] <- 0
  trace$flag[trace$variable == "pcpn" &
               trace$date == as.Date("2020-01-15")] <- "T"
  testthat::expect_equal(acis_station_window_metric(trace, "pcpn", as_of)$status,
                         "AVAILABLE")
  inversion <- daily
  inversion$numeric_value[inversion$variable == "maxt" &
                            inversion$date == as.Date("2020-01-15")] <- 30
  testthat::expect_equal(acis_station_window_metric(inversion, "tmean", as_of)$status,
                         "FLAGGED")
  testthat::expect_equal(acis_station_window_metric(
    daily[daily$date != as.Date("2020-01-15"), ], "tmean", as_of)$missing_days, 1L)
})

testthat::test_that("recent precipitation lag is provisional, not a complete total", {
  daily <- acis_prototype_daily(90L)
  end <- max(daily$date)
  pending <- daily$variable == "pcpn" & daily$date >= end - 1L
  daily$observed[pending] <- FALSE
  result <- acis_station_window_metric(daily, "pcpn", end, 90L)
  testthat::expect_equal(result$status, "PROVISIONAL")
  testthat::expect_equal(result$missing_days, 2L)
  testthat::expect_equal(result$trailing_missing_days, 2L)
  testthat::expect_equal(result$value, 8.8, tolerance = 1e-8)
  daily$observed[daily$variable == "pcpn" & daily$date == end - 10L] <- FALSE
  testthat::expect_equal(acis_station_window_metric(
    daily, "pcpn", end, 90L)$status, "INCOMPLETE")
  short <- acis_prototype_daily(7L)
  short$observed[short$variable == "pcpn" & short$date == max(short$date)] <- FALSE
  testthat::expect_equal(acis_station_window_metric(short, "pcpn",
    max(short$date), 7L)$status, "PROVISIONAL")
  short$observed[short$variable == "pcpn" & short$date == max(short$date) - 1L] <- FALSE
  testthat::expect_equal(acis_station_window_metric(short, "pcpn",
    max(short$date), 7L)$status, "INCOMPLETE")
})

testthat::test_that("partial temperature needs 95 percent and no long gap", {
  daily <- acis_prototype_daily(30L)
  end <- max(daily$date)
  daily$observed[daily$variable == "mint" & daily$date == end - 1L] <- FALSE
  result <- acis_station_window_metric(daily, "tmean", end, 30L)
  testthat::expect_equal(result$status, "PARTIAL")
  testthat::expect_equal(result$value, 70)
  daily$observed[daily$variable == "mint" & daily$date == end - 2L] <- FALSE
  testthat::expect_equal(acis_station_window_metric(
    daily, "tmean", end, 30L)$status, "INCOMPLETE")
  long <- acis_prototype_daily(90L)
  long_end <- max(long$date)
  long$observed[long$variable == "mint" & long$date == long_end] <- FALSE
  testthat::expect_equal(acis_station_window_metric(
    long, "tmean", long_end, 90L)$status, "NEAR_COMPLETE")
  long$observed[long$variable == "mint" &
                  long$date %in% seq.Date(long_end - 5L, long_end - 3L,
                                          by = "day")] <- FALSE
  testthat::expect_equal(acis_station_window_metric(
    long, "tmean", long_end, 90L)$status, "INCOMPLETE")
})

testthat::test_that("compact station cache refreshes revisions and fills gaps", {
  station <- data.frame(uid = 42L, sid = "TEST 6", name = "Test Station",
                        state = "AZ", role = "fixed", longitude = -111,
                        latitude = 34, maxt_start = "2020-01-01",
                        mint_start = "2020-01-01", pcpn_start = "2020-01-01")
  requests <- character()
  fetch <- function(endpoint, params) {
    testthat::expect_equal(endpoint, "StnData")
    requests <<- c(requests, paste(params$sdate, params$edate))
    dates <- seq.Date(as.Date(params$sdate), as.Date(params$edate), by = "day")
    list(meta = list(uid = 42L), data = lapply(dates, function(date) {
      list(as.character(date), list("80", "", "A"), list("60", "", "A"),
           list(if (length(requests) == 3L) "0.20" else "0.10", "", "A"))
    }))
  }
  cache_dir <- tempfile("acis-cache-")
  first <- update_acis_station_daily_cache(station, as.Date("2020-01-30"),
                                            3L, cache_dir, fetch)
  second <- update_acis_station_daily_cache(station, as.Date("2020-02-03"),
                                             3L, cache_dir, fetch)
  third <- update_acis_station_daily_cache(station, as.Date("2020-02-03"),
                                            3L, cache_dir, fetch)
  testthat::expect_true(first$refreshed)
  testthat::expect_true(second$refreshed)
  testthat::expect_false(third$refreshed)
  testthat::expect_equal(requests,
                         c("2020-01-01 2020-01-30", "2020-01-31 2020-02-03"))
  cache <- acis_station_read_daily_cache(first$path, 42L)
  testthat::expect_equal(nrow(cache$daily), 34L * 3L)
  testthat::expect_equal(acis_station_window_metric(cache$daily, "tmean",
                                                   as.Date("2020-02-03"))$value, 70)
  update_acis_station_daily_cache(station, as.Date("2020-02-04"),
                                  3L, cache_dir, fetch)
  revised <- acis_station_read_daily_cache(first$path, 42L)$daily
  testthat::expect_equal(revised$numeric_value[
    revised$variable == "pcpn" & revised$date == as.Date("2020-02-02")], 0.2)
  testthat::expect_equal(requests[[3L]], "2020-02-02 2020-02-04")
})

testthat::test_that("stale station caches do not produce current values", {
  station <- data.frame(uid = 42L, sid = "TEST 6", name = "Test Station",
                        state = "AZ", role = "fixed", longitude = -111,
                        latitude = 34)
  cache_dir <- tempfile("acis-empty-cache-")
  rows <- acis_reference_current_rows(station, as.Date("2020-01-30"), cache_dir)
  testthat::expect_equal(rows$pcpn_status, "STALE")
  testthat::expect_equal(rows$tmean_status, "STALE")
  testthat::expect_true(is.na(rows$pcpn_30day_inches))
})
