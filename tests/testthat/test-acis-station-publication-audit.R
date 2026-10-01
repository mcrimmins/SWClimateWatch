source(file.path(project_root, "R", "acis-station-explorer-prototype.R"))
source(file.path(project_root, "R", "acis-station-publication-audit.R"))

testthat::test_that("publication gate separates evidence, availability and review", {
  rows <- data.frame(
    uid = 1:2, sid = c("A 6", "B 9"), name = c("Fixed", "ThreadEx"),
    state = "AZ", role = c("fixed", "threadex"),
    longitude = c(-111, NA), latitude = c(34, NA),
    as_of = "2026-09-30", cache_as_of = "2026-09-30",
    period = "30day", period_days = 30L,
    pcpn_value = c(1, NA), tmean_value = c(75, 70),
    pcpn_anomaly = c(0.2, NA), tmean_anomaly = c(1, -2),
    pcpn_percentile = c(70, NA), tmean_percentile = c(80, 50),
    pcpn_status = c("AVAILABLE", "INCOMPLETE"),
    tmean_status = c("AVAILABLE", "AVAILABLE"),
    pcpn_missing_days = c(0L, 1L), tmean_missing_days = 0L,
    pcpn_flagged_days = 0L, tmean_flagged_days = 0L,
    pcpn_normal_years = c(25L, 25L), tmean_normal_years = c(25L, 15L),
    pcpn_reference_years = c(35L, 35L),
    tmean_reference_years = c(35L, 25L))
  quality <- expand.grid(uid = 1:2, variable = c("maxt", "mint", "pcpn"),
                         KEEP.OUT.ATTRS = FALSE)
  quality$as_of <- "2026-09-28"
  quality$baseline_coverage <- 0.9
  quality$recent10_coverage <- 0.95
  quality$latest_lag_days <- 0L
  quality$baseline_longest_gap_days <- 5L
  quality$recent10_longest_gap_days <- 2L
  quality$special_flag_days <- 0L
  quality$accumulated_days <- 0L
  quality$source_id_transitions <- 1L
  quality$distinct_source_ids <- 2L
  checks <- data.frame(uid = 1:2, maxt_below_mint_days = 0L,
                       negative_pcpn_days = 0L)
  reviews <- data.frame(uid = c(1L, 1L, 2L, 2L),
                        variable = c("pcpn", "tmean", "pcpn", "tmean"),
                        decision = c("APPROVE", "APPROVE", "EXCLUDE", "CAVEAT"),
                        note = c("", "", "Missing days", "Limited history"))
  audit <- audit_acis_station_publication(rows, quality, checks, reviews)
  testthat::expect_equal(nrow(audit$products), 12L)
  testthat::expect_equal(sum(audit$summary$station_count), 12L)
  testthat::expect_equal(nrow(audit$quality_context), 4L)
  testthat::expect_true(all(audit$quality_context$quality_audit_age_days == 2L))
  get_status <- function(uid, metric) audit$products$publication_status[
    audit$products$uid == uid & audit$products$metric == metric]
  testthat::expect_equal(get_status(1L, "pcpn_anomaly"), "DISPLAY")
  testthat::expect_equal(get_status(2L, "pcpn_value"), "HIDE_UNAVAILABLE")
  testthat::expect_equal(get_status(2L, "tmean_value"), "DISPLAY_CAUTION")
  testthat::expect_equal(get_status(2L, "tmean_anomaly"), "DISPLAY_CAUTION")
  testthat::expect_equal(get_status(2L, "tmean_percentile"), "DISPLAY_CAUTION")
  testthat::expect_true(grepl("LIMITED_NORMAL_SAMPLE",
    audit$products$caution_codes[audit$products$uid == 2 &
      audit$products$metric == "tmean_anomaly"]))
  automatic <- audit_acis_station_publication(rows, quality, checks)
  testthat::expect_equal(automatic$products$publication_status[
    automatic$products$uid == 1 & automatic$products$metric == "pcpn_value"],
    "DISPLAY")
  relaxed <- rows
  relaxed$pcpn_value[[2L]] <- 0.8
  relaxed$pcpn_status[[2L]] <- "PROVISIONAL"
  relaxed$tmean_status[[1L]] <- "PARTIAL"
  relaxed$tmean_missing_days[[1L]] <- 1L
  provisional <- audit_acis_station_publication(relaxed, quality, checks)
  product <- function(selected_uid, selected_metric) provisional$products[
    provisional$products$uid == selected_uid &
      provisional$products$metric == selected_metric, , drop = FALSE]
  testthat::expect_equal(product(2L, "pcpn_value")$publication_status,
                         "DISPLAY_CAUTION")
  testthat::expect_match(product(2L, "pcpn_value")$caution_codes,
                         "PROVISIONAL_PRECIP")
  testthat::expect_equal(product(2L, "pcpn_anomaly")$publication_status,
                         "HIDE_UNAVAILABLE")
  testthat::expect_equal(product(1L, "tmean_value")$publication_status,
                         "DISPLAY_CAUTION")
  testthat::expect_match(product(1L, "tmean_value")$caution_codes,
                         "PARTIAL_TEMPERATURE")
  near_complete <- rows
  near_complete$tmean_status[[1L]] <- "NEAR_COMPLETE"
  near_complete$tmean_missing_days[[1L]] <- 1L
  near_audit <- audit_acis_station_publication(near_complete, quality, checks)
  near_product <- near_audit$products[
    near_audit$products$uid == 1L &
      near_audit$products$metric == "tmean_value", , drop = FALSE]
  testthat::expect_equal(near_product$publication_status, "DISPLAY")
  testthat::expect_error(audit_acis_station_publication(
    rows, quality, checks, reviews[c(1, 1), ]), "Invalid station review")
  testthat::expect_error(audit_acis_station_publication(
    rows, quality, checks, transform(reviews, note = "")), "Invalid station review")
})
