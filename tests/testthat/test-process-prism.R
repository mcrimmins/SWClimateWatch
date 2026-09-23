make_test_prism_raster <- function(values = c(50, 55, 60, 65, 51, 56, 61, 66)) {
  raster <- terra::rast(
    ncols = 2, nrows = 2, nlyrs = 2,
    xmin = -112, xmax = -111.9166666667,
    ymin = 33, ymax = 33.0833333333,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- values
  terra::time(raster) <- as.Date(c("2020-01-01", "2020-01-02"))
  raster
}

testthat::test_that("daily reader attaches dates and native-unit names", {
  path <- tempfile(fileext = ".tif")
  terra::writeRaster(make_test_prism_raster(), path, overwrite = TRUE)

  raster <- read_prism_daily_raster(path, "maxt")

  testthat::expect_equal(as.Date(terra::time(raster)), as.Date(c("2020-01-01", "2020-01-02")))
  testthat::expect_equal(names(raster), c("maxt_2020-01-01", "maxt_2020-01-02"))
  testthat::expect_equal(range(terra::values(raster), na.rm = TRUE), c(50, 66))
})

testthat::test_that("native-unit validation rejects implausible values", {
  hot <- make_test_prism_raster(rep(200, 8))
  wet <- make_test_prism_raster(c(-1, rep(0, 7)))

  testthat::expect_error(validate_prism_native_values(hot, "maxt"), "outside")
  testthat::expect_error(validate_prism_native_values(wet, "pcpn"), "outside")
})

testthat::test_that("processed output retains values, dates, and geometry", {
  path <- tempfile(fileext = ".tif")
  raster <- make_test_prism_raster()
  names(raster) <- c("maxt_2020-01-01", "maxt_2020-01-02")

  write_prism_processed_raster(raster, path)
  result <- terra::rast(path)

  testthat::expect_true(terra::compareGeom(result, raster))
  testthat::expect_equal(as.Date(terra::time(result)), as.Date(terra::time(raster)))
  testthat::expect_equal(range(terra::values(result), na.rm = TRUE), c(50, 66))
})

testthat::test_that("processing plan rebuilds when the raw checksum changes", {
  raw_dir <- tempfile("raw-")
  processed_dir <- tempfile("processed-")
  raw_path <- file.path(
    raw_dir, "prism", "az-nm-pad050", "daily", "archive", "maxt", "test.tif"
  )
  dir.create(dirname(raw_path), recursive = TRUE)
  terra::writeRaster(make_test_prism_raster(), raw_path, overwrite = TRUE)
  raw_manifest <- data.frame(
    product = "daily", aoi_id = "az-nm-pad050", variable = "maxt",
    native_units = "degreeF", start_date = as.Date("2020-01-01"),
    end_date = as.Date("2020-01-02"), path = raw_path
  )

  first <- plan_prism_daily_processing(
    raw_manifest = raw_manifest,
    variables = "maxt",
    raw_dir = raw_dir,
    processed_dir = processed_dir,
    processed_manifest = data.frame()
  )
  testthat::expect_true(first$refresh)

  dir.create(dirname(first$path), recursive = TRUE)
  file.create(first$path)
  processed_manifest <- data.frame(path = first$path, source_md5 = first$source_md5)
  current <- plan_prism_daily_processing(
    raw_manifest = raw_manifest,
    variables = "maxt",
    raw_dir = raw_dir,
    processed_dir = processed_dir,
    processed_manifest = processed_manifest
  )
  testthat::expect_false(current$refresh)

  terra::writeRaster(make_test_prism_raster(rep(70, 8)), raw_path, overwrite = TRUE)
  changed <- plan_prism_daily_processing(
    raw_manifest = raw_manifest,
    variables = "maxt",
    raw_dir = raw_dir,
    processed_dir = processed_dir,
    processed_manifest = processed_manifest
  )
  testthat::expect_true(changed$refresh)
})

testthat::test_that("processing plan can use recorded checksums for fast recovery scans", {
  raw_dir <- tempfile("raw-")
  processed_dir <- tempfile("processed-")
  raw_path <- file.path(
    raw_dir, "prism", "az-nm-pad050", "daily", "update", "maxt", "test.tif"
  )
  dir.create(dirname(raw_path), recursive = TRUE)
  terra::writeRaster(make_test_prism_raster(), raw_path, overwrite = TRUE)
  recorded_md5 <- "0123456789abcdef0123456789abcdef"
  raw_manifest <- data.frame(
    product = "daily", aoi_id = "az-nm-pad050", variable = "maxt",
    native_units = "degreeF", start_date = as.Date("2020-01-01"),
    end_date = as.Date("2020-01-02"), md5 = recorded_md5, path = raw_path
  )

  missing_processed <- plan_prism_daily_processing(
    raw_manifest = raw_manifest,
    variables = "maxt",
    raw_dir = raw_dir,
    processed_dir = processed_dir,
    processed_manifest = data.frame(),
    verify_source_md5 = FALSE
  )
  testthat::expect_identical(missing_processed$source_md5, recorded_md5)
  testthat::expect_true(missing_processed$refresh)

  dir.create(dirname(missing_processed$path), recursive = TRUE)
  file.create(missing_processed$path)
  current <- plan_prism_daily_processing(
    raw_manifest = raw_manifest,
    variables = "maxt",
    raw_dir = raw_dir,
    processed_dir = processed_dir,
    processed_manifest = data.frame(
      path = missing_processed$path,
      source_md5 = recorded_md5
    ),
    verify_source_md5 = FALSE
  )
  testthat::expect_false(current$refresh)
})
