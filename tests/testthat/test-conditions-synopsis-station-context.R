source(file.path(project_root, "R/conditions-synopsis-evidence.R"))
source(file.path(project_root, "R/conditions-synopsis-template.R"))
source(file.path(project_root, "R/conditions-synopsis-station-context.R"))
synopsis_context_config <- function() synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))

synopsis_history_fixture <- function(root) {
  rows <- list()
  for (year in 1980:2027) {
    dates <- seq(as.Date(sprintf("%d-10-05", year)), as.Date(sprintf("%d-11-03", year)), by = "day")
    peak <- if (year == 2026) 1 else if (year == 2027) 50 else .1 + (year - 1980)/100
    for (variable in c("pcpn", "maxt", "mint")) rows[[length(rows)+1L]] <- data.frame(
      date = dates, variable = variable,
      numeric_value = switch(variable, pcpn = c(rep(.05, 29), peak), maxt = rep(if (year == 2026) 100 else 76, 30), mint = rep(50, 30)),
      observed = TRUE, flag = "", accumulated = FALSE, source = "fixture")
  }
  daily <- do.call(rbind, rows)
  dir.create(file.path(root, "data/processed/acis-stations/reference-network/daily"), recursive = TRUE)
  path <- file.path(root, "data/processed/acis-stations/reference-network/daily/1.rds")
  raw <- list(schema_version = 1L, uid = 1L, sid = "fixture", as_of = as.Date("2027-11-03"), daily = daily)
  saveRDS(raw, path)
  row <- data.frame(fact_id = "fixture", uid = 1L, window_days = 7L, metric = "max_daily_pcpn", value = 1,
    normal = NA_real_, sample_years = NA_real_)
  list(raw = raw, path = path, packet = list(candidates = row, selected = row), config = synopsis_context_config())
}

testthat::test_that("extreme references exclude current/future years and invalidate on historical revisions", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- synopsis_history_fixture(root)
  run <- function(packet = f$packet) synopsis_add_station_context(packet, root, as.Date("2026-11-03"), f$config, file.path(root, "context"))
  x <- run()$candidates
  testthat::expect_equal(x$historical_n, 46)
  testthat::expect_equal(x$historical_rank, 1)
  testthat::expect_equal(x$historical_last_year, 2025)
  testthat::expect_equal(x$context_normal_years, 30)
  testthat::expect_equal(x$context_normal, .355)
  testthat::expect_equal(x$peak_anomaly, .645)
  testthat::expect_equal(run()$candidates, x)
  revised <- f$raw
  revised$daily$numeric_value[revised$daily$variable == "pcpn" & revised$daily$date == as.Date("2010-11-03")] <- 2
  saveRDS(revised, f$path)
  changed <- run()$candidates
  testthat::expect_equal(changed$historical_rank, 2)
  testthat::expect_false(identical(changed$reference_signature, x$reference_signature))
  mismatch <- f$packet; mismatch$candidates$value <- 1.1
  testthat::expect_match(run(mismatch)$candidates$context_reason, "does not match")
})

testthat::test_that("historical quality checks, ties and cold-direction rankings are consistent", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- synopsis_history_fixture(root)
  selected <- f$raw$daily
  selected$accumulated[selected$variable == "pcpn" & selected$date == as.Date("1980-10-30")] <- TRUE
  stats <- synopsis_station_window_statistics(selected, as.Date(c("1980-11-03", "1981-11-03")), 7L)
  testthat::expect_true(is.na(stats$max_daily_pcpn[1]))
  testthat::expect_true(is.finite(stats$hottest_day[1]))
  tied <- data.frame(year = 1980:2005, hottest_day = c(rep(50, 24), 100, 100))
  x <- synopsis_context_statistics(100, tied, "hottest_day", f$config)
  testthat::expect_equal(x$historical_rank, 1)
  testthat::expect_equal(x$historical_ties, 3)
  cold <- data.frame(year = 1980:2005, coldest_night = rep(20, 26))
  x <- synopsis_context_statistics(0, cold, "coldest_night", f$config)
  testthat::expect_equal(x$historical_rank, 1)
  testthat::expect_equal(x$unusual_percentile, 100)
  testthat::expect_equal(x$peak_anomaly, -20)
  sparse <- synopsis_context_statistics(1, data.frame(year = 2000:2020, max_daily_pcpn = .5), "max_daily_pcpn", f$config)
  testthat::expect_equal(sparse$context_status, "INSUFFICIENT_REFERENCE")
  testthat::expect_true(is.na(sparse$historical_rank))
})

