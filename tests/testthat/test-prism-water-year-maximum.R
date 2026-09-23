make_water_year_maximum_test_raster <- function(values, dates) {
  raster <- terra::rast(
    ncols = 1, nrows = 1, nlyrs = length(dates),
    xmin = -112, xmax = -111.9583333333,
    ymin = 33, ymax = 33.0416666667,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- matrix(values, nrow = 1L)
  terra::time(raster) <- as.Date(dates)
  names(raster) <- paste("pcpn", format(as.Date(dates)), sep = "_")
  raster
}

make_water_year_maximum_fixture <- function() {
  processed_dir <- tempfile("water-year-maximum-")
  periods <- prism_complete_water_year_periods("2019-01-01", "2020-12-31")
  paths <- file.path(
    processed_dir, "prism", "az-nm-pad050", "daily", "archive", "pcpn",
    paste0(periods$start_date, "_", periods$end_date, ".tif")
  )
  for (index in seq_len(nrow(periods))) {
    dates <- seq(periods$start_date[[index]], periods$end_date[[index]], by = "day")
    values <- rep(0, length(dates))
    values[1:3] <- if (index == 1L) c(1, 2, 3) else c(10, 20, 30)
    dir.create(dirname(paths[[index]]), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(
      make_water_year_maximum_test_raster(values, dates),
      paths[[index]], overwrite = TRUE
    )
  }
  manifest <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    variable = "pcpn",
    native_units = "inch",
    start_date = periods$start_date,
    end_date = periods$end_date,
    processed_at = rep("2026-09-15 12:00:00 UTC", nrow(periods)),
    md5 = unname(tools::md5sum(paths)),
    path = paths,
    stringsAsFactors = FALSE
  )
  list(processed_dir = processed_dir, manifest = manifest, periods = periods)
}

testthat::test_that("complete water-year periods use October through September", {
  periods <- prism_complete_water_year_periods("1991-01-01", "2020-12-31")
  testthat::expect_equal(nrow(periods), 30L)
  testthat::expect_equal(range(periods$water_year), c(1991L, 2020L))
  testthat::expect_equal(periods$start_date[[1L]], as.Date("1990-10-01"))
  testthat::expect_equal(tail(periods$end_date, 1L), as.Date("2020-09-30"))
})

testthat::test_that("maximum rolling total uses only complete windows", {
  dates <- seq(as.Date("2020-10-01"), by = "day", length.out = 6L)
  raster <- make_water_year_maximum_test_raster(c(1, 2, 3, 0, 5, 0), dates)
  result <- prism_maximum_rolling_total(raster, 3L)
  testthat::expect_equal(as.numeric(terra::values(result)), 8)
  testthat::expect_error(
    prism_maximum_rolling_total(raster[[1:2]], 3L),
    "complete rolling window"
  )
})

testthat::test_that("complete-water-year maximum cache is written and reused", {
  fixture <- make_water_year_maximum_fixture()
  manifest_path <- file.path(fixture$processed_dir, "maximum-manifest.csv")
  first <- build_prism_water_year_maximum_cache(
    3L, "2019-01-01", "2020-12-31",
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = manifest_path,
    quiet = TRUE
  )
  reused <- build_prism_water_year_maximum_cache(
    3L, "2019-01-01", "2020-12-31",
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = manifest_path,
    quiet = TRUE
  )
  testthat::expect_equal(as.numeric(terra::values(first$raster)), c(6, 60))
  testthat::expect_true(first$refreshed)
  testthat::expect_false(reused$refreshed)
  testthat::expect_equal(unique(terra::datatype(reused$raster)), "FLT8S")
  manifest <- read_prism_manifest(manifest_path)
  testthat::expect_equal(manifest$method, "complete-water-years")
  testthat::expect_equal(manifest$rolling_window_days, 3L)
  testthat::expect_equal(manifest$sample_layers, 2L)
})

testthat::test_that("water-year maximum rank uses complete historical maxima", {
  current <- make_water_year_maximum_test_raster(33, "2026-09-09")
  reference <- make_water_year_maximum_test_raster(
    c(6, 60), as.Date(c("2019-09-30", "2020-09-30"))
  )
  rank <- prism_water_year_maximum_rank_raster(current, reference, 3L, "2026-09-09")
  testthat::expect_equal(as.numeric(terra::values(rank)), 50)
})

testthat::test_that("water-year concentration is the wettest event share", {
  maximum <- terra::rast(
    ncols = 2, nrows = 1, xmin = -112, xmax = -111,
    ymin = 33, ymax = 34, crs = "EPSG:4326"
  )
  total <- maximum
  terra::values(maximum) <- c(2, 0.04)
  terra::values(total) <- c(10, 0.08)
  terra::time(maximum) <- as.Date("2026-09-09")
  terra::time(total) <- as.Date("2026-09-09")

  concentration <- prism_water_year_precipitation_concentration_raster(
    maximum, total, 3L, "2026-09-09", minimum_total_inches = 0.10
  )
  testthat::expect_equal(
    as.numeric(terra::values(concentration)), c(20, NA_real_)
  )
  testthat::expect_equal(
    names(concentration),
    "pcpn_water_year_maximum_03day_concentration_2026-09-09"
  )
})

testthat::test_that("water-year maximum paths and maps are stable", {
  testthat::expect_match(
    prism_water_year_maximum_cache_path(3L),
    file.path("003day", "complete-water-years.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_water_year_maximum_map_path("maximum"),
    "pcpn-water-year-max-03day-latest.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_water_year_maximum_map_path("percentile-rank"),
    "pcpn-water-year-max-percentile-rank-03day-latest.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_water_year_concentration_output_path("2026-09-09", 3L),
    file.path("003day", "concentration", "2026-09-09.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_water_year_concentration_map_path(window_days = 3L),
    "pcpn-water-year-precipitation-concentration-03day-latest.png",
    fixed = TRUE
  )
  raster <- make_water_year_maximum_test_raster(c(2, 4), as.Date(c("2026-09-08", "2026-09-09")))
  raster <- raster[[1L]]
  terra::time(raster) <- as.Date("2026-09-09")
  value_plot <- build_prism_water_year_maximum_map(raster, "maximum", window_days = 3L)
  rank_plot <- build_prism_water_year_maximum_map(raster, "percentile-rank", window_days = 3L)
  concentration_plot <- build_prism_water_year_concentration_map(
    raster, window_days = 3L
  )
  testthat::expect_equal(value_plot$scales$scales[[1L]]$limits, c(0, 8))
  testthat::expect_equal(rank_plot$scales$scales[[1L]]$limits, c(0, 100))
  testthat::expect_match(rank_plot$labels$subtitle, "provisional", fixed = TRUE)
  testthat::expect_equal(
    concentration_plot$scales$scales[[1L]]$limits, c(0, 100)
  )
  testthat::expect_match(
    concentration_plot$labels$title, "precipitation concentration", fixed = TRUE
  )
})
