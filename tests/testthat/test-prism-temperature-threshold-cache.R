make_temperature_threshold_cache_test_raster <- function(value, date) {
  raster <- terra::rast(
    ncols = 1, nrows = 1, nlyrs = length(value),
    xmin = -112, xmax = -111.9583333333,
    ymin = 33, ymax = 33.0416666667,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- value
  terra::time(raster) <- as.Date(date)
  names(raster) <- paste("mint", format(as.Date(date)), sep = "_")
  raster
}

make_temperature_threshold_cache_fixture <- function() {
  processed_dir <- tempfile("temperature-threshold-cache-")
  dates <- as.Date(c(
    "2019-06-29", "2019-06-30", "2019-07-01",
    "2020-06-29", "2020-06-30", "2020-07-01"
  ))
  values <- c(31, 33, 30, 40, 35, 31)
  paths <- file.path(
    processed_dir, "prism", "az-nm-pad050", "daily", "archive", "mint",
    paste0(format(dates), ".tif")
  )
  for (index in seq_along(paths)) {
    dir.create(dirname(paths[[index]]), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(
      make_temperature_threshold_cache_test_raster(values[[index]], dates[[index]]),
      paths[[index]], overwrite = TRUE
    )
  }
  manifest <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    variable = "mint",
    native_units = "degreeF",
    start_date = dates,
    end_date = dates,
    processed_at = rep("2026-09-13 12:00:00 UTC", length(dates)),
    md5 = unname(tools::md5sum(paths)),
    path = paths,
    stringsAsFactors = FALSE
  )
  list(processed_dir = processed_dir, manifest = manifest)
}

testthat::test_that("freeze-count cache paths encode threshold, method, and baseline", {
  path <- prism_freeze_count_cache_path(
    30L, "2026-09-09", 32, "1991-01-01", "2020-12-31", window_days = 5L
  )
  testthat::expect_match(path, "19910101-20201231", fixed = TRUE)
  testthat::expect_match(path, "freeze-at-or-below-32F", fixed = TRUE)
  testthat::expect_match(path, file.path("030day", "centered-05day", "09-09.tif"), fixed = TRUE)
})

testthat::test_that("rolling threshold counts use exact sliding-window updates", {
  dates <- as.Date("2020-01-01") + 0:6
  indicator <- make_temperature_threshold_cache_test_raster(
    c(1, 0, 1, 1, 0, 0, 1), dates
  )
  counts <- prism_rolling_counts_for_end_dates(
    indicator, dates, dates[3:7], 3L, quiet = TRUE
  )
  testthat::expect_equal(as.numeric(terra::values(counts)), c(2, 2, 2, 1, 1))
  testthat::expect_equal(as.Date(terra::time(counts)), dates[3:7])
})

testthat::test_that("freeze-count samples are cached and reused", {
  fixture <- make_temperature_threshold_cache_fixture()
  cache_manifest <- file.path(fixture$processed_dir, "cache-manifest.csv")
  first <- build_prism_freeze_count_cache(
    days = 3L,
    target_date = "2026-07-01",
    baseline_start = "2019-07-01",
    baseline_end = "2020-07-01",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )
  second <- build_prism_freeze_count_cache(
    days = 3L,
    target_date = "2026-07-01",
    baseline_start = "2019-07-01",
    baseline_end = "2020-07-01",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )

  testthat::expect_true(first$refreshed)
  testthat::expect_false(second$refreshed)
  testthat::expect_equal(as.numeric(terra::values(first$raster)), c(2, 1))
  testthat::expect_identical(
    as.numeric(terra::values(first$raster)),
    as.numeric(terra::values(second$raster))
  )
  testthat::expect_equal(unique(terra::datatype(second$raster)), "FLT4S")
  testthat::expect_equal(
    as.Date(terra::time(first$raster)),
    as.Date(c("2019-07-01", "2020-07-01"))
  )
  manifest <- read_prism_manifest(cache_manifest)
  testthat::expect_equal(nrow(manifest), 1L)
  testthat::expect_equal(manifest$sample_layers, 2L)
})
