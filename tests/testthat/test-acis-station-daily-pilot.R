source(file.path(project_root, "R", "acis-station-inventory.R"))
source(file.path(project_root, "R", "acis-station-daily-pilot.R"))

acis_daily_test_station <- function() {
  data.frame(
    uid = 42L, sid = "TEST 6", name = "Test Station", state = "AZ",
    role = "fixed", longitude = -111, latitude = 34, threadex = FALSE,
    audit_status = "AUDITED", maxt_start = "2020-01-01",
    mint_start = "2020-01-01", pcpn_start = "2020-01-01",
    maxt_normal_years_90pct = 30L, mint_normal_years_90pct = 30L,
    pcpn_normal_years_90pct = 30L, maxt_recent10_years_90pct = 10L,
    mint_recent10_years_90pct = 10L, pcpn_recent10_years_90pct = 10L
  )
}

acis_daily_test_fetch <- function(endpoint, params) {
  testthat::expect_equal(endpoint, "StnData")
  testthat::expect_equal(params$elems[[1L]]$add, "f,i")
  list(meta = list(uid = 42L), data = list(
    list("2020-01-01", list("60", " ", "A"), list("40", " ", "A"), list("0.00", " ", "A")),
    list("2020-01-02", list("M", " ", "M"), list("30", "P", "A"), list("0.00", "T", "A")),
    list("2020-01-03", list("M", " ", "M"), list("M", " ", "M"), list("0.10", "A", "B")),
    list("2020-01-04", list("50", " ", "B"), list("51", " ", "B"), list("M", " ", "M")),
    list("2020-01-05", list("50", " ", "B"), list("40", " ", "B"), list("0.02", " ", "B"))
  ))
}

testthat::test_that("daily pilot detects gaps, traces, flags, sources, and inversion", {
  station <- acis_daily_test_station()
  daily <- acis_station_daily_values(station, as.Date("2020-01-06"),
                                    acis_daily_test_fetch)
  output <- acis_station_daily_summaries(daily, station, as.Date("2020-01-06"))
  maxt <- output$summary[output$summary$variable == "maxt", ]
  pcpn <- output$summary[output$summary$variable == "pcpn", ]
  testthat::expect_equal(maxt$baseline_longest_gap_days, 2L)
  testthat::expect_equal(maxt$distinct_source_ids, 2L)
  testthat::expect_equal(maxt$source_id_transitions, 1L)
  testthat::expect_equal(pcpn$trace_days, 1L)
  testthat::expect_equal(pcpn$accumulated_days, 1L)
  testthat::expect_equal(output$checks$maxt_below_mint_days, 1L)
  testthat::expect_equal(sum(output$annual$missing_days), 4L)
  testthat::expect_equal(nrow(output$monthly), 3L)
})

testthat::test_that("daily pilot resumes without downloading stored daily data", {
  station <- acis_daily_test_station()
  station$role <- NULL
  directory <- tempfile("acis-daily-")
  dir.create(directory)
  shortlist_path <- file.path(directory, "shortlist.csv")
  write.csv(station, shortlist_path, row.names = FALSE)
  calls <- 0L
  fetch <- function(endpoint, params) {
    calls <<- calls + 1L
    acis_daily_test_fetch(endpoint, params)
  }
  output_dir <- file.path(directory, "pilot")
  first <- run_acis_station_daily_pilot(
    1L, today = as.Date("2020-01-06"), directory = output_dir,
    shortlist_path = shortlist_path,
    selection = data.frame(uid = 42L, role = "fixed", area = "Test"),
    fetch = fetch
  )
  second <- run_acis_station_daily_pilot(
    1L, today = as.Date("2020-01-06"), directory = output_dir,
    shortlist_path = shortlist_path,
    selection = data.frame(uid = 42L, role = "fixed", area = "Test"),
    fetch = fetch
  )
  testthat::expect_equal(first$audited_this_run, 1L)
  testthat::expect_equal(second$audited_this_run, 0L)
  testthat::expect_equal(calls, 1L)
  testthat::expect_true(file.exists(file.path(output_dir, "summary.csv")))
  testthat::expect_false(file.exists(file.path(output_dir, "daily-values.csv")))
})
