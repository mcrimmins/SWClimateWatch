source(file.path(project_root, "R", "acis-station-inventory.R"))
source(file.path(project_root, "R", "acis-station-daily-pilot.R"))
source(file.path(project_root, "R", "acis-station-reference-network.R"))
source(file.path(project_root, "R", "acis-station-reference-daily-audit.R"))

reference_daily_record <- function(uid, sid, name, longitude) {
  list(uid = uid, sids = list(sid), name = name, state = "AZ",
       ll = list(longitude, 34),
       valid_daterange = replicate(3L, list("2026-09-26", "2026-09-28"),
                                   simplify = FALSE))
}

testthat::test_that("reference aliases are audited once per ACIS UID", {
  metadata <- list(
    reference_daily_record(1L, "001111 2", "Station one", -111),
    reference_daily_record(2L, "002222 2", "Station two", -110)
  )
  network <- data.frame(
    acis_uid = c(1L, 1L, 2L),
    reference_id = c("001111", "001112", "002222"),
    annual_audit = "AUDITED"
  )
  stations <- acis_reference_daily_stations(network, metadata)
  testthat::expect_equal(nrow(stations), 2L)
  testthat::expect_equal(stations$reference_ids, c("001111,001112", "002222"))
  testthat::expect_equal(stations$role, c("fixed", "fixed"))
})

testthat::test_that("broad daily review is capped, resumable, and stores summaries", {
  directory <- tempfile("acis-reference-daily-")
  dir.create(file.path(directory, "reference-network"), recursive = TRUE)
  metadata <- list(
    reference_daily_record(1L, "001111 2", "Station one", -111),
    reference_daily_record(2L, "002222 2", "Station two", -110)
  )
  saveRDS(metadata, file.path(directory, "metadata.rds"))
  write.csv(data.frame(
    acis_uid = c(1L, 1L, 2L),
    reference_id = c("001111", "001112", "002222"),
    annual_audit = "AUDITED"
  ), file.path(directory, "reference-network", "network.csv"), row.names = FALSE)
  calls <- 0L
  mock_fetch <- function(endpoint, params) {
    calls <<- calls + 1L
    testthat::expect_equal(endpoint, "StnData")
    list(data = lapply(26:28, function(day) {
      list(sprintf("2026-09-%02d", day),
           list("80", "", "1"), list("50", "", "1"),
           list("0.10", "", "1"))
    }))
  }
  first <- run_acis_reference_daily_audit(1L, today = as.Date("2026-09-29"),
                                          directory = directory, fetch = mock_fetch)
  testthat::expect_length(first$failures, 0L)
  testthat::expect_equal(first$pending, 1L)
  testthat::expect_equal(first$audited_this_run, 1L)
  second <- run_acis_reference_daily_audit(2L, today = as.Date("2026-09-29"),
                                           directory = directory, fetch = mock_fetch)
  testthat::expect_equal(second$pending, 0L)
  testthat::expect_equal(calls, 2L)
  testthat::expect_true(all(second$stations$daily_status == "AUDITED"))
  summary <- read.csv(file.path(second$directory, "summary.csv"))
  testthat::expect_equal(nrow(summary), 6L)
  testthat::expect_true(all(summary$latest_observed == "2026-09-28"))
  testthat::expect_equal(length(list.files(file.path(second$directory,
                                                 "station-summaries"))), 2L)
})
