make_last_freeze_test_raster <- function(values, dates) {
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

make_last_freeze_fixture <- function() {
  processed_dir <- tempfile("last-freeze-")
  starts <- as.Date(c("1991-08-01", "1992-08-01"))
  ends <- as.Date(c("1992-07-31", "1993-07-31"))
  freeze_days <- c(10L, 20L)
  paths <- file.path(
    processed_dir, "prism", "az-nm-pad050", "daily", "archive", "mint",
    paste0(starts, "_", ends, ".tif")
  )
  for (index in seq_along(paths)) {
    dates <- seq(starts[[index]], ends[[index]], by = "day")
    values <- rep(40, length(dates))
    values[[freeze_days[[index]]]] <- 32
    dir.create(dirname(paths[[index]]), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(
      make_last_freeze_test_raster(values, dates),
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

testthat::test_that("last-freeze maps publish beginning March 1", {
  testthat::expect_false(prism_last_freeze_publishable("2027-02-28"))
  testthat::expect_true(prism_last_freeze_publishable("2027-03-01"))
  testthat::expect_true(prism_last_freeze_publishable("2027-07-31"))
  testthat::expect_false(prism_last_freeze_publishable("2027-08-01"))
})

testthat::test_that("last freeze includes temperatures equal to 32 F", {
  testthat::expect_equal(prism_last_freeze_index(c(32, 40, 28), 32), 3)
  testthat::expect_true(is.na(prism_last_freeze_index(c(40, 33), 32)))
  testthat::expect_true(is.na(prism_last_freeze_index(c(31, NA, 30), 32)))
})

testthat::test_that("last-freeze raster records the final qualifying day", {
  dates <- seq(as.Date("2026-08-01"), as.Date("2026-08-05"), by = "day")
  raster <- make_last_freeze_test_raster(c(32, 38, 31, 40, 35), dates)
  result <- prism_last_freeze_from_raster(
    raster, min(dates), threshold_f = 32, observation_end = max(dates)
  )
  testthat::expect_equal(as.numeric(terra::values(result)), 3)
  testthat::expect_equal(as.Date(terra::time(result)), max(dates))
})

testthat::test_that("last-freeze input must be complete", {
  dates <- as.Date(c("2026-08-01", "2026-08-03"))
  raster <- make_last_freeze_test_raster(c(32, 30), dates)
  testthat::expect_error(
    prism_last_freeze_from_raster(raster, "2026-08-01", observation_end = "2026-08-03"),
    "complete and ordered"
  )
})

testthat::test_that("last-freeze cache is written and reused", {
  fixture <- make_last_freeze_fixture()
  manifest_path <- file.path(fixture$processed_dir, "last-freeze-manifest.csv")
  first <- build_prism_last_freeze_cache(
    baseline_start = "1991-01-01", baseline_end = "1992-12-31",
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = manifest_path,
    quiet = TRUE
  )
  reuse <- build_prism_last_freeze_cache(
    baseline_start = "1991-01-01", baseline_end = "1992-12-31",
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = manifest_path,
    quiet = TRUE
  )
  testthat::expect_equal(as.numeric(terra::values(first$raster)), c(10, 20))
  testthat::expect_true(first$refreshed)
  testthat::expect_false(reuse$refreshed)
  manifest <- read_prism_manifest(manifest_path)
  testthat::expect_equal(manifest$product, "last_freeze_season_sample")
  testthat::expect_equal(manifest$threshold_f, 32)
})

testthat::test_that("last-freeze climatology masks unreliable normals", {
  dates <- as.Date(c("1991-08-01", "1992-08-01", "1993-08-01", "1994-08-01"))
  samples <- make_last_freeze_test_raster(c(220, 230, NA, 240), dates)
  reliable <- prism_last_freeze_climatology(samples, minimum_frequency = 0.75)
  masked <- prism_last_freeze_climatology(samples, minimum_frequency = 1)
  testthat::expect_equal(as.numeric(terra::values(reliable$frequency)), 0.75)
  testthat::expect_equal(as.numeric(terra::values(reliable$median_day)), 230)
  testthat::expect_true(is.na(as.numeric(terra::values(masked$median_day))))
})

testthat::test_that("last-freeze departure is observed minus median date", {
  observed <- make_last_freeze_test_raster(250, as.Date("2027-04-07"))
  normal <- make_last_freeze_test_raster(235, as.Date("2000-01-01"))
  result <- prism_last_freeze_departure_raster(observed, normal, "2027-04-07")
  testthat::expect_equal(as.numeric(terra::values(result)), 15)
})

testthat::test_that("last-freeze paths and maps use stable conventions", {
  testthat::expect_match(
    prism_last_freeze_cache_path(processed_dir = "processed"),
    file.path("last-freeze-samples", "mint", "at-or-below-32F", "aug01-jul31.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_last_freeze_map_path("departure"),
    "mint-last-freeze-departure-latest.png",
    fixed = TRUE
  )
  raster <- make_last_freeze_test_raster(250, as.Date("2027-04-07"))
  observed_plot <- build_prism_last_freeze_map(
    raster, "observed-day", "2027-04-07", "2026-08-01"
  )
  departure_plot <- build_prism_last_freeze_map(
    raster - 250, "departure", "2027-04-07", "2026-08-01"
  )
  testthat::expect_equal(observed_plot$scales$scales[[1L]]$limits, c(1, 365))
  testthat::expect_equal(departure_plot$scales$scales[[1L]]$limits, c(-60, 60))
  testthat::expect_match(observed_plot$labels$title, "Last freeze observed so far", fixed = TRUE)
})
