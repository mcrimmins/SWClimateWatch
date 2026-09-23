make_longest_dry_spell_test_raster <- function(value, date) {
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

make_longest_dry_spell_fixture <- function() {
  processed_dir <- tempfile("longest-dry-spell-")
  dates <- c(
    seq(as.Date("2019-06-28"), as.Date("2019-07-01"), by = "day"),
    seq(as.Date("2020-06-28"), as.Date("2020-07-01"), by = "day")
  )
  values <- c(0, 0, 0.1, 0, 0.1, 0, 0, 0)
  paths <- file.path(
    processed_dir, "prism", "az-nm-pad050", "daily", "archive", "pcpn",
    paste0(format(dates), ".tif")
  )
  for (index in seq_along(paths)) {
    dir.create(dirname(paths[[index]]), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(
      make_longest_dry_spell_test_raster(values[[index]], dates[[index]]),
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

testthat::test_that("longest dry run uses the wet-day threshold", {
  testthat::expect_equal(
    prism_longest_dry_run(c(0, 0.1, 0, 0, 0.04, 0), 0.04),
    2
  )
  testthat::expect_equal(prism_longest_dry_run(c(0.04, 0.2), 0.04), 0)
  testthat::expect_true(is.na(prism_longest_dry_run(c(0, NA, 0), 0.04)))
})

testthat::test_that("longest dry spell is exact within its moving window", {
  dates <- seq(as.Date("2026-06-01"), by = "day", length.out = 5L)
  raster <- do.call(c, lapply(seq_along(dates), function(index) {
    make_longest_dry_spell_test_raster(c(0, 0.1, 0, 0, 0)[[index]], dates[[index]])
  }))
  terra::time(raster) <- dates
  result <- prism_longest_dry_spell_from_raster(
    raster, max(dates), duration_days = 5L
  )
  testthat::expect_equal(as.numeric(terra::values(result)), 3)
})

testthat::test_that("longest-dry-spell cache is written and reused", {
  fixture <- make_longest_dry_spell_fixture()
  manifest_path <- file.path(fixture$processed_dir, "longest-dry-spell-manifest.csv")
  first <- build_prism_longest_dry_spell_cache(
    "2026-07-01", duration_days = 4L,
    baseline_start = "2019-01-01", baseline_end = "2020-12-31",
    window_days = 1L, processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest, manifest_path = manifest_path,
    quiet = TRUE
  )
  reuse <- build_prism_longest_dry_spell_cache(
    "2026-07-01", duration_days = 4L,
    baseline_start = "2019-01-01", baseline_end = "2020-12-31",
    window_days = 1L, processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest, manifest_path = manifest_path,
    quiet = TRUE
  )
  testthat::expect_equal(as.numeric(terra::values(first$raster)), c(2, 3))
  testthat::expect_true(first$refreshed)
  testthat::expect_false(reuse$refreshed)
  manifest <- read_prism_manifest(manifest_path)
  testthat::expect_equal(manifest$duration_days, 4)
  testthat::expect_equal(manifest$wet_day_threshold_inches, 0.04)
})

testthat::test_that("longest-dry-spell percentile uses the empirical baseline", {
  current <- make_longest_dry_spell_test_raster(2.5, "2026-07-01")
  reference <- do.call(c, lapply(c(2, 3), function(value) {
    make_longest_dry_spell_test_raster(value, as.Date("2018-07-01") + value)
  }))
  rank <- prism_longest_dry_spell_percentile_rank_raster(
    current, reference, 180L, "2026-07-01"
  )
  testthat::expect_equal(as.numeric(terra::values(rank)), 50)
})

testthat::test_that("longest-dry-spell paths and maps use stable conventions", {
  cache_path <- prism_longest_dry_spell_cache_path(
    "2026-09-09", 180L, processed_dir = "processed"
  )
  testthat::expect_match(cache_path, "180day", fixed = TRUE)
  testthat::expect_match(cache_path, "wet-004in", fixed = TRUE)
  testthat::expect_match(cache_path, "centered-05day", fixed = TRUE)
  testthat::expect_match(
    prism_longest_dry_spell_map_path("percentile-rank"),
    "pcpn-longest-dry-spell-percentile-rank-180day-latest.png",
    fixed = TRUE
  )
  raster <- make_longest_dry_spell_test_raster(65, "2026-09-09")
  length_plot <- build_prism_longest_dry_spell_map(raster, "length")
  rank_plot <- build_prism_longest_dry_spell_map(raster, "percentile-rank")
  testthat::expect_equal(length_plot$scales$scales[[1L]]$limits, c(0, 180))
  testthat::expect_equal(rank_plot$scales$scales[[1L]]$limits, c(0, 100))
})
