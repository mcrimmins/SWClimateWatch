make_water_year_comparison_raster <- function(values, nlyrs = 1L) {
  raster <- terra::rast(
    ncols = 2, nrows = 1, nlyrs = nlyrs,
    xmin = -112, xmax = -111,
    ymin = 33, ymax = 34,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- values
  raster
}

testthat::test_that("water-year paths are stable", {
  testthat::expect_match(
    prism_water_year_product_path("percent-normal", "2026-09-09"),
    file.path("water-year", "pcpn", "percent-normal", "2026-09-09.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_water_year_map_path("percentile-rank"),
    "pcpn-water-year-percentile-rank-latest.png",
    fixed = TRUE
  )
})

testthat::test_that("water-year comparison rasters calculate normal, percentage, and rank", {
  current <- make_water_year_comparison_raster(c(3, 0.02))
  reference <- make_water_year_comparison_raster(
    matrix(c(1, 0.01, 2, 0.02, 4, 0.03), nrow = 2),
    nlyrs = 3L
  )
  terra::time(current) <- as.Date("2026-09-09")
  comparison <- prism_water_year_comparison_rasters(
    current, reference, "2026-09-09", minimum_normal_inches = 0.10
  )

  testthat::expect_equal(as.numeric(terra::values(comparison$normal)), c(7 / 3, 0.02))
  testthat::expect_equal(
    as.numeric(terra::values(comparison$percent_normal)),
    c(900 / 7, NA_real_)
  )
  testthat::expect_equal(
    as.numeric(terra::values(comparison$percentile_rank))[[1L]],
    65,
    tolerance = 1e-7
  )
  testthat::expect_equal(as.Date(terra::time(comparison$percentile_rank)), as.Date("2026-09-09"))
})

testthat::test_that("water-year maps use fixed product scales", {
  raster <- make_water_year_comparison_raster(c(25, 75))
  terra::time(raster) <- as.Date("2026-09-09")
  total_plot <- build_prism_water_year_map(raster, "total")
  normal_plot <- build_prism_water_year_map(raster, "percent-normal")
  rank_plot <- build_prism_water_year_map(raster, "percentile-rank")

  testthat::expect_s3_class(total_plot, "ggplot")
  testthat::expect_equal(total_plot$scales$scales[[1L]]$limits, c(0, 50))
  testthat::expect_equal(normal_plot$scales$scales[[1L]]$limits, c(0, 200))
  testthat::expect_equal(rank_plot$scales$scales[[1L]]$limits, c(0, 100))
  testthat::expect_match(rank_plot$labels$title, "Water year 2026", fixed = TRUE)
})
