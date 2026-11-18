source(file.path(project_root, "R/prism-monthly.R"))
source(file.path(project_root, "R/prism-monthly-temperature.R"))
source(file.path(project_root, "R/prism-monthly-precipitation.R"))
source(file.path(project_root, "R/regional-climate-reference.R"))
source(file.path(project_root, "R/regional-seasonal-reference.R"))

testthat::test_that("calendar quarters partition the year with clear labels and common scales", {
  seasons <- regional_reference_seasons()
  testthat::expect_identical(names(seasons), c("winter", "spring", "summer", "fall"))
  testthat::expect_identical(unname(unlist(lapply(seasons, `[[`, "months"))), 1:12)
  testthat::expect_equal(seasons$winter$text, "January-March")
  testthat::expect_equal(seasons$summer$text, "July-September")
  for (variable in c("precipitation", "temperature")) {
    style <- regional_seasonal_style(variable)
    testthat::expect_equal(length(style$colors), length(style$labels))
    testthat::expect_equal(length(style$breaks), length(style$labels) + 1L)
  }
  testthat::expect_equal(as.character(regional_seasonal_classes(c(0, .5, 16, 25, NA), "precipitation")),
    c("<0.5", "0.5-1", ">=16", ">=16", "Unavailable"))
  testthat::expect_equal(as.character(regional_seasonal_classes(c(-10, 20, 90, 100, NA), "temperature")),
    c("<20", "20-30", ">=90", ">=90", "Unavailable"))
})

testthat::test_that("seasonal references retain leap days, zero rain and independent period coverage", {
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
    if (variable == "maxt" && month == 2) values[3] <- 0
    terra::writeRaster(terra::setValues(grid, values), plan$path[i], datatype = "FLT4S")
  }
  winter <- regional_seasonal_statistics(plan, 1999:2000, "winter")$statistics
  spring <- regional_seasonal_statistics(plan, 1999:2000, "spring")$statistics
  summer <- regional_seasonal_statistics(plan, 1999:2000, "summer")$statistics
  fall <- regional_seasonal_statistics(plan, 1999:2000, "fall")$statistics
  expected_t <- mean(vapply(1999:2000, function(year) {
    dates <- seq(as.Date(sprintf("%d-01-01", year)), as.Date(sprintf("%d-03-31", year)), by = "day")
    mean(ifelse(format(dates, "%m") == "02", 80, 20))
  }, numeric(1)))
  testthat::expect_equal(unname(winter[, "precipitation_inches"]), c(6, NA, 6, 0))
  testthat::expect_equal(unname(winter[, "mean_temperature_f"]), c(expected_t, expected_t, NA, expected_t))
  testthat::expect_equal(unname(spring[, "precipitation_inches"]), c(15, 15, 15, 0))
  testthat::expect_equal(unname(summer[, "mean_temperature_f"]), rep(20, 4))
  testthat::expect_equal(unname(summer[, "precipitation_inches"]), c(24, 24, 24, 0))
  testthat::expect_equal(unname(fall[, "precipitation_inches"]), c(33, 33, 33, 0))
  testthat::expect_equal(unname(winter[, "precipitation_inches"] + spring[, "precipitation_inches"] +
    summer[, "precipitation_inches"] + fall[, "precipitation_inches"]), c(78, NA, 78, 0))
  testthat::expect_equal(unname(winter[, "temperature_years"]), c(2, 2, 0, 2))
  testthat::expect_equal(unname(summer[, "temperature_years"]), rep(2, 4))
  testthat::expect_error(regional_seasonal_statistics(plan, 1999:2000, "djf"), "Choose")
})
