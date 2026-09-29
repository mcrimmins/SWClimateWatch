source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "audit-snodas.R"))
source(file.path(project_root, "R", "snodas-inventory.R"))
source(file.path(project_root, "R", "snodas-bootstrap.R"))
source(file.path(project_root, "R", "snodas-baseline.R"))
source(file.path(project_root, "R", "snodas-grid.R"))
source(file.path(project_root, "R", "snodas-analysis-qc.R"))
source(file.path(project_root, "R", "snodas-climatology-pilot.R"))
source(file.path(project_root, "R", "snodas-climatology-window-pilot.R"))

testthat::test_that("five-day plan stays within each water year", {
  plan <- plan_snodas_window_baseline_day("12-15", 2019:2020,
                                           tempfile("missing-processed-"),
                                           known_missing_dates = as.Date(character()))
  testthat::expect_equal(nrow(plan), 10L)
  testthat::expect_equal(plan$date[1:5],
                         seq(as.Date("2018-12-13"), as.Date("2018-12-17"),
                             by = "day"))
  testthat::expect_equal(plan$offset_days[1:5], -2L:2L)
  testthat::expect_false(any(plan$ready))
  edge <- plan_snodas_window_baseline_day(
    "10-01", 2019, known_missing_dates = as.Date(character()))
  testthat::expect_equal(edge$date,
                         as.Date(c("2018-10-01", "2018-10-02", "2018-10-03")))
  testthat::expect_equal(edge$offset_days, 0L:2L)
  late <- plan_snodas_window_baseline_day(
    "05-31", 2019, known_missing_dates = as.Date(character()))
  testthat::expect_equal(late$offset_days, -2L:0L)
})

testthat::test_that("five-day summaries preserve one equal-weighted year", {
  template <- terra::rast(nrows = 1, ncols = 2, xmin = -111, xmax = -110,
                          ymin = 35, ymax = 36, crs = "EPSG:4326")
  make_layer <- function(values) {
    x <- template
    terra::values(x) <- values
    x
  }
  year_one <- do.call(c, lapply(list(
    c(0, 0), c(0, 0), c(0.2, 0), c(0.2, 0), c(0.2, 0)
  ), make_layer))
  year_two <- do.call(c, lapply(list(
    c(0.2, 1), c(0.2, 1), c(0.2, NA), c(NA, NA), c(NA, NA)
  ), make_layer))
  one <- summarize_snodas_window_year(year_one, min_valid_days = 3L)
  two <- summarize_snodas_window_year(year_two, min_valid_days = 3L)
  testthat::expect_equal(as.vector(terra::values(one$median_swe)),
                         c(0.2, 0), tolerance = 1e-6)
  testthat::expect_equal(as.vector(terra::values(one$snow_fraction)),
                         c(0.6, 0), tolerance = 1e-6)
  testthat::expect_equal(as.vector(terra::values(two$median_swe)),
                         c(0.2, NA), tolerance = 1e-6)
  testthat::expect_equal(as.vector(terra::values(two$snow_fraction)),
                         c(1, NA), tolerance = 1e-6)
  combined <- summarize_snodas_window_years(
    c(one$median_swe, two$median_swe),
    c(one$snow_fraction, two$snow_fraction), min_years = 2L
  )
  testthat::expect_equal(as.vector(terra::values(combined$sample_years)),
                         c(2, 1))
  testthat::expect_equal(as.vector(terra::values(combined$median_swe)),
                         c(0.2, NA), tolerance = 1e-6)
  testthat::expect_equal(as.vector(terra::values(combined$snow_frequency)),
                         c(0.8, NA), tolerance = 1e-6)
})

testthat::test_that("five-day build writes separately and preserves sources", {
  root <- tempfile("snodas-window-pilot-")
  processed_dir <- file.path(root, "processed")
  output_dir <- file.path(root, "window")
  template <- terra::rast(nrows = 1, ncols = 2, xmin = -111, xmax = -110,
                          ymin = 35, ymax = 36, crs = "EPSG:4326")
  centers <- as.Date(c("2019-02-15", "2020-02-15"))
  dates <- do.call(c, lapply(centers, function(x) x + -2L:2L))
  for (index in seq_along(dates)) {
    if (index == 2L) next # Simulate a documented missing day.
    for (variable in c("swe", "depth")) {
      path <- snodas_processed_path(dates[index], variable, processed_dir)
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      grid <- template
      swe <- if (index <= 5L) c(if (index == 1L) 0 else 0.2, 0) else c(0.4, 0)
      terra::values(grid) <- if (variable == "swe") swe else swe + 0.3
      terra::time(grid) <- dates[index]
      terra::writeRaster(grid, path)
      write_snodas_manifest_row(data.frame(
        date = as.character(dates[index]), variable = variable,
        path = path, bytes = file.info(path)$size,
        md5 = unname(tools::md5sum(path)), source_md5 = "sample-source"
      ), snodas_manifest_path("processed", processed_dir),
      c("date", "variable"))
    }
  }
  source_path <- snodas_processed_path(dates[1L], "swe", processed_dir)
  source_md5 <- unname(tools::md5sum(source_path))
  testthat::expect_error(build_snodas_window_baseline_day(
    "02-15", 2019:2020, min_years = 2L,
    processed_dir = processed_dir, template = template,
    output_dir = output_dir,
    known_missing_dates = as.Date(character())
  ), "Missing or unverified")
  result <- build_snodas_window_baseline_day(
    "02-15", 2019:2020, min_years = 2L,
    processed_dir = processed_dir, template = template,
    output_dir = output_dir, known_missing_dates = dates[2L]
  )
  testthat::expect_true(all(file.exists(result$paths)))
  testthat::expect_equal(nrow(result$qc), 10L)
  testthat::expect_equal(sum(result$qc$excluded_cells, na.rm = TRUE), 0)
  testthat::expect_equal(sum(result$qc$availability == "known_missing"), 1)
  testthat::expect_identical(unname(tools::md5sum(source_path)), source_md5)
  testthat::expect_equal(
    as.vector(terra::values(terra::rast(result$paths[["median_swe"]]))),
    c(0.3, 0), tolerance = 1e-6
  )
  testthat::expect_equal(
    as.vector(terra::values(terra::rast(result$paths[["snow_frequency"]]))),
    c(0.875, 0), tolerance = 1e-6
  )
  testthat::expect_equal(
    as.vector(terra::values(terra::rast(result$paths[["sample_years"]]))),
    c(2, 2)
  )
  testthat::expect_error(build_snodas_window_baseline_day(
    "02-15", 2019:2020, min_years = 2L,
    processed_dir = processed_dir, template = template,
    output_dir = output_dir, known_missing_dates = dates[2L]
  ), "already exists")
})
