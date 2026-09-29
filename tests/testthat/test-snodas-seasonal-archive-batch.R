source(file.path(project_root, "R", "snodas-seasonal-archive-batch.R"))

testthat::test_that("seasonal batch validates years and previews without building", {
  testthat::expect_equal(validate_snodas_seasonal_archive_years(
    c(2024, 2005, 2024)), c(2005L, 2024L))
  testthat::expect_error(validate_snodas_seasonal_archive_years(2026L),
                         "2005-2025")
  root <- tempfile("snodas-seasonal-preview-")
  result <- run_snodas_seasonal_archive_batch(
    c(2017L, 2024L), output_root = root, dry_run = TRUE,
    build_year = function(...) stop("should not build"))
  testthat::expect_null(result$results)
  testthat::expect_false(file.exists(result$log_path))
})

testthat::test_that("seasonal batch skips current years and bounds new attempts", {
  root <- tempfile("snodas-seasonal-batch-")
  dir.create(file.path(root, "wy2005"), recursive = TRUE)
  file.create(file.path(root, "wy2005", "complete.csv"))
  seen <- integer()
  builder <- function(water_year, output_dir, render_maps,
                      resume_partial) {
    seen <<- c(seen, water_year)
    if (water_year == 2007L) stop("synthetic failure")
    list(refreshed = water_year != 2005L,
         quality = data.frame(status = if (water_year == 2006L) {
           "REVIEW"
         } else "PASS", peak_max_inches = 52,
         peak_cells_for_review = 2L))
  }
  result <- run_snodas_seasonal_archive_batch(
    2005:2008, max_new_years = 2L, output_root = root,
    build_year = builder)
  testthat::expect_equal(seen, 2005:2007)
  testthat::expect_equal(result$results$event,
                         c("SKIPPED_CURRENT", "BUILT_REVIEW", "ERROR"))
  testthat::expect_true(result$limit_reached)
  testthat::expect_true(file.exists(result$log_path))
  testthat::expect_equal(nrow(utils::read.csv(result$log_path)), 3L)
})

testthat::test_that("seasonal batch detects partial grids for safe resume", {
  root <- tempfile("snodas-seasonal-partial-")
  year_dir <- file.path(root, "wy2017")
  dir.create(year_dir, recursive = TRUE)
  for (name in c("peak_swe.tif", "snow_days.tif", "coverage.tif")) {
    file.create(file.path(year_dir, name))
  }
  resumed <- FALSE
  builder <- function(water_year, output_dir, render_maps,
                      resume_partial) {
    resumed <<- resume_partial
    list(refreshed = TRUE,
         quality = data.frame(status = "PASS", peak_max_inches = 30,
                              peak_cells_for_review = 0L))
  }
  result <- run_snodas_seasonal_archive_batch(
    2017L, output_root = root, build_year = builder)
  testthat::expect_true(resumed)
  testthat::expect_equal(result$results$event, "BUILT_PASS")
})

testthat::test_that("rerunning a bounded batch advances past completed years", {
  root <- tempfile("snodas-seasonal-rerun-")
  builder <- function(water_year, output_dir, render_maps,
                      resume_partial) {
    marker <- file.path(output_dir, "complete.csv")
    current <- file.exists(marker)
    if (!current) {
      dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
      file.create(marker)
    }
    list(refreshed = !current,
         quality = data.frame(status = "PASS", peak_max_inches = 30,
                              peak_cells_for_review = 0L))
  }
  first <- run_snodas_seasonal_archive_batch(
    2005:2007, max_new_years = 1L, output_root = root,
    build_year = builder)
  second <- run_snodas_seasonal_archive_batch(
    2005:2007, max_new_years = 1L, output_root = root,
    build_year = builder)
  testthat::expect_equal(first$results$water_year, 2005L)
  testthat::expect_equal(second$results$water_year, c(2005L, 2006L))
  testthat::expect_equal(second$results$event,
                         c("SKIPPED_CURRENT", "BUILT_PASS"))
})
