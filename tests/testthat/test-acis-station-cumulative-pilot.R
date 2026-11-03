source(file.path(project_root, "R", "acis-station-cumulative-pilot.R"))
cumulative_fixture <- function() {
  dates <- seq(as.Date("2022-10-01"), as.Date("2025-09-30"), by = "day")
  data.frame(date = dates, variable = "pcpn", numeric_value = 1,
    observed = TRUE, flag = "", trace = FALSE, accumulated = FALSE)
}

testthat::test_that("integrated cumulative build reuses history and detects revisions and missing files", {
  root <- tempfile("cumulative-site-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  station <- data.frame(uid = 1L, sid = "test", name = "Test", state = "AZ", role = "fixed")
  daily <- cumulative_fixture()
  cache <- list(uid = 1L, as_of = as.Date("2025-03-01"), daily = daily)
  build <- function(cache, date = as.Date("2025-03-02")) write_acis_station_cumulative_site(
    station, list(cache), date, root, file.path(root, "cache"),
    file.path(project_root, "scripts", "station-cumulative-assets"))
  first <- build(cache)
  testthat::expect_equal(first$historical_reused, 0L)
  second <- build(cache)
  testthat::expect_equal(second$historical_reused, 1L)
  path <- file.path(root, "cumulative", "1.json")
  payload <- jsonlite::read_json(path, simplifyVector = TRUE)
  testthat::expect_equal(payload$cache_as_of, "2025-03-01")
  testthat::expect_null(payload$current$total)
  testthat::expect_equal(payload$current$missing_days, 1L)
  testthat::expect_false(payload$closest_match$available)
  testthat::expect_invisible(validate_acis_station_cumulative_site(
    file.path(root, "cumulative"), 1L, "2025-03-02"))
  # Current-year revisions do not require rescreening complete historical years.
  cache$daily$numeric_value[cache$daily$date == as.Date("2025-02-01")] <- 2
  testthat::expect_equal(build(cache)$historical_reused, 1L)
  cache$daily$numeric_value[cache$daily$date == as.Date("2023-02-01")] <- 2
  testthat::expect_equal(build(cache)$historical_reused, 0L)
  unlink(file.path(root, "cumulative", "history", "1", "2023.json"))
  testthat::expect_error(validate_acis_station_cumulative_site(
    file.path(root, "cumulative"), 1L, "2025-03-02"), "comparison curve")
  build(NULL)
  payload <- jsonlite::read_json(path)
  testthat::expect_false(payload$available)
  testthat::expect_match(payload$note, "No daily station cache")
})

testthat::test_that("water-year accumulation includes leap-day rainfall without calendar drift", {
  daily <- cumulative_fixture()
  station <- data.frame(uid = 1L, sid = "test", name = "Test", state = "AZ", role = "fixed")
  cache <- list(uid = 1L, as_of = as.Date("2025-03-01"), daily = daily)
  payload <- acis_station_cumulative_payload(station, cache,
    baseline_water_years = 2023:2024, min_years = 2L)
  testthat::expect_equal(nrow(payload$points),365L)
  march <- payload$points[payload$points$month_day == "03-01", ]
  testthat::expect_equal(march$current,152)
  testthat::expect_equal(march$previous,153)
  testthat::expect_equal(march$normal,152.5)
  testthat::expect_equal(march$lower,152)
  testthat::expect_equal(march$upper,153)
  testthat::expect_equal(tail(payload$points$normal,1),365.5)
  testthat::expect_true(all(is.na(payload$points$current[payload$points$date > "2025-03-01"])))
  testthat::expect_equal(payload$baseline$sample_years,2L)
})

testthat::test_that("missing and flagged reports stop cumulative totals rather than filling zeros", {
  daily <- cumulative_fixture()
  daily$observed[daily$date == as.Date("2024-11-02")] <- FALSE
  daily$flag[daily$date == as.Date("2024-11-04")] <- "X"
  daily$accumulated[daily$date == as.Date("2024-11-05")] <- TRUE
  daily$numeric_value[daily$date == as.Date("2024-11-06")] <- -1
  curve <- acis_precipitation_water_year(daily,2025L,as.Date("2024-11-06"))
  testthat::expect_equal(curve$cumulative_inches[curve$date == as.Date("2024-11-01")],32)
  after_gap <- curve$date >= as.Date("2024-11-02")
  testthat::expect_true(all(is.na(curve$cumulative_inches[after_gap])))
  cutoff <- curve[curve$date == as.Date("2024-11-06"), ]
  testthat::expect_equal(cutoff$missing_days,1L)
  testthat::expect_equal(cutoff$flagged_days,3L)
  testthat::expect_equal(cutoff$observed_subtotal,33)
  testthat::expect_equal(curve$status[curve$date == as.Date("2024-11-07")],"FUTURE")
})

testthat::test_that("trace precipitation is usable zero and baseline sample support is explicit", {
  daily <- cumulative_fixture()
  daily$flag[daily$date == as.Date("2024-10-01")] <- "T"
  daily$trace[daily$date == as.Date("2024-10-01")] <- TRUE
  curve <- acis_precipitation_water_year(daily,2025L,as.Date("2024-10-02"))
  testthat::expect_equal(head(curve$cumulative_inches,2),c(0,1))
  testthat::expect_equal(curve$status[1],"TRACE")
  daily$observed[daily$date == as.Date("2023-05-15")] <- FALSE
  station <- data.frame(uid=1L,sid="test",name="Test",state="AZ",role="fixed")
  cache <- list(uid=1L,as_of=as.Date("2024-10-02"),daily=daily)
  payload <- acis_station_cumulative_payload(station,cache,
    baseline_water_years=2023:2024,min_years=2L)
  testthat::expect_false(payload$baseline$available)
  testthat::expect_equal(payload$baseline$sample_years,1L)
  testthat::expect_true(all(is.na(payload$points$normal)))
  testthat::expect_true(all(is.na(payload$points$lower)))
  testthat::expect_true(all(is.na(payload$points$upper)))
  testthat::expect_false(payload$baseline_audit$eligible[1])
  testthat::expect_true(payload$baseline_audit$eligible[2])
  testthat::expect_error(acis_station_cumulative_payload(station,cache,as.Date("2024-10-03")),"stale")
  testthat::expect_error(acis_precipitation_water_year(rbind(daily,daily[1,]),2023L),"Duplicate")
})

testthat::test_that("comparison years include only complete past water years with correct alignment", {
  daily <- cumulative_fixture()
  daily$observed[daily$date == as.Date("2023-05-15")] <- FALSE
  station <- data.frame(uid=1L,sid="test",name="Test",state="AZ",role="fixed")
  cache <- list(uid=1L,as_of=as.Date("2025-03-01"),daily=daily)
  history <- acis_station_cumulative_history(station,cache,2025L)
  testthat::expect_length(history$catalog,1L)
  testthat::expect_equal(history$catalog[[1]]$water_year,2024L)
  testthat::expect_equal(history$catalog[[1]]$file,"history/1/2024.json")
  testthat::expect_equal(history$curves[["2024"]]$annual_total,366)
  testthat::expect_length(history$curves[["2024"]]$values,365L)
  testthat::expect_equal(tail(history$curves[["2024"]]$values,1),366)
  testthat::expect_false(history$audit$eligible[history$audit$water_year==2023L])
  testthat::expect_false(any(history$audit$water_year==2025L))
})

testthat::test_that("unchanged comparison files are reused without rewriting", {
  path <- tempfile(fileext=".json")
  on.exit(unlink(path))
  testthat::expect_true(acis_cumulative_write_json(list(value=1),path))
  checksum <- tools::md5sum(path)
  testthat::expect_false(acis_cumulative_write_json(list(value=1),path))
  testthat::expect_identical(tools::md5sum(path),checksum)
  testthat::expect_true(acis_cumulative_write_json(list(value=2),path))
})

testthat::test_that("historical extremes identify years and closest match uses the full progression", {
  station <- data.frame(uid=1L,sid="test",name="Test",state="AZ",role="fixed")
  cache <- list(uid=1L,as_of=as.Date("2024-10-03"),daily=cumulative_fixture())
  payload <- acis_station_cumulative_payload(station,cache,baseline_water_years=2023:2024,min_years=1L)
  history <- list(curves=list(
    a=list(water_year=2023L,values=c(0,0,rep(3,363))),
    b=list(water_year=2024L,values=c(1,2,rep(2.9,363)))))
  result <- acis_cumulative_history_context(payload,history,min_history_years=1L)
  # 2023 matches the endpoint exactly, but 2024 follows the progression better.
  testthat::expect_equal(result$closest_match$water_year,2024L)
  testthat::expect_equal(result$closest_match$rmse_inches,sqrt(0.01/3))
  testthat::expect_equal(result$closest_match$days_compared,3L)
  testthat::expect_true(result$closest_match$early_season)
  testthat::expect_equal(result$points$high_years[1L],"2024")
  testthat::expect_equal(result$points$high_years[3L],"2023")
  testthat::expect_equal(result$historical_context$current_status,"TIED_HIGH")
  payload$points$current[3L] <- 3.5; payload$current$total <- 3.5
  high <- acis_cumulative_history_context(payload,history,min_history_years=1L)
  testthat::expect_equal(high$historical_context$current_status,"NEW_HIGH")
  testthat::expect_equal(acis_cumulative_record_status(0,1,3),"NEW_LOW")
  testthat::expect_equal(acis_cumulative_record_status(0,0,0),"TIED_BOTH")
  testthat::expect_equal(acis_cumulative_record_status(1+1e-8,0,1),"TIED_HIGH")
  testthat::expect_equal(acis_cumulative_record_status(NA_real_,0,1),"UNAVAILABLE")
})

testthat::test_that("cached references agree with a full calculation after advancing or revising current data", {
  station <- data.frame(uid = 1L, sid = "test", name = "Test", state = "AZ", role = "fixed")
  cache <- list(uid = 1L, as_of = as.Date("2024-10-03"), daily = cumulative_fixture())
  history <- list(curves = setNames(lapply(2001:2024, function(year)
    list(water_year = year, values = as.numeric(1:365) / (year - 1999))), as.character(2001:2024)))
  calculate <- function() acis_cumulative_history_context(acis_station_cumulative_payload(
    station, cache, baseline_water_years = 2023:2024, min_years = 1L), history)
  reference <- calculate()
  cache$as_of <- as.Date("2024-10-04")
  cache$daily$numeric_value[cache$daily$date == as.Date("2024-10-02")] <- 2
  cached <- acis_cumulative_refresh_current(reference, cache, cache$as_of, history)
  testthat::expect_equal(cached, calculate())
  cache$daily$observed[cache$daily$date == as.Date("2024-10-02")] <- FALSE
  cached <- acis_cumulative_refresh_current(reference, cache, cache$as_of, history)
  testthat::expect_equal(cached, calculate())
  testthat::expect_false(cached$closest_match$available)
})

testthat::test_that("match ties are deterministic, and incomplete or sparse histories are withheld", {
  station <- data.frame(uid=1L,sid="test",name="Test",state="AZ",role="fixed")
  cache <- list(uid=1L,as_of=as.Date("2024-10-03"),daily=cumulative_fixture())
  payload <- acis_station_cumulative_payload(station,cache,baseline_water_years=2023:2024,min_years=1L)
  history <- list(curves=list(a=list(water_year=2023L,values=as.numeric(1:365)),
    b=list(water_year=2024L,values=as.numeric(1:365))))
  result <- acis_cumulative_history_context(payload,history,min_history_years=1L)
  testthat::expect_equal(result$closest_match$tied_years,c(2024L,2023L))
  testthat::expect_equal(result$closest_match$water_year,2024L)
  testthat::expect_equal(result$points$high_years[1L],"2024,2023")
  testthat::expect_false(acis_cumulative_history_context(payload,history)$closest_match$available)
  payload$current$total <- NA_real_
  incomplete <- acis_cumulative_history_context(payload,history,min_history_years=1L)
  testthat::expect_false(incomplete$closest_match$available)
  testthat::expect_match(incomplete$closest_match$note,"incomplete")
})
