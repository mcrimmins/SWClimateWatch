make_rolling_temperature_test_raster <- function(values, dates, variable = "tmean") {
  raster <- terra::rast(
    ncols = 1, nrows = 1, nlyrs = length(values),
    xmin = -112, xmax = -111.9583333333,
    ymin = 33, ymax = 33.0416666667,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- values
  terra::time(raster) <- as.Date(dates)
  names(raster) <- paste(variable, format(as.Date(dates)), sep = "_")
  raster
}

make_rolling_temperature_cache_fixture <- function() {
  processed_dir <- tempfile("rolling-temperature-cache-")
  dates <- c(
    seq(as.Date("2019-06-25"), as.Date("2019-07-02"), by = "day"),
    seq(as.Date("2020-06-25"), as.Date("2020-07-02"), by = "day")
  )
  variables <- rep(c("maxt", "mint"), each = 2L)
  years <- rep(c(2019L, 2020L), 2L)
  values <- c(80, 100, 40, 60)
  paths <- character(length(variables))
  for (index in seq_along(variables)) {
    variable_dates <- dates[format(dates, "%Y") == years[[index]]]
    paths[[index]] <- file.path(
      processed_dir, "prism", "az-nm-pad050", "daily", "archive",
        variables[[index]], paste0(years[[index]], "-06-25_", years[[index]], "-07-02.tif")
    )
    dir.create(dirname(paths[[index]]), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(
      make_rolling_temperature_test_raster(
        values[[index]] + seq_along(variable_dates) - 1L,
        variable_dates,
        variables[[index]]
      ),
      paths[[index]], overwrite = TRUE
    )
  }
  manifest <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    variable = variables,
    native_units = "degreeF",
    start_date = as.Date(paste0(years, "-06-25")),
    end_date = as.Date(paste0(years, "-07-02")),
    processed_at = rep("2026-09-17 12:00:00 UTC", length(paths)),
    md5 = unname(tools::md5sum(paths)),
    path = paths,
    stringsAsFactors = FALSE
  )
  list(processed_dir = processed_dir, manifest = manifest)
}

testthat::test_that("rolling temperature mean uses complete daily windows", {
  dates <- seq(as.Date("2026-07-01"), as.Date("2026-07-07"), by = "day")
  raster <- make_rolling_temperature_test_raster(1:7, dates)
  result <- prism_rolling_temperature_mean_raster(raster, 7L, "2026-07-07")
  testthat::expect_equal(as.numeric(terra::values(result)), 4)
  testthat::expect_equal(as.Date(terra::time(result)), as.Date("2026-07-07"))
  testthat::expect_error(
    prism_rolling_temperature_mean_raster(raster[[-1L]], 7L, "2026-07-07"),
    "complete, ordered"
  )
})

testthat::test_that("rolling temperature reference means use requested ending dates", {
  dates <- seq(as.Date("2020-01-01"), as.Date("2020-01-08"), by = "day")
  raster <- make_rolling_temperature_test_raster(1:8, dates)
  means <- prism_rolling_temperature_means_for_end_dates(
    raster, dates, dates[7:8], 7L, quiet = TRUE
  )
  testthat::expect_equal(as.numeric(terra::values(means)), c(4, 5))
  testthat::expect_equal(as.Date(terra::time(means)), dates[7:8])
})

testthat::test_that("rolling temperature paths encode duration and method", {
  cache_path <- prism_rolling_temperature_cache_path(
    7L, "2026-09-09", "1991-01-01", "2020-12-31", 5L
  )
  testthat::expect_match(cache_path, "19910101-20201231", fixed = TRUE)
  testthat::expect_match(
    cache_path,
    file.path("rolling-temperature-samples", "tmean", "007day", "centered-05day", "09-09.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_rolling_temperature_percentile_output_path(90L, "2026-09-09"),
    file.path("rolling-percentile-rank", "tmean", "090day", "2026-09-09.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_rolling_temperature_percentile_map_path(7L),
    "tmean-percentile-rank-07day-latest.png",
    fixed = TRUE
  )
})

testthat::test_that("rolling temperature samples are cached and reused", {
  fixture <- make_rolling_temperature_cache_fixture()
  cache_manifest <- file.path(fixture$processed_dir, "cache-manifest.csv")
  first <- build_prism_rolling_temperature_cache(
    days = 7L,
    target_date = "2026-07-01",
    baseline_start = "2019-07-01",
    baseline_end = "2020-07-01",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )
  second <- build_prism_rolling_temperature_cache(
    days = 7L,
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
  testthat::expect_equal(as.numeric(terra::values(first$raster)), c(63, 83))
  testthat::expect_equal(unique(terra::datatype(second$raster)), "FLT8S")
  manifest <- read_prism_manifest(cache_manifest)
  testthat::expect_equal(nrow(manifest), 1L)
  testthat::expect_equal(manifest$sample_layers, 2L)
})

testthat::test_that("rolling temperature percentile ranks compare rolling means", {
  current <- make_rolling_temperature_test_raster(70, "2026-07-01")
  reference <- make_rolling_temperature_test_raster(
    c(60, 80), c("2019-07-01", "2020-07-01")
  )
  rank <- prism_rolling_temperature_percentile_rank_raster(
    current, reference, 7L, "2026-07-01"
  )
  testthat::expect_equal(as.numeric(terra::values(rank)), 50)
  testthat::expect_equal(as.Date(terra::time(rank)), as.Date("2026-07-01"))
})

testthat::test_that("rolling temperature caches advance incrementally from the prior day", {
  fixture <- make_rolling_temperature_cache_fixture()
  cache_manifest <- file.path(fixture$processed_dir, "cache-manifest.csv")
  build_prism_rolling_temperature_cache(
    days = 7L,
    target_date = "2026-07-01",
    baseline_start = "2019-07-01",
    baseline_end = "2020-07-02",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )
  incremental <- build_prism_rolling_temperature_cache(
    days = 7L,
    target_date = "2026-07-02",
    baseline_start = "2019-07-01",
    baseline_end = "2020-07-02",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )
  incremental_values <- as.numeric(terra::values(incremental$raster))
  direct <- build_prism_rolling_temperature_cache(
    days = 7L,
    target_date = "2026-07-02",
    baseline_start = "2019-07-01",
    baseline_end = "2020-07-02",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    overwrite = TRUE,
    allow_incremental = FALSE,
    quiet = TRUE
  )

  testthat::expect_identical(incremental$build_method, "incremental")
  testthat::expect_equal(incremental_values, c(64, 84), tolerance = 1e-7)
  testthat::expect_equal(
    incremental_values,
    as.numeric(terra::values(direct$raster)),
    tolerance = 1e-7
  )
})

testthat::test_that("public rolling temperature maps use three supported windows", {
  rank <- make_rolling_temperature_test_raster(50, "2026-09-09")
  plot <- build_prism_rolling_temperature_percentile_map(rank, 90L)
  testthat::expect_s3_class(plot, "ggplot")
  testthat::expect_equal(plot$scales$scales[[1L]]$limits, c(0, 100))
  testthat::expect_match(plot$labels$title, "90-day", fixed = TRUE)
  testthat::expect_match(plot$labels$subtitle, "centered 5-day baseline", fixed = TRUE)
  testthat::expect_error(
    build_prism_rolling_temperature_percentile_map(rank, 14L),
    "support 7, 30, and 90"
  )
})