testthat::test_that("dry-spell comparisons measure runs inside the full window", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- synopsis_history_fixture(root)
  data <- f$raw$daily[f$raw$daily$date >= as.Date("2026-10-05") & f$raw$daily$date <= as.Date("2026-11-03"), ]
  data$numeric_value[data$variable == "pcpn"] <- c(rep(0, 24), rep(.1, 6))
  values <- synopsis_station_window_statistics(data, as.Date("2026-11-03"), 30L)
  testthat::expect_equal(values$longest_dry_spell, 24)
  testthat::expect_equal(values$max_3day_pcpn, .3)
  data$flag[data$variable == "pcpn" & data$date == as.Date("2026-10-15")] <- "A"
  testthat::expect_true(is.na(synopsis_station_window_statistics(data, as.Date("2026-11-03"), 30L)$longest_dry_spell))
})

testthat::test_that("readable dates retain cross-year and leap-day meaning", {
  testthat::expect_equal(synopsis_date_text("2026-11-01", year = FALSE), "November 1")
  testthat::expect_equal(synopsis_date_range("2026-10-28", "2026-11-03"), "Oct 28–Nov 3, 2026")
  testthat::expect_equal(synopsis_date_range("2026-12-28", "2027-01-03"), "Dec 28, 2026–Jan 3, 2027")
  testthat::expect_equal(synopsis_date_range("2028-02-27", "2028-02-29"), "Feb 27–29, 2028")
  testthat::expect_equal(synopsis_ordinal(11), "11th")
  testthat::expect_equal(synopsis_ordinal(23), "23rd")
})

testthat::test_that("editorial focus responds to weekly signals and withholds uncontextualized peaks", {
  config <- synopsis_context_config()
  rain <- data.frame(product = "pcpn_total_07day", region = "AZNM", metric = "mean", status = "AVAILABLE_CACHED", value = 1)
  temp <- data.frame(product = "tmean_departure_07day", region = "AZNM", metric = "mean_departure", status = "AVAILABLE_CACHED", value = 0)
  e <- list(configuration = config, recent = list(facts = rbind(rain, temp)), station_week = list(candidates = data.frame()))
  testthat::expect_equal(synopsis_week_profile(e)$mode, "rainfall")
  e$recent$facts$value <- c(.01, 4)
  testthat::expect_equal(synopsis_week_profile(e)$mode, "heat")
  e$recent$facts$value <- c(.01, -4)
  testthat::expect_equal(synopsis_week_profile(e)$mode, "cold")
  e$recent$facts$value <- c(.01, 0)
  testthat::expect_equal(synopsis_week_profile(e)$mode, "longer_term")
  e$recent$facts$status[2] <- "UNAVAILABLE"
  testthat::expect_equal(synopsis_week_profile(e)$mode, "uncertain")
  testthat::expect_equal(nrow(synopsis_unusual_candidates(data.frame(metric = "max_daily_pcpn", value = 5), config)), 0L)
})

testthat::test_that("rank prose names the extreme and counts the current period once", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- synopsis_history_fixture(root)
  packet <- synopsis_add_station_context(f$packet, root, as.Date("2026-11-03"), f$config, file.path(root, "context"))
  x <- packet$candidates
  x$name <- "Fixture station"; x$state <- "AZ"; x$event_start <- x$event_end <- "2026-11-03"; x$period_end <- "2026-11-03"
  sentence <- synopsis_station_sentence(x)
  testthat::expect_match(sentence, "on November 3")
  testthat::expect_match(sentence, "weekly wettest-day amount is the highest among 47 matching 7-day periods")
  testthat::expect_false(grepl("all-time|weekly total|season total|2026-11-03", sentence))
})
