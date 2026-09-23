testthat::test_that("configured display modes can be supplied for an update run", {
  old <- options(swc.map.product.scale_modes = c(
    maxt_percentile_daily = "categorical"
  ))
  on.exit(options(old), add = TRUE)

  testthat::expect_equal(
    configured_map_product_scale("maxt_percentile_daily"),
    "categorical"
  )
  testthat::expect_equal(
    configured_map_product_scale("unknown_product"),
    "continuous"
  )
})

testthat::test_that("categorical families use interpretable climate classes", {
  percentile <- map_product_categorical_classes(
    "pcpn_percentile_30day", c(0, 10, 25, 50, 75, 90, 100), c(0, 100)
  )
  percent_normal <- map_product_categorical_classes(
    "pcpn_percent_normal_30day", c(0, 50, 75, 100, 125, 150, 200), c(0, 200)
  )
  departure <- map_product_categorical_classes(
    "tmean_departure_daily", c(-30, -20, -10, 0, 10, 20, 30), c(-30, 30)
  )

  testthat::expect_equal(percentile$breaks, c(0, 2, 10, 33, 67, 90, 98, 100))
  testthat::expect_equal(
    percentile$labels,
    c(
      "<=2\nnear-record low", "2-10\nmuch below", "10-33\nbelow",
      "33-67\nnear normal", "67-90\nabove", "90-98\nmuch above",
      ">98\nnear-record high"
    )
  )
  testthat::expect_true("90-110%" %in% percent_normal$labels)
  testthat::expect_true("-5-5" %in% departure$labels)
})

testthat::test_that("categorical mode creates a discrete map legend", {
  raster <- terra::rast(
    ncols = 2, nrows = 2,
    xmin = -115, xmax = -103,
    ymin = 31, ymax = 37,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- c(5, 20, 60, 95)
  terra::time(raster) <- as.Date("2026-09-09")
  old <- options(swc.map.product.scale_modes = c(
    maxt_percentile_daily = "categorical"
  ))
  on.exit(options(old), add = TRUE)

  plot <- build_prism_percentile_rank_map(raster, "maxt", "2026-09-09")
  built <- ggplot2::ggplot_build(plot)
  fill_scale <- built$plot$scales$get_scales("fill")

  testthat::expect_s3_class(fill_scale, "ScaleDiscrete")
  testthat::expect_equal(
    as.character(fill_scale$get_breaks()),
    c(
      "<=2\nnear-record low", "2-10\nmuch below", "10-33\nbelow",
      "33-67\nnear normal", "67-90\nabove", "90-98\nmuch above",
      ">98\nnear-record high"
    )
  )
})
