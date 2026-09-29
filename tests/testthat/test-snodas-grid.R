source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "snodas-grid.R"))

testthat::test_that("fixed common grid keeps centers inside the padded AOI", {
  target <- snodas_common_grid()
  testthat::expect_equal(c(terra::nrow(target), terra::ncol(target)),
                         c(822L, 1578L))
  bounds <- terra::ext(target)
  testthat::expect_equal(unname(c(bounds$xmin, bounds$xmax, bounds$ymin, bounds$ymax)),
                         unname(swc_region$bbox[c("west", "east", "south", "north")]),
                         tolerance = 1e-7)
})

testthat::test_that("nearest alignment preserves overlapping SWE values and time", {
  target <- terra::rast(nrows = 2, ncols = 3, xmin = 0, xmax = 3,
                        ymin = 0, ymax = 2, crs = "EPSG:4326")
  source <- terra::rast(nrows = 3, ncols = 4, xmin = -0.95, xmax = 3.05,
                        ymin = 0.05, ymax = 3.05, crs = "EPSG:4326")
  terra::values(source) <- 1:12
  terra::time(source) <- as.Date("2008-02-15")
  aligned <- snodas_align_common_grid(source, target)
  testthat::expect_true(terra::compareGeom(aligned, target,
                                            stopOnError = FALSE))
  testthat::expect_equal(as.vector(terra::values(aligned)),
                         c(6, 7, 8, 10, 11, 12))
  testthat::expect_equal(as.Date(terra::time(aligned)), as.Date("2008-02-15"))
  metrics <- snodas_alignment_metrics(source, aligned, target,
                                      as.Date("2008-02-15"))
  testthat::expect_equal(metrics$max_abs_roundtrip_difference_inches, 0)

  terra::values(target) <- 1:6
  testthat::expect_equal(as.vector(terra::values(
    snodas_align_common_grid(target, target))), 1:6)
})

testthat::test_that("unexpected source displacements are rejected", {
  target <- terra::rast(nrows = 2, ncols = 3, xmin = 0, xmax = 3,
                        ymin = 0, ymax = 2, crs = "EPSG:4326")
  shifted <- terra::rast(nrows = 2, ncols = 3, xmin = 0.3, xmax = 3.3,
                         ymin = 0, ymax = 2, crs = "EPSG:4326")
  testthat::expect_error(snodas_align_common_grid(shifted, target),
                         "displacement exceeds")
})
