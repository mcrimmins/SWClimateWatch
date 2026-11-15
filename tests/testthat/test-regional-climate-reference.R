source(file.path(project_root, "R/prism-monthly.R"))
source(file.path(project_root, "R/prism-monthly-temperature.R"))
source(file.path(project_root, "R/prism-monthly-precipitation.R"))
source(file.path(project_root, "R/regional-climate-reference.R"))

testthat::test_that("reference code signatures ignore source annotations", {
  plain <- function(x) x + 1
  annotated <- plain
  attr(body(annotated), "srcref") <- "different caller annotation"
  testthat::expect_identical(regional_reference_function_text(list(plain)),
    regional_reference_function_text(list(annotated)))
})

testthat::test_that("reference means require complete years separately for rain and temperature", {
  p <- rbind(c(0, 0), c(12, 24), c(NA, 24), c(5, 7), c(NA, NA))
  t <- rbind(c(50, 70), c(NA, 70), c(40, 60), c(-10, 10), c(NA, NA))
  x <- regional_reference_statistics(p, t)
  testthat::expect_equal(x[, "precipitation_inches"], c(0, 18, NA, 6, NA))
  testthat::expect_equal(x[, "mean_temperature_f"], c(60, NA, 50, 0, NA))
  testthat::expect_equal(x[, "precipitation_years"], c(2, 2, 1, 2, 0))
  testthat::expect_equal(x[, "temperature_years"], c(2, 1, 2, 2, 0))
  testthat::expect_false(any(is.nan(x)))
  testthat::expect_error(regional_reference_statistics(matrix(-1, 1, 2), matrix(0, 1, 2)), "negative")
})

testthat::test_that("annual windows use actual leap-day weights and never fill missing months", {
  root <- tempfile(); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  grid <- terra::rast(nrows = 1, ncols = 4, xmin = -112, xmax = -111, ymin = 34, ymax = 35, crs = "EPSG:4326")
  plan <- expand.grid(variable = c("maxt", "mint", "pcpn"),
    month = format(seq(as.Date("1999-01-01"), as.Date("2000-12-01"), by = "month"), "%Y-%m"), stringsAsFactors = FALSE)
  plan$path <- file.path(root, paste0(plan$variable, "-", plan$month, ".tif")); plan$complete <- TRUE
  for (i in seq_len(nrow(plan))) {
    month <- as.integer(substr(plan$month[i], 6, 7)); variable <- plan$variable[i]
    values <- switch(variable, maxt = rep(if (month == 2) 90 else 30, 4),
      mint = rep(if (month == 2) 70 else 10, 4), pcpn = rep(month, 4))
    if (variable == "pcpn") {
      values[4] <- 0
      if (month == 2) values[2] <- NA
    }
    if (variable == "maxt" && month == 6) values[3] <- 0 # max below min
    terra::writeRaster(terra::setValues(grid, values), plan$path[i], datatype = "FLT4S")
  }
  p <- prism_monthly_precipitation_window(plan, "2000-12", 12L)
  t99 <- prism_monthly_temperature_window(plan, "1999-12", 12L)
  t00 <- prism_monthly_temperature_window(plan, "2000-12", 12L)
  # Independent expectations use daily sequence expansion, not the production weight helper.
  expected <- vapply(c(1999L, 2000L), function(year) {
    days <- seq(as.Date(sprintf("%d-01-01", year)), as.Date(sprintf("%d-12-31", year)), by = "day")
    mean(ifelse(format(days, "%m") == "02", 80, 20))
  }, numeric(1))
  testthat::expect_equal(terra::values(p, mat = FALSE), c(78, NA, 78, 0))
  testthat::expect_equal(terra::values(t99, mat = FALSE), c(expected[1], expected[1], NA, expected[1]))
  testthat::expect_equal(terra::values(t00, mat = FALSE), c(expected[2], expected[2], NA, expected[2]))
  statistics <- regional_reference_statistics(cbind(terra::values(p, mat = FALSE), terra::values(p, mat = FALSE)),
    cbind(terra::values(t99, mat = FALSE), terra::values(t00, mat = FALSE)))
  testthat::expect_equal(unname(statistics[1, "mean_temperature_f"]), mean(expected))
  testthat::expect_true(abs(mean(expected) - weighted.mean(expected, c(365, 366))) > 1e-5)
  plan$complete[plan$variable == "pcpn" & plan$month == "2000-02"] <- FALSE
  testthat::expect_error(prism_monthly_precipitation_window(plan, "2000-12", 12L), "unverified")
})

testthat::test_that("reference display preserves tails, zeros and unavailable values", {
  testthat::expect_equal(as.character(regional_reference_classes(c(0, 4, 60, 80, NA), "precipitation")),
    c("<4", "4-8", ">=60", ">=60", "Unavailable"))
  testthat::expect_equal(as.character(regional_reference_classes(c(-5, 30, 40, 80, 95, NA), "temperature")),
    c("<30", "30-40", "40-45", ">=80", ">=80", "Unavailable"))
})
