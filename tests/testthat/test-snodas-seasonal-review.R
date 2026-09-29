source(file.path(project_root, "R", "snodas-seasonal-review.R"))

testthat::test_that("neighbor contrast distinguishes coherent from sharp peaks", {
  coherent <- rep(44, 25)
  coherent[13] <- 50.55118
  context <- snodas_peak_neighbor_context(coherent, 13L, 5L, 5L)
  testthat::expect_equal(context$neighbor_count, 8L)
  testthat::expect_equal(context$neighbor_median_inches, 44)
  testthat::expect_false(context$sharp_local_contrast)

  sharp <- rep(25, 25)
  sharp[13] <- 72.87402
  context <- snodas_peak_neighbor_context(sharp, 13L, 5L, 5L)
  testthat::expect_true(context$sharp_local_contrast)
  testthat::expect_gt(context$peak_to_neighbor_median, 2)

  sparse <- sharp
  sparse[c(7, 8, 9, 12, 14)] <- NA_real_
  context <- snodas_peak_neighbor_context(sparse, 13L, 5L, 5L)
  testthat::expect_true(context$limited_neighbor_context)
  testthat::expect_false(context$sharp_local_contrast)

  corner <- snodas_peak_neighbor_context(sharp, 1L, 5L, 5L)
  testthat::expect_equal(corner$neighbor_count, 3L)
  testthat::expect_true(corner$limited_neighbor_context)
})

testthat::test_that("review queue separates peak and coverage issues", {
  archive_dir <- tempfile("snodas-review-archive-")
  output_dir <- tempfile("snodas-review-output-")
  on.exit(unlink(c(archive_dir, output_dir), recursive = TRUE), add = TRUE)
  make_year <- function(year, center, neighbor, missing = 0L,
                        masked = 0L, with_audit = TRUE) {
    directory <- file.path(archive_dir, sprintf("wy%04d", year))
    dir.create(directory, recursive = TRUE)
    template <- terra::rast(nrows = 3L, ncols = 3L, xmin = -111,
                            xmax = -108, ymin = 33, ymax = 36,
                            crs = "EPSG:4326")
    values <- rep(neighbor, 9L)
    values[5L] <- center
    peak_path <- file.path(directory, "peak_swe.tif")
    terra::writeRaster(terra::setValues(template, values), peak_path)
    quality <- data.frame(
      water_year = year, source_signature = paste0("test-", year),
      status = "REVIEW", reasons = "diagnostic test",
      known_missing_days = missing,
      days_with_pairwise_exclusions = 0L, pairwise_excluded_cells = 0L,
      peak_cells_for_review = sum(values >= 50, na.rm = TRUE),
      peak_qc_masked_cells = masked
    )
    quality_path <- file.path(directory, "quality-summary.csv")
    utils::write.csv(quality, quality_path, row.names = FALSE)
    marker <- data.frame(
      source_signature = quality$source_signature,
      peak_swe_md5 = unname(tools::md5sum(peak_path)),
      quality_md5 = unname(tools::md5sum(quality_path))
    )
    utils::write.csv(marker, file.path(directory, "complete.csv"),
                     row.names = FALSE)
    if (with_audit && quality$peak_cells_for_review > 0L) {
      audit <- data.frame(
        source_signature = marker$source_signature,
        peak_swe_md5 = marker$peak_swe_md5,
        threshold_inches = 50, radius_days = 7L,
        high_peak_cells = quality$peak_cells_for_review
      )
      utils::write.csv(audit,
                       file.path(directory, "peak-provenance-summary.csv"),
                       row.names = FALSE)
      evidence <- data.frame(
        cell = 5L, map_peak_inches = center,
        peak_date = sprintf("%d-03-18", year),
        patch_id = 1L, patch_cells = 1L,
        nearby_valid_days = 14L, nearby_near_peak_fraction = 1,
        peak_difference_inches = 0
      )
      utils::write.csv(evidence,
                       file.path(directory, "peak-provenance-cells.csv"),
                       row.names = FALSE)
    }
    directory
  }
  coherent_dir <- make_year(2008L, 50.55118, 44, missing = 1L)
  make_year(2013L, 72.87402, 25)
  make_year(2014L, NA_real_, 25, masked = 1L)
  make_year(2016L, 53.18898, 38.05118)
  result <- build_snodas_seasonal_review_queue(
    c(2008L, 2013L, 2014L, 2016L, 2017L), archive_dir, output_dir)
  testthat::expect_equal(result$peaks$review_priority,
                         c("CHECK_SOURCE", "CHECK_CONTEXT",
                           "LOCALLY_COHERENT"))
  testthat::expect_equal(result$peaks$water_year,
                         c(2013L, 2016L, 2008L))
  testthat::expect_equal(result$peaks$peak_date[3L], "2008-03-18")
  testthat::expect_equal(result$peaks$patch_id, c(1L, 1L, 1L))
  testthat::expect_equal(result$years$known_missing_days[1L], 1L)
  testthat::expect_equal(result$years$documented_masked_cells[3L], 1L)
  testthat::expect_equal(result$years$peak_cells_50in[3L], 0L)
  testthat::expect_equal(result$years$archive_state[5L], "MISSING")
  testthat::expect_equal(result$years$archive_state[1L], "OUTPUTS_VERIFIED")
  testthat::expect_equal(
    result$years$isolated_moderate_contrast_cells[4L], 1L)
  testthat::expect_true(all(file.exists(result$paths)))

  audit_path <- file.path(coherent_dir, "peak-provenance-summary.csv")
  audit <- utils::read.csv(audit_path)
  audit$peak_swe_md5 <- "stale"
  utils::write.csv(audit, audit_path, row.names = FALSE)
  stale <- build_snodas_seasonal_review_queue(
    2008L, archive_dir, output_dir)
  testthat::expect_equal(stale$years$peak_audit_state, "MISSING_OR_STALE")
  testthat::expect_equal(stale$peaks$review_priority, "RUN_PEAK_AUDIT")
  testthat::expect_true(stale$peaks$provenance_needed)

  quality_path <- file.path(coherent_dir, "quality-summary.csv")
  cat("\n", file = quality_path, append = TRUE)
  unverified <- build_snodas_seasonal_review_queue(
    2008L, archive_dir, output_dir)
  testthat::expect_equal(unverified$years$archive_state, "UNVERIFIED")
  testthat::expect_true(is.na(unverified$years$peak_cells_50in))
  testthat::expect_equal(nrow(unverified$peaks), 0L)
})
