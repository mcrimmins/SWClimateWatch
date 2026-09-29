source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "audit-snodas.R"))
source(file.path(project_root, "R", "snodas-inventory.R"))
source(file.path(project_root, "R", "snodas-bootstrap.R"))
source(file.path(project_root, "R", "snodas-grid.R"))
source(file.path(project_root, "R", "snodas-analysis-qc.R"))
source(file.path(project_root, "R", "map-product-scales.R"))
source(file.path(project_root, "R", "snodas-seasonal-archive.R"))

testthat::test_that("seasonal peak and snow-day count honor coverage", {
  template <- terra::rast(nrows = 1, ncols = 4, xmin = -111, xmax = -110,
                          ymin = 35, ymax = 36, crs = "EPSG:4326")
  dates <- as.Date(c("2023-10-01", "2023-10-02", "2023-10-03",
                     "2023-10-04"))
  values <- list(c(0, 0.2, 1, NA), c(0, 1.5, NA, NA),
                 c(0, 2, 0.5, NA), c(0, NA, 3, NA))
  read_day <- function(date) {
    raster <- terra::setValues(template, values[[match(date, dates)]])
    list(swe = raster, excluded_cells = if (date == dates[3L]) 1L else 0L)
  }
  result <- snodas_seasonal_summary(
    dates, template, read_day, expected_days = 4L,
    minimum_coverage = 0.75, progress_every = 4L)
  testthat::expect_equal(
    as.vector(terra::values(result$peak_swe)), c(0, 2, 3, NA))
  testthat::expect_equal(
    as.vector(terra::values(result$snow_days)), c(0, 3, 3, NA))
  testthat::expect_equal(
    as.vector(terra::values(result$coverage)), c(1, 0.75, 0.75, 0))
  testthat::expect_equal(result$metrics$days_with_pairwise_exclusions, 1L)
  testthat::expect_equal(
    snodas_seasonal_quality_gate(result$metrics)$status, "REVIEW")
})

testthat::test_that("seasonal gate blocks empty coverage and flags high peaks", {
  metrics <- data.frame(sufficient_coverage_cells = 2L,
                        peak_cells_for_review = 0L,
                        days_with_pairwise_exclusions = 0L,
                        known_missing_days = 0L)
  testthat::expect_equal(
    snodas_seasonal_quality_gate(metrics)$status, "PASS")
  metrics$peak_cells_for_review <- 1L
  testthat::expect_equal(
    snodas_seasonal_quality_gate(metrics)$status, "REVIEW")
  metrics$sufficient_coverage_cells <- 0L
  testthat::expect_equal(
    snodas_seasonal_quality_gate(metrics)$status, "FAIL")
})

