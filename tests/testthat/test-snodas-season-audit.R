source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "audit-snodas.R"))
source(file.path(project_root, "R", "snodas-quality-pilot.R"))
source(file.path(project_root, "R", "snodas-season-audit.R"))

testthat::test_that("processed-pair audit accepts integer Dates and checks both grids", {
  date <- structure(as.integer(as.Date("2024-02-15")), class = "Date")
  processed_dir <- tempfile("snodas-audit-grids-")
  for (variable in c("swe", "depth")) {
    grid <- terra::rast(nrows = 2, ncols = 2, xmin = -111, xmax = -110,
                        ymin = 35, ymax = 36, crs = "EPSG:4326")
    terra::values(grid) <- if (variable == "swe") {
      c(0, 1, 2, NA)
    } else c(0, 2, 3, NA)
    terra::time(grid) <- as.Date("2024-02-15")
    path <- snodas_processed_path(date, variable, processed_dir)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(grid, path)
  }
  quality <- snodas_audit_processed_pair(date, processed_dir)
  testthat::expect_equal(nrow(quality), 2L)
  testthat::expect_equal(unique(quality$valid_fraction), 0.75)
  testthat::expect_true(all(quality$swe_exceeds_depth_cells == 0L))
  testthat::expect_true(all(nzchar(quality$swe_md5)))
  testthat::expect_true(all(nzchar(quality$depth_md5)))

  depth_path <- snodas_processed_path(date, "depth", processed_dir)
  wrong <- terra::rast(nrows = 2, ncols = 2, xmin = -111, xmax = -110,
                       ymin = 35, ymax = 36, crs = "EPSG:4326")
  terra::values(wrong) <- c(0, 2, 3, NA)
  terra::time(wrong) <- as.Date("2024-02-16")
  terra::writeRaster(wrong, depth_path, overwrite = TRUE)
  testthat::expect_error(
    snodas_audit_processed_pair(date, processed_dir),
    "unexpected layers or date"
  )
})

testthat::test_that("geometry audit ignores roundoff but catches grid shifts", {
  geometry <- data.frame(
    source_rows = c(823L, 823L), source_cols = c(1579L, 1579L),
    source_xmin = c(-115.600416666665, -115.600416666665),
    source_ymax = c(37.6079166666663, 37.6079166666662),
    res_x = c(1 / 120, 1 / 120), res_y = c(1 / 120, 1 / 120)
  )
  testthat::expect_equal(snodas_geometry_variant_count(geometry), 1L)
  geometry$source_xmin[2L] <- geometry$source_xmin[2L] + 0.001
  testthat::expect_equal(snodas_geometry_variant_count(geometry), 2L)
  geometry$source_xmin[2L] <- geometry$source_xmin[1L]
  geometry$source_cols[2L] <- geometry$source_cols[1L] - 1L
  testthat::expect_equal(snodas_geometry_variant_count(geometry), 2L)
})
