source(file.path(project_root, "R", "acis-station-inventory.R"))

acis_test_record <- function(uid, sid, name, start, end, ll = NULL) {
  list(uid = uid, sids = list(sid), name = name, state = "AZ", ll = ll,
       valid_daterange = replicate(3L, list(start, end), simplify = FALSE))
}

testthat::test_that("metadata screening preserves ThreadEx without coordinates", {
  metadata <- list(
    acis_test_record(1L, "PHXthr 9", "Phoenix Area", "1895-01-01", "2026-09-01"),
    acis_test_record(2L, "USW00000001 6", "Long station", "1940-01-01",
                     "2026-09-01", list(-111, 34)),
    acis_test_record(3L, "US1AZXX0001 6", "Short station", "2010-01-01",
                     "2026-09-01", list(-111, 34))
  )
  candidates <- acis_station_candidates(metadata, today = as.Date("2026-09-29"))
  testthat::expect_equal(candidates$uid[candidates$selected], c(1L, 2L))
  testthat::expect_true(is.na(candidates$longitude[candidates$uid == 1L]))
  testthat::expect_equal(candidates$sid[candidates$uid == 1L], "PHXthr 9")
})

testthat::test_that("annual ACIS missing-day counts become explicit coverage", {
  station <- acis_station_candidates(list(acis_test_record(
    1L, "PHXthr 9", "Phoenix Area", "2019-01-01", "2020-12-31"
  )), today = as.Date("2021-01-01"))[1L, ]
  mock_fetch <- function(endpoint, params) {
    testthat::expect_equal(endpoint, "StnData")
    testthat::expect_equal(length(params$elems), 3L)
    list(data = list(
      list("2019", list("80", 0L), list("60", 10L), list("3", 0L)),
      list("2020", list("80", 37L), list("60", 0L), list("3", 0L))
    ))
  }
  coverage <- acis_station_annual_coverage(station, 2020L, mock_fetch)
  testthat::expect_equal(nrow(coverage), 6L)
  testthat::expect_equal(coverage$days[coverage$year == 2020L], rep(366L, 3L))
  testthat::expect_equal(coverage$observed_days[
    coverage$year == 2020L & coverage$variable == "maxt"], 329L)
  testthat::expect_error(acis_station_annual_coverage(
    station, 2020L, function(...) list(data = list())),
    "missing-day counts")
})

testthat::test_that("inventory caps requests and resumes from cached annual coverage", {
  calls <- 0L
  mock_fetch <- function(endpoint, params) {
    if (endpoint == "StnMeta") {
      if (!is.null(params$state)) return(list(meta = list(
        acis_test_record(1L, "PHXthr 9", "Phoenix Area", "2019-01-01", "2020-12-31"),
        acis_test_record(2L, "TUSthr 9", "Tucson Area", "2019-01-01", "2020-12-31")
      )))
      return(list(meta = list(acis_test_record(
        1L, "PHXthr 9", "Phoenix Area", "2019-01-01", "2020-12-31"
      ))))
    }
    calls <<- calls + 1L
    list(data = list(
      list("2019", list("80", 0L), list("60", 0L), list("3", 0L)),
      list("2020", list("80", 0L), list("60", 0L), list("3", 0L))
    ))
  }
  directory <- tempfile("acis-audit-")
  first <- run_acis_station_inventory(1L, today = as.Date("2021-01-01"),
                                      directory = directory, fetch = mock_fetch)
  testthat::expect_equal(first$audited_this_run, 1L)
  testthat::expect_equal(first$pending, 1L)
  second <- run_acis_station_inventory(1L, today = as.Date("2021-01-01"),
                                       directory = directory, fetch = mock_fetch)
  testthat::expect_equal(second$pending, 0L)
  testthat::expect_equal(calls, 2L)
  testthat::expect_equal(sum(second$shortlist$audit_status == "AUDITED"), 2L)
})