testthat::test_that("reviewed WY2016 peak mask is local and source guarded", {
  rules <- snodas_seasonal_peak_qc_rules(2016L)
  testthat::expect_equal(nrow(rules), 1L)
  testthat::expect_equal(nrow(snodas_seasonal_peak_qc_rules(2017L)), 0L)
  grid <- terra::rast(
    nrows = 1L, ncols = 2L, xmin = -111.0083333,
    xmax = -110.9916667, ymin = 34.3666667,
    ymax = 34.375, crs = "EPSG:4326"
  )
  original <- terra::setValues(grid, c(53.50394, 7))
  dates <- as.Date("2016-03-01")
  md5 <- "example-source-md5"
  old_signature <- digest::digest(c(
    as.character(dates), md5,
    as.character(terra::ext(grid)), as.character(terra::res(grid)),
    as.character(c(terra::nrow(grid), terra::ncol(grid))),
    "seasonal-peak-snowdays-v1", "threshold=0.1", "coverage=0.9"
  ), algo = "sha256")
  testthat::expect_identical(snodas_seasonal_source_signature(
    dates, md5, grid, 2017L), old_signature)
  testthat::expect_false(identical(snodas_seasonal_source_signature(
    dates, md5, grid, 2016L), old_signature))
  legacy_rule <- data.frame(
    water_year = 2016L,
    rule_id = "wy2016-promontory-peak-swe",
    longitude = -111.0042, latitude = 34.3708,
    expected_peak_inches = 53.50394,
    tolerance_inches = 0.01, stringsAsFactors = FALSE
  )
  legacy_rule <- legacy_rule[legacy_rule$water_year == 2016L, , drop = FALSE]
  legacy_signature <- digest::digest(c(
    as.character(dates), md5,
    as.character(terra::ext(grid)), as.character(terra::res(grid)),
    as.character(c(terra::nrow(grid), terra::ncol(grid))),
    "seasonal-peak-snowdays-v1", "threshold=0.1", "coverage=0.9",
    digest::digest(legacy_rule, algo = "sha256")
  ), algo = "sha256")
  testthat::expect_identical(snodas_seasonal_source_signature(
    dates, md5, grid, 2016L), legacy_signature)
  masked <- snodas_apply_seasonal_peak_qc(original, rules)
  testthat::expect_equal(masked$masked_cells, 1L)
  testthat::expect_equal(masked$original_inches, 53.50394)
  testthat::expect_equal(as.vector(terra::values(masked$raster)),
                         c(NA_real_, 7))
  testthat::expect_equal(as.vector(terra::values(original)),
                         c(53.50394, 7))
  unchanged <- snodas_apply_seasonal_peak_qc(
    original, snodas_seasonal_peak_qc_rules(2017L))
  testthat::expect_equal(unchanged$masked_cells, 0L)
  testthat::expect_equal(as.vector(terra::values(unchanged$raster)),
                         c(53.50394, 7))
  testthat::expect_error(
    snodas_apply_seasonal_peak_qc(
      terra::setValues(grid, c(45, 7)), rules),
    "source value changed"
  )
  metrics <- data.frame(
    sufficient_coverage_cells = 2L, peak_cells_for_review = 0L,
    days_with_pairwise_exclusions = 0L, known_missing_days = 0L,
    peak_qc_masked_cells = 1L
  )
  testthat::expect_equal(
    snodas_seasonal_quality_gate(metrics)$status, "REVIEW")
})

testthat::test_that("reviewed WY2014 mask leaves nearby peak cells intact", {
  rules <- snodas_seasonal_peak_qc_rules(2014L)
  testthat::expect_equal(nrow(rules), 1L)
  testthat::expect_equal(rules$rule_id, "wy2014-wolf-creek-peak-swe")
  grid <- terra::rast(
    nrows = 1L, ncols = 2L, xmin = -106.7916667,
    xmax = -106.775, ymin = 37.4833333,
    ymax = 37.4916667, crs = "EPSG:4326"
  )
  original <- terra::setValues(grid, c(72.87402, 32))
  masked <- snodas_apply_seasonal_peak_qc(original, rules)
  testthat::expect_equal(masked$masked_cells, 1L)
  testthat::expect_equal(masked$original_inches, 72.87402)
  testthat::expect_equal(as.vector(terra::values(masked$raster)),
                         c(NA_real_, 32))
  testthat::expect_equal(as.vector(terra::values(original)),
                         c(72.87402, 32))
  testthat::expect_error(
    snodas_apply_seasonal_peak_qc(
      terra::setValues(grid, c(35, 32)), rules),
    "source value changed"
  )
  testthat::expect_false(identical(
    snodas_seasonal_source_signature(
      as.Date("2014-04-07"), "source-md5", grid, 2014L),
    snodas_seasonal_source_signature(
      as.Date("2014-04-07"), "source-md5", grid, 2017L)
  ))
})

testthat::test_that("snow-day classes have consistent labels across years", {
  classes <- map_product_categorical_classes(
    "snodas_snow_days", NULL, c(0, 244))
  testthat::expect_equal(classes$breaks,
                         c(0, 1, 7, 30, 60, 90, 120, 180, 244))
  testthat::expect_equal(tail(classes$labels, 1L), ">180")
  testthat::expect_equal(snodas_seasonal_map_key("peak_swe"),
                         "peak_map")
  testthat::expect_equal(snodas_seasonal_map_key("snow_days"),
                         "snow_days_map")
})
