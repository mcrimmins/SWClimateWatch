make_very_wet_test_raster <- function(values, dates) {
  raster <- terra::rast(
    ncols = 1, nrows = 1, nlyrs = length(dates),
    xmin = -112, xmax = -111.9583333333,
    ymin = 33, ymax = 33.0416666667,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- values
  terra::time(raster) <- as.Date(dates)
  names(raster) <- paste("pcpn", format(as.Date(dates)), sep = "_")
  raster
}

make_very_wet_fixture <- function() {
  processed_dir <- tempfile("very-wet-")
  years <- 1991:1992
  starts <- as.Date(sprintf("%d-01-01", years))
  ends <- as.Date(sprintf("%d-12-31", years))
  paths <- file.path(
    processed_dir, "prism", "az-nm-pad050", "daily", "archive", "pcpn",
    paste0(starts, "_", ends, ".tif")
  )
  for (index in seq_along(paths)) {
    dates <- seq(starts[[index]], ends[[index]], by = "day")
    values <- rep(0.01, length(dates))
    values[[94L]] <- c(0.5, 0.2)[[index]]
    dir.create(dirname(paths[[index]]), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(
      make_very_wet_test_raster(values, dates),
      paths[[index]], overwrite = TRUE
    )
  }
  manifest <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    variable = "pcpn",
    native_units = "inch",
    start_date = starts,
    end_date = ends,
    processed_at = rep("2026-09-16 12:00:00 UTC", length(paths)),
    md5 = unname(tools::md5sum(paths)),
    path = paths,
    stringsAsFactors = FALSE
  )
  threshold_path <- prism_very_wet_threshold_path(
    "wet_p95", "1991-01-01", "1992-12-31",
    processed_dir = processed_dir
  )
  dir.create(dirname(threshold_path), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(
    make_very_wet_test_raster(0.25, as.Date("2000-01-01")),
    threshold_path, overwrite = TRUE
  )
  list(
    processed_dir = processed_dir,
    manifest = manifest,
    threshold_path = threshold_path
  )
}

testthat::test_that("very-wet contribution uses days strictly above p95", {
  result <- prism_very_wet_contribution_values(c(0.01, 0.20, 0.50), 0.25, 0.10)
  testthat::expect_equal(result, 100 * 0.50 / 0.71)
  testthat::expect_equal(
    prism_very_wet_contribution_values(c(0.25, 0.25), 0.25, 0.10),
    0
  )
})

testthat::test_that("very-wet contribution suppresses small or incomplete totals", {
  testthat::expect_true(is.na(
    prism_very_wet_contribution_values(c(0.01, 0.02), 0.25, 0.10)
  ))
  testthat::expect_true(is.na(
    prism_very_wet_contribution_values(c(0.10, NA), 0.25, 0.10)
  ))
  testthat::expect_error(
    validate_prism_minimum_precipitation_total(-0.1),
    "non-negative"
  )
})

testthat::test_that("very-wet contribution is exact within its moving window", {
  dates <- seq(as.Date("2026-09-06"), as.Date("2026-09-09"), by = "day")
  raster <- make_very_wet_test_raster(c(0.01, 0.20, 0.50, 0), dates)
  threshold <- make_very_wet_test_raster(0.25, as.Date("2000-01-01"))
  result <- prism_very_wet_contribution_from_raster(
    raster, threshold, max(dates), duration_days = 4L
  )
  testthat::expect_equal(as.numeric(terra::values(result)), 100 * 0.50 / 0.71)
  testthat::expect_equal(as.Date(terra::time(result)), max(dates))
})

testthat::test_that("very-wet contribution requires a complete window", {
  dates <- as.Date(c("2026-09-06", "2026-09-08"))
  raster <- make_very_wet_test_raster(c(0.1, 0.5), dates)
  threshold <- make_very_wet_test_raster(0.25, as.Date("2000-01-01"))
  testthat::expect_error(
    prism_very_wet_contribution_from_raster(
      raster, threshold, "2026-09-08", duration_days = 2L
    ),
    "complete and ordered"
  )
})

testthat::test_that("very-wet threshold path uses annual wet-day climatology", {
  path <- prism_very_wet_threshold_path(processed_dir = "processed")
  testthat::expect_match(path, "annual-wet-days", fixed = TRUE)
  testthat::expect_match(path, "wet_p95.tif", fixed = TRUE)
  testthat::expect_error(
    prism_very_wet_threshold_path("p95", processed_dir = "processed"),
    "wet_p90"
  )
})

testthat::test_that("very-wet contribution cache is written and reused", {
  fixture <- make_very_wet_fixture()
  manifest_path <- file.path(fixture$processed_dir, "very-wet-manifest.csv")
  first <- build_prism_very_wet_contribution_cache(
    target_date = "2026-04-04",
    duration_days = 90L,
    baseline_start = "1991-01-01",
    baseline_end = "1992-12-31",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = manifest_path,
    quiet = TRUE
  )
  reuse <- build_prism_very_wet_contribution_cache(
    target_date = "2026-04-04",
    duration_days = 90L,
    baseline_start = "1991-01-01",
    baseline_end = "1992-12-31",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = manifest_path,
    quiet = TRUE
  )
  expected <- c(100 * 0.5 / 1.39, 0)
  testthat::expect_equal(as.numeric(terra::values(first$raster)), expected, tolerance = 1e-6)
  testthat::expect_true(first$refreshed)
  testthat::expect_false(reuse$refreshed)
  manifest <- read_prism_manifest(manifest_path)
  testthat::expect_equal(manifest$threshold_statistic, "wet_p95")
  testthat::expect_equal(manifest$minimum_total_inches, 0.1)
})

testthat::test_that("very-wet contribution percentile uses empirical baseline", {
  current <- make_very_wet_test_raster(50, as.Date("2026-07-01"))
  reference <- do.call(c, lapply(c(10, 30, 70, 90), function(value) {
    make_very_wet_test_raster(value, as.Date("2018-07-01") + value)
  }))
  rank <- prism_very_wet_contribution_percentile_rank_raster(
    current, reference, 90L, "2026-07-01"
  )
  testthat::expect_equal(as.numeric(terra::values(rank)), 50)
})

testthat::test_that("very-wet contribution cache advances incrementally", {
  fixture <- make_very_wet_fixture()
  manifest_path <- file.path(fixture$processed_dir, "very-wet-manifest.csv")
  build_prism_very_wet_contribution_cache(
    target_date = "2026-04-04",
    duration_days = 90L,
    baseline_start = "1991-01-01",
    baseline_end = "1992-12-31",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = manifest_path,
    quiet = TRUE
  )
  incremental <- build_prism_very_wet_contribution_cache(
    target_date = "2026-04-05",
    duration_days = 90L,
    baseline_start = "1991-01-01",
    baseline_end = "1992-12-31",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = manifest_path,
    quiet = TRUE
  )
  incremental_values <- as.numeric(terra::values(incremental$raster))
  direct <- build_prism_very_wet_contribution_cache(
    target_date = "2026-04-05",
    duration_days = 90L,
    baseline_start = "1991-01-01",
    baseline_end = "1992-12-31",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = manifest_path,
    overwrite = TRUE,
    allow_incremental = FALSE,
    quiet = TRUE
  )

  testthat::expect_identical(incremental$build_method, "incremental")
  testthat::expect_equal(
    incremental_values,
    as.numeric(terra::values(direct$raster)),
    tolerance = 1e-7
  )
})

testthat::test_that("very-wet contribution paths and maps use stable conventions", {
  cache_path <- prism_very_wet_contribution_cache_path(
    "2026-09-09", processed_dir = "processed"
  )
  testthat::expect_match(cache_path, "090day", fixed = TRUE)
  testthat::expect_match(cache_path, "wet-p95", fixed = TRUE)
  testthat::expect_match(cache_path, "minimum-total-010in", fixed = TRUE)
  testthat::expect_match(
    prism_very_wet_contribution_map_path("percentile-rank"),
    "pcpn-very-wet-contribution-percentile-rank-090day-latest.png",
    fixed = TRUE
  )
  raster <- make_very_wet_test_raster(50, as.Date("2026-09-09"))
  contribution_plot <- build_prism_very_wet_contribution_map(raster, "contribution")
  rank_plot <- build_prism_very_wet_contribution_map(raster, "percentile-rank")
  testthat::expect_equal(contribution_plot$scales$scales[[1L]]$limits, c(0, 100))
  testthat::expect_equal(rank_plot$scales$scales[[1L]]$limits, c(0, 100))
  testthat::expect_match(
    contribution_plot$labels$title,
    "Precipitation from very wet days",
    fixed = TRUE
  )
})
