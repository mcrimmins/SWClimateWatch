source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "audit-snodas.R"))
source(file.path(project_root, "R", "snodas-inventory.R"))
source(file.path(project_root, "R", "snodas-grid.R"))
source(file.path(project_root, "R", "snodas-quality-pilot.R"))

testthat::test_that("quality plan reuses pilot archives and verifies inventory", {
  raw_dir <- tempfile("snodas-quality-raw-")
  dir.create(file.path(raw_dir, "snodas", "pilot"), recursive = TRUE)
  pilot <- file.path(raw_dir, "snodas", "pilot", "SNODAS_20260923.tar")
  writeBin(as.raw(1L), pilot)
  inventory_path <- tempfile(fileext = ".csv")
  utils::write.csv(data.frame(
    month = "2012-04-01", checked_utc = "2026-09-25 00:00:00 UTC",
    listed_dates = "2012-04-15"), inventory_path, row.names = FALSE)
  plan <- plan_snodas_quality_pilot(
    as.Date(c("2012-04-15", "2026-09-23")),
    inventory_path = inventory_path, raw_dir = raw_dir
  )
  testthat::expect_equal(plan$download, c(TRUE, FALSE))
  testthat::expect_equal(plan$archive_path[2L], pilot)
  testthat::expect_error(plan_snodas_quality_pilot(
    as.Date("2012-04-16"), inventory_path = inventory_path,
    raw_dir = raw_dir), "not confirmed listed")
})

testthat::test_that("paired snow quality flags mismatches on a common grid", {
  swe <- terra::rast(nrows = 2, ncols = 3, xmin = 0, xmax = 3,
                     ymin = 0, ymax = 2, crs = "EPSG:4326")
  depth <- swe
  terra::values(swe) <- c(NA, 0, 1, 2, 0, 3)
  terra::values(depth) <- c(NA, 0, 2, 1, 1, 0)
  quality <- snodas_pair_quality(swe, depth, as.Date("2023-03-01"))
  testthat::expect_equal(quality$variable, c("swe", "depth"))
  testthat::expect_equal(quality$both_valid_fraction, rep(5 / 6, 2))
  testthat::expect_equal(quality$snow_cells_both_valid, rep(4L, 2))
  testthat::expect_equal(quality$swe_positive_depth_zero, rep(1L, 2))
  testthat::expect_equal(quality$depth_positive_swe_zero, rep(1L, 2))
  testthat::expect_equal(quality$swe_exceeds_depth_cells, rep(2L, 2))
  terra::ext(depth) <- terra::ext(1, 4, 0, 2)
  testthat::expect_error(snodas_pair_quality(swe, depth,
                                             as.Date("2023-03-01")),
                         "do not share a grid")
})
