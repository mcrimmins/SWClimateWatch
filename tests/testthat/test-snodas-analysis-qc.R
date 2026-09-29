source(file.path(project_root, "R", "snodas-analysis-qc.R"))

testthat::test_that("analysis screening excludes inconsistent cells only in memory", {
  date <- as.Date("2012-12-19")
  swe <- terra::rast(nrows = 2, ncols = 3, xmin = -111, xmax = -110,
                     ymin = 35, ymax = 36, crs = "EPSG:4326")
  depth <- swe
  terra::values(swe) <- c(0, 0.3, NA, 1, 0.1, 0.1)
  terra::values(depth) <- c(0, 0, 0.1, 2, -0.1, 0.2)
  terra::time(swe) <- date
  terra::time(depth) <- date
  result <- screen_snodas_analysis_pair(swe, depth)
  testthat::expect_equal(result$summary$swe_exceeds_depth_cells, 2L)
  testthat::expect_equal(result$summary$one_sided_missing_cells, 1L)
  testthat::expect_equal(result$summary$invalid_range_cells, 1L)
  testthat::expect_equal(result$summary$excluded_cells, 3L)
  testthat::expect_equal(as.vector(terra::values(result$swe)),
                         c(0, NA, NA, 1, NA, 0.1))
  testthat::expect_equal(as.vector(terra::values(result$depth)),
                         c(0, NA, NA, 2, NA, 0.2))
})

testthat::test_that("analysis screening refuses different dates or grids", {
  swe <- terra::rast(nrows = 1, ncols = 1, xmin = -111, xmax = -110,
                     ymin = 35, ymax = 36, crs = "EPSG:4326")
  terra::values(swe) <- 1
  terra::time(swe) <- as.Date("2024-02-15")
  depth <- swe
  terra::time(depth) <- as.Date("2024-02-16")
  testthat::expect_error(screen_snodas_analysis_pair(swe, depth),
                         "same daily date")
  terra::time(depth) <- terra::time(swe)
  shifted <- terra::shift(depth, dx = 1)
  testthat::expect_error(screen_snodas_analysis_pair(swe, shifted),
                         "same grid")
})
