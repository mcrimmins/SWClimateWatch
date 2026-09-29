source(file.path(project_root, "R", "snodas-seasonal-review.R"))
source(file.path(project_root, "R", "snodas-seasonal-qc-pilot.R"))
source(file.path(project_root, "R", "snodas-relative-qc-triage.R"))

testthat::test_that("relative daily evidence recovers peak and pairwise screen", {
  candidates <- data.frame(
    cell = c(1L, 2L), longitude = c(0.5, 1.5),
    latitude = c(0.5, 1.5), peak_swe_inches = c(30, 15))
  dates <- seq(as.Date("2014-04-01"), as.Date("2014-04-04"),
               by = "day")
  swe <- list(c(10, 12), c(25, 16), c(30, 20), c(29, 14))
  depth <- list(c(20, 24), c(50, 15), c(60, 19), c(58, 28))
  checked <- snodas_relative_daily_evidence(
    candidates, dates,
    function(date, points) {
      i <- match(date, dates)
      list(swe = swe[[i]], depth = depth[[i]])
    }, progress_every = 10L)
  testthat::expect_equal(checked$peak_date, c("2014-04-03", "2014-04-04"))
  testthat::expect_equal(checked$daily_peak_inches, c(30, 14))
  testthat::expect_equal(checked$source_valid_days, c(4L, 2L))
  testthat::expect_false(checked$map_daily_mismatch[1L])
  testthat::expect_true(checked$map_daily_mismatch[2L])
  testthat::expect_true(all(checked$weak_temporal_support))
})

testthat::test_that("missing daily evidence is not treated as a pass", {
  candidates <- data.frame(
    cell = 1L, longitude = 0.5, latitude = 0.5,
    peak_swe_inches = 30)
  checked <- snodas_relative_daily_evidence(
    candidates, as.Date("2014-04-01"),
    function(date, points) NULL)
  testthat::expect_true(checked$provenance_needed)
  testthat::expect_true(is.na(checked$peak_date))
  testthat::expect_equal(checked$source_valid_days, 0L)
})

testthat::test_that("one broad patch is split into dated review events", {
  peaks <- data.frame(
    water_year = c(2005L, 2005L), cell = c(1L, 2L),
    patch_id = c(9L, 9L),
    peak_date = c("2005-04-14", "2005-05-19"),
    peak_swe_inches = c(52, 60),
    pilot_priority = c("REVIEW_EVENT", "REVIEW_EVENT"))
  events <- snodas_qc_pilot_events(peaks, split_peak_date = TRUE)
  episodes <- snodas_qc_pilot_episodes(events)
  testthat::expect_equal(nrow(events), 2L)
  testthat::expect_equal(nrow(episodes), 2L)
  testthat::expect_equal(episodes$start_date,
                         c("2005-04-14", "2005-05-19"))
  testthat::expect_equal(episodes$end_date, episodes$start_date)
})
