for (file in c("acis-station-inventory", "acis-station-daily-pilot", "acis-station-current-prototype",
    "acis-station-explorer-prototype", "station-custom-dates-pilot")) source(file.path(project_root, "R", paste0(file, ".R")))

custom_cache_fixture <- function() {
  dates <- seq.Date(as.Date("2019-01-01"), as.Date("2020-01-02"), "day")
  raw <- do.call(rbind, lapply(c("pcpn", "maxt", "mint"), function(v) data.frame(date = dates, variable = v,
    numeric_value = if (v == "pcpn") 1 else if (v == "maxt") 70 else 40,
    observed = TRUE, flag = "", source = "fixture", trace = FALSE, accumulated = FALSE)))
  raw$numeric_value[raw$variable == "pcpn" & raw$date == as.Date("2019-01-01")] <- 0
  raw$trace[raw$variable == "pcpn" & raw$date == as.Date("2019-01-01")] <- TRUE
  raw$observed[raw$variable == "pcpn" & raw$date == as.Date("2020-01-01")] <- FALSE
  raw$flag[raw$variable == "pcpn" & raw$date == as.Date("2019-12-31")] <- "A"
  raw$numeric_value[raw$variable == "maxt" & raw$date == as.Date("2020-01-02")] <- 20
  list(schema_version = 1L, uid = 1L, sid = "fixture", as_of = max(dates), daily = raw)
}
custom_station_fixture <- function() data.frame(uid = 1L, sid = "fixture", name = "Fixture", state = "AZ", role = "fixed")

testthat::test_that("custom chunks preserve dates, traces, accumulated flags and inverted-temperature gaps", {
  station <- custom_station_fixture(); cache <- custom_cache_fixture()
  full <- acis_station_explorer_daily_detail(station, cache, cache$as_of, full_record = TRUE)
  recent <- acis_station_explorer_daily_detail(station, cache, cache$as_of)
  testthat::expect_equal(nrow(full$daily), 367L)
  testthat::expect_equal(nrow(recent$daily), 365L)
  a <- station_custom_chunk(station, cache, 2019L); b <- station_custom_chunk(station, cache, 2020L)
  testthat::expect_equal(a$pcpn_status[1], 2L)
  testthat::expect_equal(a$pcpn[1], 0)
  testthat::expect_equal(tail(a$pcpn_status, 1), 3L)
  testthat::expect_true(is.na(tail(a$pcpn, 1)))
  testthat::expect_identical(b$pcpn_status, c(0L, 1L))
  testthat::expect_equal(b$maxt_status[2], 3L)
  testthat::expect_equal(b$mint_status[2], 3L)
  result <- station_custom_summary(list(a, b), "2019-12-30", "2020-01-02")
  testthat::expect_equal(result$days, 4L)
  testthat::expect_equal(result$precipitation, 2)
  testthat::expect_equal(result$precipitation_valid, 2L)
  testthat::expect_equal(result$precipitation_flagged, 1L)
  testthat::expect_equal(result$paired_days, 3L)
  testthat::expect_equal(result$mean_temperature, 55)
})

testthat::test_that("warm, appended-date and older-revision builds touch only affected annual chunks", {
  old <- getwd(); setwd(project_root); on.exit(setwd(old), add = TRUE)
  root <- tempfile("custom-date-test-", tmpdir = "data/diagnostics"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  cache_dir <- file.path(root, "cache"); dir.create(cache_dir)
  output <- file.path(root, "preview"); station <- custom_station_fixture(); cache <- custom_cache_fixture()
  path <- file.path(cache_dir, "1.rds"); saveRDS(cache, path)
  a <- build_station_custom_dates_pilot(station, cache_dir, output)$summary
  testthat::expect_equal(a$built, 2L)
  b <- build_station_custom_dates_pilot(station, cache_dir, output)$summary
  testthat::expect_equal(b$built, 0L); testthat::expect_equal(b$reused, 2L)
  index <- readRDS(file.path(output, "history/1/build.rds"))
  old_2019 <- index$years$file[index$years$year == 2019L]
  extra <- cache$daily[cache$daily$date == cache$as_of, ]; extra$date <- extra$date + 1
  cache$daily <- rbind(cache$daily, extra); cache$as_of <- cache$as_of + 1; saveRDS(cache, path)
  c <- build_station_custom_dates_pilot(station, cache_dir, output)$summary
  testthat::expect_equal(c$built, 1L); testthat::expect_equal(c$reused, 1L)
  index <- readRDS(file.path(output, "history/1/build.rds"))
  testthat::expect_identical(index$years$file[index$years$year == 2019L], old_2019)
  cache$daily$numeric_value[cache$daily$date == as.Date("2019-07-01") & cache$daily$variable == "pcpn"] <- 5
  saveRDS(cache, path)
  d <- build_station_custom_dates_pilot(station, cache_dir, output)$summary
  testthat::expect_equal(d$built, 1L); testthat::expect_equal(d$reused, 1L)
  testthat::expect_length(list.files(file.path(output, "history/1"), pattern = "[.]json$"), 3L)
})
