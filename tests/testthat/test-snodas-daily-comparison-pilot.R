source(file.path(project_root, "R", "snodas-seasonal-anomaly.R"))
source(file.path(project_root, "R", "snodas-daily-comparison-pilot.R"))
source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "snodas-inventory.R"))
source(file.path(project_root, "R", "snodas-bootstrap.R"))

testthat::test_that("missing prior cache stays unavailable without downloading or writing", {
  directory <- tempfile(); dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  template <- terra::rast(nrows = 1, ncols = 1, xmin = -112, xmax = -111,
    ymin = 34, ymax = 35, crs = "EPSG:4326")
  testthat::expect_null(snodas_read_comparison_endpoint(as.Date("2025-02-08"), template,
    processed_dir = directory))
  testthat::expect_length(list.files(directory, recursive = TRUE, all.files = TRUE, no.. = TRUE), 0L)
})

testthat::test_that("seven-day net SWE change requires exact dates and paired finite endpoints", {
  grid <- terra::rast(nrows = 1, ncols = 4, xmin = -112, xmax = -111,
    ymin = 34, ymax = 35, crs = "EPSG:4326")
  current <- terra::setValues(grid, c(0, 1, NA, 5))
  previous <- terra::setValues(grid, c(.5, 0, 3, NA))
  date <- as.Date("2025-02-15")
  terra::time(current) <- date; terra::time(previous) <- date - 7L
  change <- snodas_seven_day_swe_change(current, previous, date)
  testthat::expect_equal(terra::values(change, mat = FALSE), c(-.5, 1, NA, NA))
  testthat::expect_equal(as.Date(terra::time(change)), date)
  terra::time(previous) <- date - 6L
  testthat::expect_error(snodas_seven_day_swe_change(current, previous, date), "endpoint")
  terra::time(previous) <- date - 7L
  testthat::expect_error(snodas_seven_day_swe_change(current, terra::shift(previous, dx = .1), date))
  terra::values(current) <- c(-1, 0, 0, 0)
  testthat::expect_error(snodas_seven_day_swe_change(current, previous, date), "negative")
})

testthat::test_that("daily percentages require date-specific support independently of the median guard", {
  grid <- terra::rast(nrows = 1, ncols = 4, xmin = -112, xmax = -111,
    ymin = 34, ymax = 35, crs = "EPSG:4326")
  make <- function(x) terra::setValues(grid, x)
  observed <- make(c(0, 2, NA, 5)); date <- as.Date("2025-02-15")
  terra::time(observed) <- date
  reference <- make(c(1, .5, 1, 2)); counts <- make(c(21, 21, 21, 17))
  percent <- snodas_daily_percent_swe(observed, reference, counts, date)
  testthat::expect_equal(terra::values(percent$percent_of_median, mat = FALSE), c(0, NA, NA, NA))
  testthat::expect_equal(terra::values(percent$display_status, mat = FALSE), c(1, 2, 3, 3))
  testthat::expect_equal(as.Date(terra::time(percent$percent_of_median)), date)
  testthat::expect_error(snodas_daily_percent_swe(observed, reference, counts, date + 1L), "endpoint")
  testthat::expect_error(snodas_daily_percent_swe(observed, reference, make(c(21, 21, 21, .5)), date), "integers")
  testthat::expect_error(snodas_daily_percent_swe(observed, reference, counts, date, min_years = 0), "positive integer")
  testthat::expect_match(levels(snodas_peak_percent_classes(NA_real_, 2L,
    reference_label = "Typical SWE"))[9L], "Typical SWE", fixed = TRUE)
})
