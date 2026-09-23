make_first_freeze_test_raster <- function(values, dates) {
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

make_first_freeze_fixture <- function() {
  processed_dir <- tempfile("first-freeze-")
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
      make_first_freeze_test_raster(values, dates),
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

testthat::test_that("freeze seasons start on August 1 and publish in September", {
  testthat::expect_equal(
    prism_freeze_season_start("2026-09-09"),
    as.Date("2026-08-01")
  )
  testthat::expect_equal(
    prism_freeze_season_start("2027-02-01"),
    as.Date("2026-08-01")
  )
  testthat::expect_false(prism_first_freeze_publishable("2026-08-31"))
  testthat::expect_true(prism_first_freeze_publishable("2026-09-01"))
  testthat::expect_equal(prism_first_freeze_season_label("2026-08-01"), "2026-27")
})

testthat::test_that("first-freeze publication requires observed coverage", {
  normal <- make_first_freeze_test_raster(c(40, 50), as.Date(c("2000-01-01", "2000-01-02")))
  observed_none <- normal[[1L]] * NA
  observed_half <- normal[[1L]]
  terra::values(observed_half) <- 40
  testthat::expect_false(prism_first_freeze_publishable(
    "2026-09-09", observed_none, normal[[1L]], minimum_observed_coverage = 0.05
  ))
  testthat::expect_true(prism_first_freeze_publishable(
    "2026-09-09", observed_half, normal[[1L]], minimum_observed_coverage = 0.05
  ))
})

testthat::test_that("first freeze includes temperatures equal to 32 F", {
  testthat::expect_equal(prism_first_freeze_index(c(40, 32, 28), 32), 2)
  testthat::expect_true(is.na(prism_first_freeze_index(c(40, 33), 32)))
  testthat::expect_true(is.na(prism_first_freeze_index(c(40, NA, 31), 32)))
})

testthat::test_that("first-freeze raster records day since August 1", {
  dates <- seq(as.Date("2026-08-01"), as.Date("2026-08-05"), by = "day")
  raster <- make_first_freeze_test_raster(c(40, 38, 32, 30, 35), dates)
  result <- prism_first_freeze_from_raster(
    raster, min(dates), threshold_f = 32, observation_end = max(dates)
  )
  testthat::expect_equal(as.numeric(terra::values(result)), 3)
  testthat::expect_equal(as.Date(terra::time(result)), max(dates))
})

testthat::test_that("first-freeze cache is written and reused", {
  fixture <- make_first_freeze_fixture()
  manifest_path <- file.path(fixture$processed_dir, "first-freeze-manifest.csv")
  first <- build_prism_first_freeze_cache(
    baseline_start = "1991-01-01", baseline_end = "1992-12-31",
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = manifest_path,
    quiet = TRUE
  )
  reuse <- build_prism_first_freeze_cache(
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
  testthat::expect_equal(manifest$season_start_month_day, "08-01")
  testthat::expect_equal(manifest$threshold_f, 32)
})

testthat::test_that("first-freeze climatology masks unreliable normals", {
  dates <- as.Date(c("1991-08-01", "1992-08-01", "1993-08-01", "1994-08-01"))
  samples <- make_first_freeze_test_raster(c(10, 20, NA, 30), dates)
  reliable <- prism_first_freeze_climatology(samples, minimum_frequency = 0.75)
  masked <- prism_first_freeze_climatology(samples, minimum_frequency = 1)
  testthat::expect_equal(as.numeric(terra::values(reliable$frequency)), 0.75)
  testthat::expect_equal(as.numeric(terra::values(reliable$median_day)), 20)
  testthat::expect_true(is.na(as.numeric(terra::values(masked$median_day))))
})

testthat::test_that("first-freeze departure is observed minus median date", {
  observed <- make_first_freeze_test_raster(45, as.Date("2026-09-14"))
  normal <- make_first_freeze_test_raster(55, as.Date("2000-01-01"))
  result <- prism_first_freeze_departure_raster(observed, normal, "2026-09-14")
  testthat::expect_equal(as.numeric(terra::values(result)), -10)
})

testthat::test_that("first-freeze paths and maps use stable conventions", {
  testthat::expect_match(
    prism_first_freeze_cache_path(processed_dir = "processed"),
    file.path("first-freeze-samples", "mint", "at-or-below-32F", "aug01-jul31.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_first_freeze_map_path("departure"),
    "mint-first-freeze-departure-latest.png",
    fixed = TRUE
  )
  raster <- make_first_freeze_test_raster(40, as.Date("2026-09-09"))
  observed_plot <- build_prism_first_freeze_map(
    raster, "observed-day", "2026-09-09", "2026-08-01"
  )
  departure_plot <- build_prism_first_freeze_map(
    raster - 40, "departure", "2026-09-09", "2026-08-01"
  )
  testthat::expect_equal(observed_plot$scales$scales[[1L]]$limits, c(1, 365))
  testthat::expect_equal(departure_plot$scales$scales[[1L]]$limits, c(-60, 60))
  testthat::expect_match(observed_plot$labels$title, "First freeze observed so far", fixed = TRUE)
})
