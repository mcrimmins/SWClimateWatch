make_dry_spell_test_raster <- function(value, date) {
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

make_dry_spell_fixture <- function() {
  processed_dir <- tempfile("dry-spell-")
  dates <- c(
    seq(as.Date("2019-06-27"), as.Date("2019-07-02"), by = "day"),
    seq(as.Date("2020-06-27"), as.Date("2020-07-02"), by = "day")
  )
  values <- c(0.1, 0, 0, 0, 0, 0, 0, 0.2, 0, 0, 0, 0)
  paths <- file.path(
    processed_dir, "prism", "az-nm-pad050", "daily", "archive", "pcpn",
    paste0(format(dates), ".tif")
  )
  for (index in seq_along(paths)) {
    dir.create(dirname(paths[[index]]), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(
      make_dry_spell_test_raster(values[[index]], dates[[index]]),
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
    processed_at = rep("2026-09-13 12:00:00 UTC", length(dates)),
    md5 = unname(tools::md5sum(paths)),
    path = paths,
    stringsAsFactors = FALSE
  )
  list(processed_dir = processed_dir, manifest = manifest)
}

testthat::test_that("trailing dry length resets on a wet day", {
  testthat::expect_equal(prism_trailing_dry_length(c(0.1, 0, 0, 0), 0.04), 3L)
  testthat::expect_equal(prism_trailing_dry_length(c(0, 0, 0.04), 0.04), 0L)
  testthat::expect_true(is.na(prism_trailing_dry_length(c(0.1, NA, 0), 0.04)))
})

testthat::test_that("dry-spell source dates honor the lookback", {
  dates <- prism_dry_spell_source_dates(
    as.Date(c("2020-07-01", "2020-07-02")), 5L,
    available_start = as.Date("1981-01-01")
  )
  testthat::expect_equal(
    dates,
    seq(as.Date("2020-06-27"), as.Date("2020-07-02"), by = "day")
  )
})

testthat::test_that("dry-spell lengths are exact for requested ending dates", {
  dates <- seq(as.Date("2020-06-27"), as.Date("2020-07-01"), by = "day")
  raster <- do.call(c, lapply(seq_along(dates), function(index) {
    make_dry_spell_test_raster(c(0, 0.2, 0, 0, 0)[[index]], dates[[index]])
  }))
  terra::time(raster) <- dates
  result <- prism_dry_spell_lengths_for_end_dates(
    raster, dates, as.Date("2020-07-01"),
    lookback_days = 5L, available_start = as.Date("1981-01-01"), quiet = TRUE
  )
  testthat::expect_equal(as.numeric(terra::values(result$raster)), 3)
  testthat::expect_equal(result$censored_cells, 0)
})

testthat::test_that("dry-spell cache is written and reused", {
  fixture <- make_dry_spell_fixture()
  cache_manifest <- file.path(fixture$processed_dir, "dry-spell-manifest.csv")
  first <- build_prism_dry_spell_cache(
    "2026-07-01", "2019-01-01", "2020-12-31", window_days = 1L,
    initial_lookback_days = 5L, maximum_lookback_days = 10L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )
  second <- build_prism_dry_spell_cache(
    "2026-07-01", "2019-01-01", "2020-12-31", window_days = 1L,
    initial_lookback_days = 5L, maximum_lookback_days = 10L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )
  next_day <- build_prism_dry_spell_cache(
    "2026-07-02", "2019-01-01", "2020-12-31", window_days = 1L,
    initial_lookback_days = 5L, maximum_lookback_days = 10L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )
  testthat::expect_equal(as.numeric(terra::values(first$raster)), c(4, 3))
  testthat::expect_true(first$refreshed)
  testthat::expect_false(second$refreshed)
  testthat::expect_equal(first$lookback_days, 5L)
  testthat::expect_equal(as.numeric(terra::values(next_day$raster)), c(5, 4))
  testthat::expect_equal(next_day$build_method, "incremental")
  manifest <- read_prism_manifest(cache_manifest)
  testthat::expect_true(all(manifest$censored_cells == 0))
  testthat::expect_true(all(manifest$wet_day_threshold_inches == 0.04))
})

testthat::test_that("dry-spell cache reruns with a longer lookback when censored", {
  fixture <- make_dry_spell_fixture()
  expanded_dir <- tempfile("dry-spell-expanded-")
  expanded <- build_prism_dry_spell_cache(
    "2026-07-01", "2019-01-01", "2020-12-31", window_days = 1L,
    initial_lookback_days = 3L, maximum_lookback_days = 5L,
    processed_dir = expanded_dir,
    processed_manifest = fixture$manifest,
    manifest_path = file.path(expanded_dir, "manifest.csv"),
    allow_incremental = FALSE,
    quiet = TRUE
  )
  testthat::expect_equal(expanded$lookback_days, 5L)
  testthat::expect_equal(as.numeric(terra::values(expanded$raster)), c(4, 3))
  manifest <- read_prism_manifest(file.path(expanded_dir, "manifest.csv"))
  testthat::expect_equal(manifest$censored_cells, 0)
})

testthat::test_that("dry-spell percentile rank uses the empirical baseline", {
  current <- make_dry_spell_test_raster(3.5, "2026-07-01")
  reference <- do.call(c, lapply(c(3, 4), function(value) {
    make_dry_spell_test_raster(value, as.Date("2018-07-01") + value)
  }))
  rank <- prism_dry_spell_percentile_rank_raster(current, reference, "2026-07-01")
  testthat::expect_equal(as.numeric(terra::values(rank)), 50)
})

testthat::test_that("dry-spell maps use fixed scales and paths", {
  raster <- terra::rast(
    ncols = 2, nrows = 1, xmin = -112, xmax = -111,
    ymin = 33, ymax = 34, crs = "EPSG:4326"
  )
  terra::values(raster) <- c(5, 80)
  terra::time(raster) <- as.Date("2026-09-09")
  length_plot <- build_prism_dry_spell_map(raster, "length")
  rank_plot <- build_prism_dry_spell_map(raster, "percentile-rank")
  testthat::expect_equal(length_plot$scales$scales[[1L]]$limits, c(0, 90))
  testthat::expect_equal(rank_plot$scales$scales[[1L]]$limits, c(0, 100))
  testthat::expect_match(
    prism_dry_spell_map_path("percentile-rank"),
    "pcpn-current-dry-spell-percentile-rank-latest.png",
    fixed = TRUE
  )
})
