make_climatology_test_raster <- function(values, dates) {
  raster <- terra::rast(
    ncols = 1, nrows = 1, nlyrs = length(dates),
    xmin = -112, xmax = -111.9583333333,
    ymin = 33, ymax = 33.0416666667,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- values
  terra::time(raster) <- as.Date(dates)
  raster
}

testthat::test_that("daily means group the same calendar day across years", {
  raster <- make_climatology_test_raster(
    c(40, 50, 60, 70),
    c("2019-01-01", "2019-01-02", "2020-01-01", "2020-01-02")
  )

  result <- prism_climatology_statistic(raster, "maxt", "mean", window_days = 1L)

  testthat::expect_equal(unname(terra::values(result)[, 1]), 50)
  testthat::expect_equal(unname(terra::values(result)[, 2]), 60)
  testthat::expect_equal(names(result), c("maxt_mean_01-01", "maxt_mean_01-02"))
})

testthat::test_that("leap day is interpolated and observed leap values are excluded", {
  raster <- make_climatology_test_raster(
    c(40, 60, 60, 999, 80),
    c("2019-02-28", "2019-03-01", "2020-02-28", "2020-02-29", "2020-03-01")
  )

  result <- prism_climatology_statistic(raster, "maxt", "mean", window_days = 1L)

  testthat::expect_equal(
    names(result),
    c("maxt_mean_02-28", "maxt_mean_02-29", "maxt_mean_03-01")
  )
  testthat::expect_equal(as.numeric(terra::values(result)), c(50, 60, 70))
})

testthat::test_that("precipitation wet frequency is a fraction", {
  raster <- make_climatology_test_raster(
    c(0, 0.04, 0.08),
    c("2018-07-01", "2019-07-01", "2020-07-01")
  )
  result <- prism_climatology_statistic(
    raster, "pcpn", "wet_frequency", window_days = 1L
  )

  testthat::expect_equal(as.numeric(terra::values(result)), 2 / 3)
  testthat::expect_equal(prism_climatology_units("pcpn", "wet_frequency"), "fraction")
  testthat::expect_error(
    prism_climatology_statistic(raster, "maxt", "wet_frequency"),
    "Unsupported"
  )
})

testthat::test_that("centered windows pool five calendar days across years", {
  raster <- make_climatology_test_raster(
    c(1:5, 11:15),
    c(
      "2019-01-01", "2019-01-02", "2019-01-03", "2019-01-04", "2019-01-05",
      "2020-01-01", "2020-01-02", "2020-01-03", "2020-01-04", "2020-01-05"
    )
  )

  result <- prism_climatology_statistic(raster, "maxt", "mean", window_days = 5L)
  jan03 <- match("maxt_mean_01-03", names(result))

  testthat::expect_equal(as.numeric(terra::values(result)[, jan03]), 8)
})

testthat::test_that("centered windows wrap across the end of the year", {
  raster <- make_climatology_test_raster(
    1:5,
    c("2019-12-30", "2019-12-31", "2020-01-01", "2020-01-02", "2020-01-03")
  )

  result <- prism_climatology_statistic(raster, "maxt", "mean", window_days = 5L)
  jan01 <- match("maxt_mean_01-01", names(result))

  testthat::expect_equal(as.numeric(terra::values(result)[, jan01]), 3)
})

testthat::test_that("temperature percentiles use R quantile type 8", {
  values <- c(1, 2, 3, 10, 20)
  raster <- make_climatology_test_raster(
    values,
    sprintf("%d-07-01", 2016:2020)
  )

  result <- prism_climatology_statistic(
    raster, "maxt", "p90", window_days = 1L, quantile_type = 8L
  )

  testthat::expect_equal(
    as.numeric(terra::values(result)),
    as.numeric(stats::quantile(values, 0.9, type = 8, names = FALSE))
  )
})

testthat::test_that("centered climatologies report bounded progress", {
  raster <- make_climatology_test_raster(
    c(40, 50),
    c("2019-01-01", "2019-01-02")
  )

  testthat::expect_message(
    prism_climatology_statistic(
      raster, "maxt", "mean", window_days = 1L,
      progress_every = 1L
    ),
    "calendar day 1/2"
  )
  testthat::expect_silent(
    prism_climatology_statistic(
      raster, "maxt", "mean", window_days = 1L,
      progress_every = 1L, quiet = TRUE
    )
  )
  testthat::expect_equal(format_prism_elapsed(10925), "3h 02m 05s")
})

testthat::test_that("precipitation percentiles use wet days only", {
  values <- c(0, 0.01, 0.039, 0.04, 0.10, 0.20)
  raster <- make_climatology_test_raster(
    values,
    sprintf("%d-07-01", 2015:2020)
  )

  result <- prism_climatology_statistic(
    raster, "pcpn", "wet_p90", wet_day_threshold = 0.04, quantile_type = 8L
  )

  testthat::expect_equal(
    as.numeric(terra::values(result)),
    as.numeric(stats::quantile(c(0.04, 0.10, 0.20), 0.9, type = 8, names = FALSE))
  )
  testthat::expect_equal(names(result), "pcpn_wet_p90")
  testthat::expect_error(
    prism_climatology_statistic(raster, "pcpn", "p90"),
    "Unsupported"
  )
})

testthat::test_that("wet-day percentiles can be calculated together in one pass", {
  values <- c(0, 0.01, 0.039, 0.04, 0.10, 0.20, 0.50)
  raster <- make_climatology_test_raster(
    values,
    sprintf("%d-07-01", 2014:2020)
  )

  result <- prism_wet_day_percentiles(
    raster,
    statistics = c("wet_p90", "wet_p95", "wet_p99"),
    wet_day_threshold = 0.04,
    quantile_type = 8L
  )
  expected <- stats::quantile(
    c(0.04, 0.10, 0.20, 0.50),
    probs = c(0.90, 0.95, 0.99),
    type = 8,
    names = FALSE
  )

  testthat::expect_equal(as.numeric(terra::values(result)), as.numeric(expected))
  testthat::expect_equal(
    names(result),
    c("pcpn_wet_p90", "pcpn_wet_p95", "pcpn_wet_p99")
  )
})

testthat::test_that("daily collection detects an incomplete baseline", {
  processed_dir <- tempfile("processed-")
  path <- file.path(processed_dir, "two-days.tif")
  dir.create(processed_dir, recursive = TRUE)
  terra::writeRaster(
    make_climatology_test_raster(c(40, 50), c("2020-01-01", "2020-01-03")),
    path,
    overwrite = TRUE
  )
  manifest <- data.frame(
    product = "daily", aoi_id = "az-nm-pad050", variable = "maxt",
    native_units = "degreeF", start_date = as.Date("2020-01-01"),
    end_date = as.Date("2020-01-03"), md5 = unname(tools::md5sum(path)), path = path
  )

  testthat::expect_error(
    read_prism_daily_collection(
      "maxt", "2020-01-01", "2020-01-03",
      processed_manifest = manifest,
      require_complete = TRUE
    ),
    "2020-01-02"
  )
})
