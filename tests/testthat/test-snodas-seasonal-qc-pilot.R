source(file.path(project_root, "R", "snodas-seasonal-qc-pilot.R"))

testthat::test_that("QC pilot distinguishes coherent, isolated and supported peaks", {
  template <- terra::rast(nrows = 5L, ncols = 5L, xmin = 0,
                          xmax = 5, ymin = 0, ymax = 5,
                          crs = "EPSG:4326")
  make_pair <- function(date, swe_values, depth_values) {
    swe <- terra::setValues(template, swe_values)
    depth <- terra::setValues(template, depth_values)
    terra::time(swe) <- as.Date(date)
    terra::time(depth) <- as.Date(date)
    list(swe = swe, depth = depth)
  }
  coherent <- rep(44, 25)
  coherent[13] <- 50.55
  isolated <- rep(25, 25)
  isolated[13] <- 72.87
  supported <- rep(25, 25)
  supported[c(13, 12, 17, 14)] <- c(60.67, 56.57, 46.06, 40)
  pairs <- list(
    `2008-03-18` = make_pair("2008-03-18", coherent, coherent * 2),
    `2014-04-07` = make_pair("2014-04-07", isolated, isolated * 2),
    `2005-05-19` = make_pair("2005-05-19", supported, supported * 2))
  peaks <- data.frame(
    water_year = c(2008L, 2014L, 2005L), cell = rep(13L, 3),
    peak_date = names(pairs), peak_swe_inches = c(50.55, 72.87, 60.67),
    patch_id = c(1L, 1L, 2L),
    sharp_local_contrast = c(FALSE, TRUE, TRUE),
    weak_temporal_support = rep(FALSE, 3),
    map_daily_mismatch = rep(FALSE, 3),
    provenance_needed = rep(FALSE, 3))
  checked <- snodas_qc_pilot_peaks(
    peaks, function(date) pairs[[as.character(date)]], c(40, 40, 45))
  testthat::expect_equal(checked$pilot_priority,
                         c("COHERENT_EXTREME", "REVIEW_EVENT", "CONTEXT_FLAG"))
  testthat::expect_equal(checked$same_day_supporting_neighbors,
                         c(8L, 0L, 2L))
  testthat::expect_true(checked$same_day_sharp_contrast[2L])
  testthat::expect_false(checked$density_contrast[2L])
  strict <- snodas_qc_pilot_peaks(
    peaks, function(date) pairs[[as.character(date)]], c(40, 40, 45),
    strict_spatial = TRUE)
  testthat::expect_equal(strict$pilot_priority,
                         c("COHERENT_EXTREME", "REVIEW_EVENT", "CONTEXT_FLAG"))
  testthat::expect_true(strict$strong_spatial_isolation[2L])
  testthat::expect_false(strict$strong_spatial_isolation[3L])

  checked$map_daily_mismatch[1L] <- TRUE
  changed <- snodas_qc_pilot_peaks(
    checked, function(date) pairs[[as.character(date)]], c(40, 40, 45))
  testthat::expect_equal(changed$pilot_priority[1L], "REVIEW_EVENT")
  events <- snodas_qc_pilot_events(checked)
  testthat::expect_equal(nrow(events), 3L)
  testthat::expect_equal(events$pilot_priority[1L], "REVIEW_EVENT")
})

testthat::test_that("QC pilot groups connected cells and preserves missing evidence", {
  peaks <- data.frame(
    water_year = c(2005L, 2005L, 2006L),
    cell = c(1L, 2L, 3L), patch_id = c(9L, 9L, NA_integer_),
    peak_date = c("2005-05-19", "2005-05-20", NA_character_),
    peak_swe_inches = c(60, 57, 51),
    pilot_priority = c("REVIEW_EVENT", "CONTEXT_FLAG", "NEEDS_EVIDENCE"))
  events <- snodas_qc_pilot_events(peaks)
  testthat::expect_equal(nrow(events), 2L)
  testthat::expect_equal(events$peak_cells[events$water_year == 2005L], 2L)
  testthat::expect_equal(events$peak_date_last[events$water_year == 2005L],
                         "2005-05-20")
  testthat::expect_equal(events$pilot_priority[1L], "NEEDS_EVIDENCE")
  episodes <- snodas_qc_pilot_episodes(events)
  testthat::expect_equal(nrow(episodes), 2L)
  testthat::expect_equal(
    episodes$flagged_patches[episodes$water_year == 2005L], 1L)
})

