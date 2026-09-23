make_accumulation_cache_test_raster <- function(value, date) {
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

make_accumulation_cache_fixture <- function() {
  processed_dir <- tempfile("accumulation-cache-")
  dates <- as.Date(c(
    "2019-06-29", "2019-06-30", "2019-07-01", "2019-07-02",
    "2020-06-29", "2020-06-30", "2020-07-01", "2020-07-02"
  ))
  values <- c(0.1, 0.2, 0.3, 0.4, 0.2, 0.4, 0.6, 0.8)
  paths <- file.path(
    processed_dir, "prism", "az-nm-pad050", "daily", "archive", "pcpn",
    paste0(format(dates), ".tif")
  )
  for (index in seq_along(paths)) {
    dir.create(dirname(paths[[index]]), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(
      make_accumulation_cache_test_raster(values[[index]], dates[[index]]),
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

testthat::test_that("accumulation cache paths encode method and baseline", {
  path <- prism_accumulation_cache_path(
    30L, "2026-09-09", "1991-01-01", "2020-12-31", window_days = 5L
  )
  testthat::expect_match(path, "19910101-20201231", fixed = TRUE)
  testthat::expect_match(path, file.path("030day", "centered-05day", "09-09.tif"), fixed = TRUE)
})

testthat::test_that("rolling accumulation samples are cached and reused", {
  fixture <- make_accumulation_cache_fixture()
  cache_manifest <- file.path(fixture$processed_dir, "cache-manifest.csv")
  first <- build_prism_accumulation_cache(
    accumulation_days = 3L,
    target_date = "2026-07-01",
    baseline_start = "2019-07-01",
    baseline_end = "2020-07-01",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )
  second <- build_prism_accumulation_cache(
    accumulation_days = 3L,
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
  testthat::expect_equal(
    as.numeric(terra::values(first$raster)), c(0.6, 1.2), tolerance = 1e-7
  )
  testthat::expect_identical(
    as.numeric(terra::values(first$raster)),
    as.numeric(terra::values(second$raster))
  )
  testthat::expect_equal(unique(terra::datatype(second$raster)), "FLT8S")
  testthat::expect_equal(as.Date(terra::time(first$raster)), as.Date(c("2019-07-01", "2020-07-01")))
  manifest <- read_prism_manifest(cache_manifest)
  testthat::expect_equal(nrow(manifest), 1L)
  testthat::expect_equal(manifest$sample_layers, 2L)
})

testthat::test_that("cached samples produce the expected percentile rank", {
  fixture <- make_accumulation_cache_fixture()
  current <- make_accumulation_cache_test_raster(0.9, "2026-07-01")
  result <- calculate_prism_accumulation_percentile_rank(
    current_accumulation = current,
    accumulation_days = 3L,
    current_date = "2026-07-01",
    baseline_start = "2019-07-01",
    baseline_end = "2020-07-01",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    cache_manifest_path = file.path(fixture$processed_dir, "cache-manifest.csv"),
    quiet = TRUE
  )
  direct <- calculate_prism_accumulation_percentile_rank(
    current_accumulation = current,
    accumulation_days = 3L,
    current_date = "2026-07-01",
    baseline_start = "2019-07-01",
    baseline_end = "2020-07-01",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    use_cache = FALSE,
    quiet = TRUE
  )
  testthat::expect_equal(as.numeric(terra::values(result)), 50, tolerance = 1e-5)
  testthat::expect_identical(
    as.numeric(terra::values(result)), as.numeric(terra::values(direct))
  )
})

testthat::test_that("accumulation caches advance incrementally from the prior day", {
  fixture <- make_accumulation_cache_fixture()
  cache_manifest <- file.path(fixture$processed_dir, "cache-manifest.csv")
  build_prism_accumulation_cache(
    accumulation_days = 3L,
    target_date = "2026-07-01",
    baseline_start = "2019-07-01",
    baseline_end = "2020-07-02",
    window_days = 1L,
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )
  incremental <- build_prism_accumulation_cache(
    accumulation_days = 3L,
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
  direct <- build_prism_accumulation_cache(
    accumulation_days = 3L,
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
  testthat::expect_equal(incremental_values, c(0.9, 1.8), tolerance = 1e-7)
  testthat::expect_equal(
    incremental_values,
    as.numeric(terra::values(direct$raster)),
    tolerance = 1e-7
  )
  record <- tail(read_prism_manifest(cache_manifest), 1L)
  testthat::expect_identical(record$build_method, "direct")
})
