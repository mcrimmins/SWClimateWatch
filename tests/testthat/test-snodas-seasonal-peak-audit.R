source(file.path(project_root, "R", "snodas-seasonal-peak-audit.R"))

testthat::test_that("peak provenance records timing, persistence, and patches", {
  template <- terra::rast(nrows = 3, ncols = 4, xmin = -111,
                          xmax = -107, ymin = 33, ymax = 36,
                          crs = "EPSG:4326")
  dates <- as.Date("2017-01-01") + 0:4
  daily_values <- list(
    c(51, 52, rep(0, 9), 55),
    c(55, 52, rep(0, 10)),
    c(60, 52, rep(0, 10)),
    c(58, 52, rep(0, 10)),
    c(52, 52, rep(0, 10))
  )
  peak <- terra::setValues(template, c(60, 52, rep(0, 9), 55))
  read_day <- function(date) {
    terra::setValues(template, daily_values[[match(date, dates)]])
  }
  evidence <- snodas_seasonal_peak_evidence(
    dates, peak, read_day, radius_days = 1L, progress_every = 5L)
  testthat::expect_equal(nrow(evidence), 3L)
  testthat::expect_equal(evidence$peak_date,
                         c("2017-01-03", "2017-01-01", "2017-01-01"))
  testthat::expect_equal(evidence$patch_cells, c(2L, 2L, 1L))
  testthat::expect_equal(evidence$nearby_near_peak_days, c(3L, 2L, 1L))
  testthat::expect_equal(evidence$peak_difference_inches, c(0, 0, 0))
  testthat::expect_equal(evidence$context[3L], "closer inspection")
})

testthat::test_that("peak provenance rejects a mapped peak absent in daily data", {
  template <- terra::rast(nrows = 1, ncols = 1, xmin = -111,
                          xmax = -110, ymin = 34, ymax = 35,
                          crs = "EPSG:4326")
  peak <- terra::setValues(template, 55)
  dates <- as.Date("2017-01-01") + 0:1
  testthat::expect_error(snodas_seasonal_peak_evidence(
    dates, peak, function(date) terra::setValues(template, NA_real_),
    progress_every = 2L), "no valid daily value")
})

testthat::test_that("peak provenance handles years without high cells", {
  template <- terra::rast(nrows = 1, ncols = 1, xmin = -111,
                          xmax = -110, ymin = 34, ymax = 35,
                          crs = "EPSG:4326")
  peak <- terra::setValues(template, 25)
  evidence <- snodas_seasonal_peak_evidence(
    as.Date("2017-01-01"), peak,
    function(date) stop("should not read daily files"))
  testthat::expect_equal(nrow(evidence), 0L)
  testthat::expect_true("peak_date" %in% names(evidence))
})