testthat::test_that("moderate isolated contrast stays context in strict triage", {
  template <- terra::rast(nrows = 3L, ncols = 3L, xmin = 0,
                          xmax = 3, ymin = 0, ymax = 3,
                          crs = "EPSG:4326")
  swe <- terra::setValues(template, c(25, 25, 25, 25, 45,
                                       25, 25, 25, 25))
  depth <- swe * 2
  peaks <- data.frame(
    water_year = 2005L, cell = 5L, peak_date = "2005-04-10",
    peak_swe_inches = 45, patch_id = 1L,
    sharp_local_contrast = TRUE, weak_temporal_support = FALSE,
    map_daily_mismatch = FALSE, provenance_needed = FALSE)
  strict <- snodas_qc_pilot_peaks(
    peaks, function(date) list(swe = swe, depth = depth),
    strict_spatial = TRUE)
  testthat::expect_equal(strict$same_day_supporting_neighbors, 0L)
  testthat::expect_false(strict$strong_spatial_isolation)
  testthat::expect_equal(strict$pilot_priority, "CONTEXT_FLAG")
})

testthat::test_that("snow-free neighbors count for SWE but not density", {
  template <- terra::rast(nrows = 3L, ncols = 3L, xmin = 0,
                          xmax = 3, ymin = 0, ymax = 3,
                          crs = "EPSG:4326")
  swe <- terra::setValues(template, c(0, 0, 0, 0, 20,
                                       0, 0, 0, 0))
  depth <- terra::setValues(template, c(0, 0, 0, 0, 40,
                                         0, 0, 0, 0))
  peaks <- data.frame(
    water_year = 2005L, cell = 5L, peak_date = "2005-04-10",
    peak_swe_inches = 20, patch_id = 1L,
    sharp_local_contrast = TRUE, weak_temporal_support = FALSE,
    map_daily_mismatch = FALSE, provenance_needed = FALSE)
  checked <- snodas_qc_pilot_peaks(
    peaks, function(date) list(swe = swe, depth = depth),
    strict_spatial = TRUE)
  testthat::expect_equal(checked$same_day_valid_neighbors, 8L)
  testthat::expect_equal(checked$same_day_neighbor_median_inches, 0)
  testthat::expect_equal(checked$same_day_supporting_neighbors, 0L)
  testthat::expect_true(is.na(checked$density_contrast))
  testthat::expect_equal(checked$pilot_priority, "CONTEXT_FLAG")
})

testthat::test_that("same-season flagged patches become date episodes", {
  events <- data.frame(
    water_year = rep(2005L, 4), patch_id = 1:4,
    peak_cells = c(2L, 1L, 3L, 1L),
    peak_date_first = c("2005-04-10", "2005-05-19",
                        "2005-05-20", "2005-05-25"),
    peak_date_last = c("2005-04-10", "2005-05-19",
                       "2005-05-21", "2005-05-25"),
    maximum_swe_inches = c(55, 60, 58, 51),
    pilot_priority = rep("REVIEW_EVENT", 4))
  episodes <- snodas_qc_pilot_episodes(events)
  testthat::expect_equal(nrow(episodes), 3L)
  testthat::expect_equal(episodes$flagged_patches, c(1L, 2L, 1L))
  testthat::expect_equal(episodes$end_date[2L], "2005-05-21")
})

testthat::test_that("unavailable daily evidence is queued rather than passed", {
  peaks <- data.frame(
    water_year = 2005L, cell = 1L, peak_date = "2005-05-19",
    peak_swe_inches = 60, patch_id = 1L,
    sharp_local_contrast = TRUE, weak_temporal_support = FALSE,
    map_daily_mismatch = FALSE, provenance_needed = FALSE)
  checked <- snodas_qc_pilot_peaks(peaks, function(date) {
    stop("source unavailable")
  })
  testthat::expect_equal(checked$pilot_priority, "NEEDS_EVIDENCE")
  testthat::expect_equal(snodas_qc_pilot_episodes(
    snodas_qc_pilot_events(checked))$pilot_priority,
    "NEEDS_EVIDENCE")
})
