testthat::test_that("recent daily precipitation supersedes a monthly source", {
  manifest <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    variable = "pcpn",
    native_units = "inch",
    start_date = as.Date(c("2026-08-01", "2026-08-11")),
    end_date = as.Date(c("2026-08-31", "2026-08-11")),
    processed_at = c("2026-09-01 00:00:00 UTC", "2026-09-10 00:00:00 UTC"),
    path = c(
      file.path("daily", "catchup", "pcpn", "2026-08.tif"),
      file.path("daily", "recent", "pcpn", "2026-08-11.tif")
    ),
    stringsAsFactors = FALSE
  )

  selected <- select_prism_daily_sources(
    "pcpn",
    as.Date(c("2026-08-10", "2026-08-11")),
    processed_manifest = manifest
  )

  testthat::expect_match(selected$path[[1L]], "catchup", fixed = TRUE)
  testthat::expect_match(selected$path[[2L]], "recent", fixed = TRUE)
})

testthat::test_that("precipitation accumulation sums complete daily layers", {
  raster <- terra::rast(
    ncols = 2, nrows = 1,
    xmin = -110, xmax = -108,
    ymin = 33, ymax = 34,
    nlyrs = 3,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- matrix(c(0.1, 0.2, 0.3, 0.4, 0.5, 0.6), nrow = 2)
  terra::time(raster) <- seq(as.Date("2026-09-07"), as.Date("2026-09-09"), by = "day")

  total <- prism_accumulation_from_raster(raster, "pcpn", "2026-09-09")

  testthat::expect_equal(as.vector(terra::values(total)), c(0.9, 1.2))
  testthat::expect_equal(as.Date(terra::time(total)), as.Date("2026-09-09"))
})

testthat::test_that("precipitation map scales and paths are stable", {
  scale <- prism_precipitation_scale(7L)
  testthat::expect_equal(scale$limits, c(0, 8))
  testthat::expect_equal(scale$breaks, c(0, 1, 2, 4, 8))
  testthat::expect_equal(scale$labels[[length(scale$labels)]], "8+")
  testthat::expect_match(
    prism_precipitation_map_path(30L),
    "pcpn-total-30day-latest.png",
    fixed = TRUE
  )
  scale90 <- prism_precipitation_scale(90L)
  testthat::expect_equal(scale90$limits, c(0, 35))
  testthat::expect_error(prism_precipitation_scale(14L), "1, 7, 30, and 90")
})

testthat::test_that("precipitation footer describes the accumulation period", {
  footer <- prism_precipitation_footer_text("2026-09-03", "2026-09-09")
  testthat::expect_match(footer, "Data source: PRISM Climate Group via RCC-ACIS", fixed = TRUE)
  testthat::expect_match(footer, "Accumulation period: September 3-9, 2026", fixed = TRUE)
  testthat::expect_false(grepl("Reference period", footer, fixed = TRUE))
})

testthat::test_that("rolling reference dates include every contributing day", {
  source_dates <- prism_rolling_source_dates(
    as.Date(c("2020-01-07", "2020-01-08")),
    accumulation_days = 7L
  )
  testthat::expect_equal(
    source_dates,
    seq(as.Date("2020-01-01"), as.Date("2020-01-08"), by = "day")
  )
})

testthat::test_that("rolling totals are calculated for requested ending dates", {
  dates <- seq(as.Date("2020-01-01"), as.Date("2020-01-08"), by = "day")
  raster <- terra::rast(
    ncols = 1, nrows = 1, nlyrs = length(dates),
    xmin = -112, xmax = -111.9583333333,
    ymin = 33, ymax = 33.0416666667,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- seq_along(dates)
  terra::time(raster) <- dates

  totals <- prism_rolling_totals_for_end_dates(
    raster,
    dates,
    as.Date(c("2020-01-07", "2020-01-08")),
    accumulation_days = 7L,
    quiet = TRUE
  )

  testthat::expect_equal(as.numeric(terra::values(totals)), c(28, 35))
  testthat::expect_equal(
    as.Date(terra::time(totals)),
    as.Date(c("2020-01-07", "2020-01-08"))
  )
})

testthat::test_that("rolling percentile-rank paths are stable", {
  testthat::expect_match(
    prism_accumulation_percentile_rank_output_path(30L, "2026-09-09"),
    file.path("percentile-rank", "pcpn", "30day", "2026-09-09.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_precipitation_percentile_map_path(7L),
    "pcpn-percentile-rank-07day-latest.png",
    fixed = TRUE
  )
})

testthat::test_that("precipitation percentile change subtracts the earlier rank", {
  current <- terra::rast(
    ncols = 2, nrows = 1, xmin = -112, xmax = -110,
    ymin = 33, ymax = 34, crs = "EPSG:4326"
  )
  previous <- terra::rast(current)
  terra::values(current) <- c(60, 20)
  terra::values(previous) <- c(25, 50)
  terra::time(current) <- as.Date("2026-09-09")
  terra::time(previous) <- as.Date("2026-08-26")

  change <- prism_accumulation_percentile_change_raster(
    current, previous, 30L, 14L, as.Date("2026-09-09")
  )

  testthat::expect_equal(as.numeric(terra::values(change)), c(35, -30))
  testthat::expect_equal(as.Date(terra::time(change)), as.Date("2026-09-09"))
  testthat::expect_match(names(change), "30day_over_14day", fixed = TRUE)
})

testthat::test_that("precipitation percentile-change paths and scale are stable", {
  testthat::expect_match(
    prism_accumulation_percentile_change_output_path(
      30L, 14L, "2026-09-09"
    ),
    file.path(
      "percentile-rank-change", "pcpn", "30day", "14day-change",
      "2026-09-09.tif"
    ),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_precipitation_percentile_change_map_path(30L, 14L),
    "pcpn-percentile-rank-change-30day-over-14day-latest.png",
    fixed = TRUE
  )
  raster <- terra::rast(
    ncols = 2, nrows = 1, xmin = -112, xmax = -110,
    ymin = 33, ymax = 34, crs = "EPSG:4326"
  )
  terra::values(raster) <- c(-25, 25)
  terra::time(raster) <- as.Date("2026-09-09")
  plot <- build_prism_accumulation_percentile_change_map(raster)
  testthat::expect_s3_class(plot, "ggplot")
  testthat::expect_equal(plot$scales$scales[[1L]]$limits, c(-100, 100))
  testthat::expect_match(plot$labels$subtitle, "positive = wetter", fixed = TRUE)
})

testthat::test_that("precipitation percentile change validates its dates", {
  current <- terra::rast(
    ncols = 1, nrows = 1, xmin = -112, xmax = -111,
    ymin = 33, ymax = 34, crs = "EPSG:4326"
  )
  previous <- terra::rast(current)
  terra::values(current) <- 50
  terra::values(previous) <- 40
  terra::time(current) <- as.Date("2026-09-09")
  terra::time(previous) <- as.Date("2026-08-25")
  testthat::expect_error(
    prism_accumulation_percentile_change_raster(
      current, previous, 30L, 14L, as.Date("2026-09-09")
    ),
    "dates do not match"
  )
})

testthat::test_that("rolling percent of normal uses the cached sample mean", {
  current <- terra::rast(
    ncols = 1, nrows = 1, xmin = -112, xmax = -111,
    ymin = 33, ymax = 34, crs = "EPSG:4326"
  )
  reference <- terra::rast(current, nlyrs = 3L)
  terra::values(current) <- 3
  terra::values(reference) <- c(1, 2, 4)
  result <- prism_accumulation_percent_normal_raster(
    current, reference, 30L, "2026-09-09"
  )

  testthat::expect_equal(as.numeric(terra::values(result)), 900 / 7)
  testthat::expect_equal(as.Date(terra::time(result)), as.Date("2026-09-09"))
  testthat::expect_match(names(result), "pcpn_percent_normal_30day", fixed = TRUE)
})

testthat::test_that("rolling percent of normal masks near-zero normals", {
  current <- terra::rast(
    ncols = 1, nrows = 1, xmin = -112, xmax = -111,
    ymin = 33, ymax = 34, crs = "EPSG:4326"
  )
  reference <- terra::rast(current, nlyrs = 2L)
  terra::values(current) <- 0.03
  terra::values(reference) <- c(0.02, 0.04)
  result <- prism_accumulation_percent_normal_raster(
    current, reference, 90L, "2026-09-09", minimum_normal_inches = 0.10
  )
  testthat::expect_true(is.na(as.numeric(terra::values(result))))
})

testthat::test_that("rolling percent-of-normal paths and map scales are stable", {
  testthat::expect_match(
    prism_accumulation_percent_normal_output_path(90L, "2026-09-09"),
    file.path("percent-normal", "pcpn", "90day", "2026-09-09.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_precipitation_percent_normal_map_path(30L),
    "pcpn-percent-normal-30day-latest.png",
    fixed = TRUE
  )
  raster <- terra::rast(
    ncols = 2, nrows = 1, xmin = -112, xmax = -111,
    ymin = 33, ymax = 34, crs = "EPSG:4326"
  )
  terra::values(raster) <- c(50, 150)
  terra::time(raster) <- as.Date("2026-09-09")
  plot <- build_prism_accumulation_percent_normal_map(raster, 90L)
  testthat::expect_s3_class(plot, "ggplot")
  testthat::expect_equal(plot$scales$scales[[1L]]$limits, c(0, 200))
})
