source(file.path(project_root, "R", "snodas-seasonal-review.R"))
source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "snodas-relative-qc-pilot.R"))

testthat::test_that("relative screen finds sub-50 local spikes", {
  raster <- terra::rast(nrows = 5L, ncols = 5L, xmin = 0,
                        xmax = 5, ymin = 0, ymax = 5,
                        crs = "EPSG:4326")
  values <- rep(10, 25)
  values[13] <- 30
  candidates <- snodas_relative_peak_candidates(
    terra::setValues(raster, values))
  testthat::expect_equal(candidates$cell, 13L)
  testthat::expect_equal(candidates$peak_swe_inches, 30)
  testthat::expect_equal(candidates$neighbor_median_inches, 10)
  testthat::expect_equal(candidates$patch_cells, 1L)

  values[13] <- 18
  quiet <- snodas_relative_peak_candidates(
    terra::setValues(raster, values))
  testthat::expect_equal(nrow(quiet), 0L)
})

testthat::test_that("relative screen leaves coherent high snow alone", {
  raster <- terra::rast(nrows = 5L, ncols = 5L, xmin = 0,
                        xmax = 5, ymin = 0, ymax = 5,
                        crs = "EPSG:4326")
  values <- rep(44, 25)
  values[13] <- 50.55
  candidates <- snodas_relative_peak_candidates(
    terra::setValues(raster, values))
  testthat::expect_equal(nrow(candidates), 0L)
  testthat::expect_error(
    snodas_relative_peak_candidates(raster, contrast_ratio = 1),
    "Invalid SNODAS relative-peak inputs")
})

testthat::test_that("relative contrast excludes the focal cell", {
  raster <- terra::rast(nrows = 3L, ncols = 3L, xmin = 0,
                        xmax = 3, ymin = 0, ymax = 3,
                        crs = "EPSG:4326")
  values <- c(0, 0, 0, 0, 100, 100, 100, 100, 100)
  candidates <- snodas_relative_peak_candidates(
    terra::setValues(raster, values))
  testthat::expect_true(5L %in% candidates$cell)
  testthat::expect_equal(
    candidates$neighbor_median_inches[candidates$cell == 5L], 50)
})

testthat::test_that("known-mask benchmark reads unmodified daily peak", {
  processed_dir <- tempfile("snodas-relative-source-")
  on.exit(unlink(processed_dir, recursive = TRUE), add = TRUE)
  template <- terra::rast(nrows = 3L, ncols = 3L, xmin = 0,
                          xmax = 3, ymin = 0, ymax = 3,
                          crs = "EPSG:4326")
  for (date_text in c("2014-04-06", "2014-04-07")) {
    date <- as.Date(date_text)
    for (variable in c("swe", "depth")) {
      value <- if (date_text == "2014-04-07") 30 else 20
      if (variable == "depth") value <- value * 2
      raster <- terra::setValues(template, rep(value, 9L))
      terra::time(raster) <- date
      path <- snodas_processed_path(date, variable, processed_dir)
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      terra::writeRaster(raster, path)
    }
  }
  source <- snodas_relative_source_peak(
    2014L, matrix(c(1.5, 1.5), ncol = 2L), processed_dir)
  testthat::expect_equal(source$source_peak_inches, 30)
  testthat::expect_equal(source$source_depth_inches, 60)
  testthat::expect_equal(source$source_peak_date, "2014-04-07")
  testthat::expect_equal(source$valid_days, 2L)
})
