make_wet_day_intensity_test_raster <- function(value, date) {
  raster <- terra::rast(
    ncols = 1, nrows = 1,
    xmin = -112, xmax = -111.9583333333,
    ymin = 33, ymax = 33.0416666667,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- value
  terra::time(raster) <- as.Date(date)
  names(raster) <- paste("pcpn", format(as.Date(date)), sep = "_")
  raster
}

make_wet_day_intensity_fixture <- function() {
  processed_dir <- tempfile("wet-day-intensity-")
  dates <- c(
    seq(as.Date("2019-06-28"), as.Date("2019-07-02"), by = "day"),
    seq(as.Date("2020-06-28"), as.Date("2020-07-02"), by = "day")
  )
  values <- c(0.01, 0.04, 0.08, 0, 0.12, 0.1, 0.2, 0, 0, 0.3)
  paths <- file.path(
    processed_dir, "prism", "az-nm-pad050", "daily", "archive", "pcpn",
    paste0(format(dates), ".tif")
  )
  for (index in seq_along(paths)) {
    dir.create(dirname(paths[[index]]), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(
      make_wet_day_intensity_test_raster(values[[index]], dates[[index]]),
      paths[[index]], overwrite = TRUE
    )
  }
  manifest <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    variable = "pcpn",
    native_units = "inch",
    start_date = dates,
    end_date = dates,
    processed_at = rep("2026-09-16 12:00:00 UTC", length(dates)),
    md5 = unname(tools::md5sum(paths)),
    path = paths,
    stringsAsFactors = FALSE
  )
  list(processed_dir = processed_dir, manifest = manifest)
}

testthat::test_that("wet-day intensity excludes sub-threshold precipitation", {
  testthat::expect_equal(
    prism_mean_wet_day_intensity(c(0.01, 0.04, 0.08, 0), 0.04),
    0.06
  )
  testthat::expect_true(is.na(
    prism_mean_wet_day_intensity(c(0, 0.01, 0.039), 0.04)
  ))
  testthat::expect_true(is.na(
    prism_mean_wet_day_intensity(c(0.04, NA, 0.08), 0.04)
  ))
})

testthat::test_that("wet-day intensity honors the minimum wet-day count", {
  testthat::expect_true(is.na(
    prism_mean_wet_day_intensity(c(0, 0.05, 0), 0.04, minimum_wet_days = 2L)
  ))
  testthat::expect_equal(
    prism_mean_wet_day_intensity(c(0.04, 0.08, 0), 0.04, minimum_wet_days = 2L),
    0.06
  )
})

testthat::test_that("wet-day intensity is exact within its moving window", {
  dates <- seq(as.Date("2026-06-01"), by = "day", length.out = 4L)
  raster <- do.call(c, lapply(seq_along(dates), function(index) {
    make_wet_day_intensity_test_raster(c(0.01, 0.04, 0.08, 0)[[index]], dates[[index]])
  }))
  terra::time(raster) <- dates
  result <- prism_wet_day_intensity_from_raster(
    raster, max(dates), duration_days = 4L
  )
  testthat::expect_equal(as.numeric(terra::values(result)), 0.06, tolerance = 1e-8)
})

testthat::test_that("wet-day-intensity cache is written and reused", {
  fixture <- make_wet_day_intensity_fixture()
  manifest_path <- file.path(fixture$processed_dir, "wet-day-intensity-manifest.csv")
  first <- build_prism_wet_day_intensity_cache(
    "2026-07-01", duration_days = 4L,
    baseline_start = "2019-01-01", baseline_end = "2020-12-31",
    window_days = 1L, processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest, manifest_path = manifest_path,
    quiet = TRUE
  )
  reuse <- build_prism_wet_day_intensity_cache(
    "2026-07-01", duration_days = 4L,
    baseline_start = "2019-01-01", baseline_end = "2020-12-31",
    window_days = 1L, processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest, manifest_path = manifest_path,
    quiet = TRUE
  )
  testthat::expect_equal(
    as.numeric(terra::values(first$raster)),
    c(0.06, 0.15),
    tolerance = 1e-8
  )
  testthat::expect_true(first$refreshed)
  testthat::expect_false(reuse$refreshed)
  manifest <- read_prism_manifest(manifest_path)
  testthat::expect_equal(manifest$duration_days, 4)
  testthat::expect_equal(manifest$minimum_wet_days, 1)
})

testthat::test_that("wet-day-intensity percentile uses the empirical baseline", {
  current <- make_wet_day_intensity_test_raster(0.1, "2026-07-01")
  reference <- do.call(c, lapply(c(0.05, 0.15), function(value) {
    make_wet_day_intensity_test_raster(value, as.Date("2018-07-01") + round(value * 100))
  }))
  rank <- prism_wet_day_intensity_percentile_rank_raster(
    current, reference, 90L, "2026-07-01"
  )
  testthat::expect_equal(as.numeric(terra::values(rank)), 50)
})

testthat::test_that("wet-day-intensity cache advances incrementally", {
  fixture <- make_wet_day_intensity_fixture()
  manifest_path <- file.path(fixture$processed_dir, "wet-day-intensity-manifest.csv")
  build_prism_wet_day_intensity_cache(
    "2026-07-01", duration_days = 4L,
    baseline_start = "2019-01-01", baseline_end = "2020-12-31",
    window_days = 1L, processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest, manifest_path = manifest_path,
    quiet = TRUE
  )
  incremental <- build_prism_wet_day_intensity_cache(
    "2026-07-02", duration_days = 4L,
    baseline_start = "2019-01-01", baseline_end = "2020-12-31",
    window_days = 1L, processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest, manifest_path = manifest_path,
    quiet = TRUE
  )
  incremental_values <- as.numeric(terra::values(incremental$raster))
  direct <- build_prism_wet_day_intensity_cache(
    "2026-07-02", duration_days = 4L,
    baseline_start = "2019-01-01", baseline_end = "2020-12-31",
    window_days = 1L, processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest, manifest_path = manifest_path,
    overwrite = TRUE, allow_incremental = FALSE, quiet = TRUE
  )

  testthat::expect_identical(incremental$build_method, "incremental")
  testthat::expect_equal(incremental_values, c(0.08, 0.25), tolerance = 1e-8)
  testthat::expect_equal(
    incremental_values,
    as.numeric(terra::values(direct$raster)),
    tolerance = 1e-8
  )
})

testthat::test_that("wet-day-intensity paths and maps use stable conventions", {
  cache_path <- prism_wet_day_intensity_cache_path(
    "2026-09-09", 90L, processed_dir = "processed"
  )
  testthat::expect_match(cache_path, "090day", fixed = TRUE)
  testthat::expect_match(cache_path, "wet-004in", fixed = TRUE)
  testthat::expect_match(cache_path, "minimum-01-wet-days", fixed = TRUE)
  testthat::expect_match(
    prism_wet_day_intensity_map_path("percentile-rank"),
    "pcpn-wet-day-intensity-percentile-rank-090day-latest.png",
    fixed = TRUE
  )
  raster <- make_wet_day_intensity_test_raster(0.3, "2026-09-09")
  intensity_plot <- build_prism_wet_day_intensity_map(raster, "intensity")
  rank_plot <- build_prism_wet_day_intensity_map(raster, "percentile-rank")
  testthat::expect_equal(intensity_plot$scales$scales[[1L]]$limits, c(0.04, 1.5))
  testthat::expect_equal(rank_plot$scales$scales[[1L]]$limits, c(0, 100))
})
