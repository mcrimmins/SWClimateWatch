make_freeze_free_test_raster <- function(values, dates) {
  raster <- terra::rast(
    ncols = 1, nrows = 1, nlyrs = length(dates),
    xmin = -112, xmax = -111.9583333333,
    ymin = 33, ymax = 33.0416666667,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- values
  terra::time(raster) <- as.Date(dates)
  names(raster) <- paste("mint", format(as.Date(dates)), sep = "_")
  raster
}

make_freeze_free_fixture <- function() {
  processed_dir <- tempfile("freeze-free-")
  years <- 1991:1992
  starts <- as.Date(sprintf("%d-01-01", years))
  ends <- as.Date(sprintf("%d-12-31", years))
  spring_days <- c(100L, 120L)
  fall_days <- c(300L, 280L)
  paths <- file.path(
    processed_dir, "prism", "az-nm-pad050", "daily", "archive", "mint",
    paste0(starts, "_", ends, ".tif")
  )
  for (index in seq_along(paths)) {
    dates <- seq(starts[[index]], ends[[index]], by = "day")
    values <- rep(40, length(dates))
    values[[spring_days[[index]]]] <- 32
    values[[fall_days[[index]]]] <- 31
    dir.create(dirname(paths[[index]]), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(
      make_freeze_free_test_raster(values, dates),
      paths[[index]], overwrite = TRUE
    )
  }
  manifest <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    variable = "mint",
    native_units = "degreeF",
    start_date = starts,
    end_date = ends,
    processed_at = rep("2026-09-16 12:00:00 UTC", length(paths)),
    md5 = unname(tools::md5sum(paths)),
    path = paths,
    stringsAsFactors = FALSE
  )
  list(processed_dir = processed_dir, manifest = manifest)
}

testthat::test_that("freeze-free periods use complete calendar years", {
  periods <- prism_freeze_free_periods("1991-01-01", "1992-12-31")
  testthat::expect_equal(periods$year, 1991:1992)
  testthat::expect_equal(periods$start_date, as.Date(c("1991-01-01", "1992-01-01")))
  testthat::expect_equal(periods$end_date, as.Date(c("1991-12-31", "1992-12-31")))
})

testthat::test_that("freeze-free length uses last spring and first fall freeze", {
  values <- rep(40, 365)
  values[c(30, 100, 300, 330)] <- c(31, 32, 32, 30)
  testthat::expect_equal(
    prism_freeze_free_length_index(values, 1:212, 213:365, 32),
    200
  )
  testthat::expect_true(is.na(
    prism_freeze_free_length_index(rep(40, 365), 1:212, 213:365, 32)
  ))
  values[[50]] <- NA
  testthat::expect_true(is.na(
    prism_freeze_free_length_index(values, 1:212, 213:365, 32)
  ))
})

testthat::test_that("freeze-free raster records elapsed days", {
  dates <- seq(as.Date("2025-01-01"), as.Date("2025-12-31"), by = "day")
  values <- rep(40, length(dates))
  values[c(100, 300)] <- 32
  raster <- make_freeze_free_test_raster(values, dates)
  result <- prism_freeze_free_length_from_raster(
    raster, 2025, threshold_f = 32, observation_end = max(dates)
  )
  testthat::expect_equal(as.numeric(terra::values(result)), 200)
  testthat::expect_equal(as.Date(terra::time(result)), max(dates))
})

testthat::test_that("freeze-free raster remains blank before a fall freeze", {
  dates <- seq(as.Date("2026-01-01"), as.Date("2026-09-09"), by = "day")
  values <- rep(40, length(dates))
  values[[100]] <- 30
  raster <- make_freeze_free_test_raster(values, dates)
  result <- prism_freeze_free_length_from_raster(
    raster, 2026, threshold_f = 32, observation_end = max(dates)
  )
  testthat::expect_true(is.na(as.numeric(terra::values(result))))
})

testthat::test_that("freeze-free raster remains blank before August", {
  dates <- seq(as.Date("2026-01-01"), as.Date("2026-05-31"), by = "day")
  values <- rep(40, length(dates))
  values[[100]] <- 30
  raster <- make_freeze_free_test_raster(values, dates)
  result <- prism_freeze_free_length_from_raster(
    raster, 2026, threshold_f = 32, observation_end = max(dates)
  )
  testthat::expect_true(is.na(as.numeric(terra::values(result))))
})

testthat::test_that("freeze-free publication requires fall coverage", {
  normal <- make_freeze_free_test_raster(180, as.Date("2000-01-01"))
  blank <- normal * NA
  observed <- normal
  testthat::expect_false(prism_freeze_free_publishable("2026-08-31"))
  testthat::expect_false(prism_freeze_free_publishable(
    "2026-09-09", blank, normal, minimum_observed_coverage = 0.05
  ))
  testthat::expect_true(prism_freeze_free_publishable(
    "2026-09-09", observed, normal, minimum_observed_coverage = 0.05
  ))
})

testthat::test_that("freeze-free cache is written and reused", {
  fixture <- make_freeze_free_fixture()
  manifest_path <- file.path(fixture$processed_dir, "freeze-free-manifest.csv")
  first <- build_prism_freeze_free_cache(
    baseline_start = "1991-01-01", baseline_end = "1992-12-31",
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = manifest_path,
    quiet = TRUE
  )
  reuse <- build_prism_freeze_free_cache(
    baseline_start = "1991-01-01", baseline_end = "1992-12-31",
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = manifest_path,
    quiet = TRUE
  )
  testthat::expect_equal(as.numeric(terra::values(first$raster)), c(200, 160))
  testthat::expect_true(first$refreshed)
  testthat::expect_false(reuse$refreshed)
  manifest <- read_prism_manifest(manifest_path)
  testthat::expect_equal(manifest$product, "freeze_free_calendar_year_sample")
  testthat::expect_equal(manifest$native_units, "days")
})

testthat::test_that("freeze-free climatology masks unreliable normals", {
  dates <- as.Date(c("1991-01-01", "1992-01-01", "1993-01-01", "1994-01-01"))
  samples <- make_freeze_free_test_raster(c(160, 180, NA, 200), dates)
  reliable <- prism_freeze_free_climatology(samples, minimum_frequency = 0.75)
  masked <- prism_freeze_free_climatology(samples, minimum_frequency = 1)
  testthat::expect_equal(as.numeric(terra::values(reliable$frequency)), 0.75)
  testthat::expect_equal(as.numeric(terra::values(reliable$median_length)), 180)
  testthat::expect_true(is.na(as.numeric(terra::values(masked$median_length))))
})

testthat::test_that("freeze-free departure is observed minus median length", {
  observed <- make_freeze_free_test_raster(210, as.Date("2025-12-31"))
  normal <- make_freeze_free_test_raster(180, as.Date("2000-01-01"))
  result <- prism_freeze_free_departure_raster(observed, normal, "2025-12-31")
  testthat::expect_equal(as.numeric(terra::values(result)), 30)
})

testthat::test_that("freeze-free paths and maps use stable conventions", {
  testthat::expect_match(
    prism_freeze_free_cache_path(processed_dir = "processed"),
    file.path("freeze-free-samples", "mint", "at-or-below-32F", "calendar-years.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_freeze_free_map_path("departure"),
    "mint-freeze-free-season-departure-latest.png",
    fixed = TRUE
  )
  raster <- make_freeze_free_test_raster(200, as.Date("2025-12-31"))
  length_plot <- build_prism_freeze_free_map(
    raster, "length", "2025-12-31", 2025
  )
  departure_plot <- build_prism_freeze_free_map(
    raster - 200, "departure", "2025-12-31", 2025
  )
  testthat::expect_equal(length_plot$scales$scales[[1L]]$limits, c(0, 365))
  testthat::expect_equal(departure_plot$scales$scales[[1L]]$limits, c(-60, 60))
  testthat::expect_match(length_plot$labels$title, "Freeze-free season length", fixed = TRUE)
})
