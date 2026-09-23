make_wet_day_count_test_raster <- function(value, date) {
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

make_wet_day_count_fixture <- function() {
  processed_dir <- tempfile("wet-day-count-")
  dates <- c(
    seq(as.Date("2019-06-29"), as.Date("2019-07-02"), by = "day"),
    seq(as.Date("2020-06-29"), as.Date("2020-07-02"), by = "day")
  )
  values <- c(0.04, 0, 0.1, 0, 0, 0.04, 0, 0.2)
  paths <- file.path(
    processed_dir, "prism", "az-nm-pad050", "daily", "archive", "pcpn",
    paste0(format(dates), ".tif")
  )
  for (index in seq_along(paths)) {
    dir.create(dirname(paths[[index]]), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(
      make_wet_day_count_test_raster(values[[index]], dates[[index]]),
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
    processed_at = rep("2026-09-15 12:00:00 UTC", length(dates)),
    md5 = unname(tools::md5sum(paths)),
    path = paths,
    stringsAsFactors = FALSE
  )
  list(processed_dir = processed_dir, manifest = manifest)
}

testthat::test_that("wet-day count includes precipitation at the threshold", {
  dates <- seq(as.Date("2026-06-01"), by = "day", length.out = 4L)
  raster <- do.call(c, lapply(seq_along(dates), function(index) {
    make_wet_day_count_test_raster(c(0, 0.039, 0.04, 0.2)[[index]], dates[[index]])
  }))
  terra::time(raster) <- dates
  result <- prism_wet_day_count_from_raster(raster, max(dates), 0.04)
  testthat::expect_equal(as.numeric(terra::values(result)), 2)
})

testthat::test_that("rolling wet-day counts are exact", {
  dates <- seq(as.Date("2020-06-28"), as.Date("2020-07-02"), by = "day")
  raster <- do.call(c, lapply(seq_along(dates), function(index) {
    make_wet_day_count_test_raster(c(0.04, 0, 0.1, 0.039, 0.2)[[index]], dates[[index]])
  }))
  terra::time(raster) <- dates
  result <- prism_wet_day_counts_for_end_dates(
    raster, dates, as.Date(c("2020-06-30", "2020-07-02")),
    duration_days = 3L, quiet = TRUE
  )
  testthat::expect_equal(as.numeric(terra::values(result)), c(2, 2))
})

testthat::test_that("wet-day-count cache is written, reused, and incremented", {
  fixture <- make_wet_day_count_fixture()
  manifest_path <- file.path(fixture$processed_dir, "wet-day-count-manifest.csv")
  first <- build_prism_wet_day_count_cache(
    "2026-07-01", duration_days = 3L,
    baseline_start = "2019-01-01", baseline_end = "2020-12-31",
    window_days = 1L, processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest, manifest_path = manifest_path,
    quiet = TRUE
  )
  reuse <- build_prism_wet_day_count_cache(
    "2026-07-01", duration_days = 3L,
    baseline_start = "2019-01-01", baseline_end = "2020-12-31",
    window_days = 1L, processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest, manifest_path = manifest_path,
    quiet = TRUE
  )
  next_day <- build_prism_wet_day_count_cache(
    "2026-07-02", duration_days = 3L,
    baseline_start = "2019-01-01", baseline_end = "2020-12-31",
    window_days = 1L, processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest, manifest_path = manifest_path,
    quiet = TRUE
  )
  direct_dir <- tempfile("wet-day-count-direct-")
  direct_manifest <- file.path(direct_dir, "manifest.csv")
  direct <- build_prism_wet_day_count_cache(
    "2026-07-02", duration_days = 3L,
    baseline_start = "2019-01-01", baseline_end = "2020-12-31",
    window_days = 1L, processed_dir = direct_dir,
    processed_manifest = fixture$manifest, manifest_path = direct_manifest,
    allow_incremental = FALSE, quiet = TRUE
  )
  testthat::expect_equal(as.numeric(terra::values(first$raster)), c(2, 1))
  testthat::expect_true(first$refreshed)
  testthat::expect_false(reuse$refreshed)
  testthat::expect_equal(next_day$build_method, "incremental")
  testthat::expect_equal(as.numeric(terra::values(next_day$raster)), c(1, 2))
  testthat::expect_equal(
    as.numeric(terra::values(next_day$raster)),
    as.numeric(terra::values(direct$raster))
  )
  manifest <- read_prism_manifest(manifest_path)
  testthat::expect_true(all(manifest$wet_day_threshold_inches == 0.04))
})

testthat::test_that("wet-day-count percentile rank uses the empirical baseline", {
  current <- make_wet_day_count_test_raster(1.5, "2026-07-01")
  reference <- do.call(c, lapply(c(1, 2), function(value) {
    make_wet_day_count_test_raster(value, as.Date("2018-07-01") + value)
  }))
  rank <- prism_wet_day_count_percentile_rank_raster(
    current, reference, 90L, "2026-07-01"
  )
  testthat::expect_equal(as.numeric(terra::values(rank)), 50)
})

testthat::test_that("wet-day-count paths and maps use stable conventions", {
  cache_path <- prism_wet_day_count_cache_path(
    "2026-09-09", 90L, processed_dir = "processed"
  )
  testthat::expect_match(cache_path, "090day", fixed = TRUE)
  testthat::expect_match(cache_path, "wet-004in", fixed = TRUE)
  testthat::expect_match(cache_path, "centered-05day", fixed = TRUE)
  testthat::expect_match(
    prism_wet_day_count_map_path("percentile-rank"),
    "pcpn-wet-day-count-percentile-rank-090day-latest.png",
    fixed = TRUE
  )
  raster <- make_wet_day_count_test_raster(12, "2026-09-09")
  count_plot <- build_prism_wet_day_count_map(raster, "count")
  rank_plot <- build_prism_wet_day_count_map(raster, "percentile-rank")
  testthat::expect_equal(count_plot$scales$scales[[1L]]$limits, c(0, 60))
  testthat::expect_equal(rank_plot$scales$scales[[1L]]$limits, c(0, 100))
})
