testthat::test_that("Grid2 returns a readable dated PRISM GeoTIFF", {
  testthat::skip_if(
    Sys.getenv("SWC_LIVE_TESTS") != "true",
    "Set SWC_LIVE_TESTS=true to run RCC-ACIS integration tests."
  )

  temporary_raw <- tempfile("swc-live-raw-")
  plan <- plan_prism_download(
    mode = "bootstrap",
    variables = "maxt",
    start = as.Date("2020-01-15"),
    end = as.Date("2020-01-16"),
    raw_dir = temporary_raw
  )
  records <- download_prism_plan(
    plan,
    manifest_path = file.path(temporary_raw, "manifest.csv"),
    quiet = TRUE
  )

  testthat::expect_equal(nrow(records), 1L)
  testthat::expect_true(file.exists(records$path))
  raster <- terra::rast(records$path)
  extent <- as.vector(terra::ext(raster))
  testthat::expect_equal(terra::nlyr(raster), 2L)
  testthat::expect_lte(extent[1L], swc_region$bbox[["west"]])
  testthat::expect_gte(extent[2L], swc_region$bbox[["east"]])
  testthat::expect_lte(extent[3L], swc_region$bbox[["south"]])
  testthat::expect_gte(extent[4L], swc_region$bbox[["north"]])
  testthat::expect_equal(
    prism_geotiff_dates(records$path),
    as.Date(c("2020-01-15", "2020-01-16"))
  )
})
