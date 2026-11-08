for (file in c("prism-monthly.R", "prism-monthly-audit.R", "prism-monthly-temperature.R",
    "prism-monthly-precipitation.R", "prism-monthly-ranking-pilots.R", "prism-monthly-spi.R")) {
  source(file.path(project_root, "R", file))
}

testthat::test_that("gamma MLE matches an independent numerical optimizer", {
  testthat::skip_if_not_installed("MASS")
  result <- validate_prism_monthly_spi_methods()
  testthat::expect_true(all(result$status == "PASS"))
})

testthat::test_that("SPI is scale invariant, monotone, and handles mixed-zero probability", {
  x <- c(rep(0, 15), stats::qgamma((seq_len(135) - .5) / 135, shape = 2, scale = 2))
  fit <- fit_prism_monthly_spi_gamma(matrix(x, nrow = 1))
  testthat::expect_equal(fit$fit_status, 0L)
  testthat::expect_equal(fit$zero_fraction, .1)
  zero <- evaluate_prism_monthly_spi(0, fit)
  testthat::expect_equal(zero$spi, stats::qnorm(.1))
  lo <- evaluate_prism_monthly_spi(1, fit)$spi
  hi <- evaluate_prism_monthly_spi(8, fit)$spi
  testthat::expect_gt(hi, lo)
  millimeters <- fit_prism_monthly_spi_gamma(matrix(x * 25.4, nrow = 1))
  testthat::expect_equal(evaluate_prism_monthly_spi(8 * 25.4, millimeters)$spi, hi, tolerance = 1e-7)
  testthat::expect_equal(evaluate_prism_monthly_spi(NA_real_, fit)$spi_status, 6L)
})

testthat::test_that("SPI withholds bad fits instead of using percentiles as a fallback", {
  gamma <- stats::qgamma((seq_len(120) - .5) / 120, 2)
  x <- rbind(gamma, rep(0, 120), rep(1, 120), c(gamma[1:70], rep(NA, 50)),
    c(rep(1, 60), rep(100, 60)), c(rep(0, 60), gamma[1:60]))
  fitted <- fit_prism_monthly_spi_gamma(x)
  testthat::expect_equal(fitted$fit_status, c(0L, 3L, 4L, 1L, 7L, 3L))
  result <- evaluate_prism_monthly_spi(rep(1, 6), fitted)
  testthat::expect_true(all(is.na(result$spi[-1])))
  tail <- evaluate_prism_monthly_spi(0, fitted[1, ])
  testthat::expect_true(is.finite(tail$spi))
  testthat::expect_equal(tail$probability_clipped, 1)
  testthat::expect_error(fit_prism_monthly_spi_gamma(matrix(-1, nrow = 1)), "negative")
})

testthat::test_that("SPI classification treats threshold endpoints correctly", {
  testthat::expect_equal(prism_monthly_spi_display(c(-2, -1.5, -1, 0, 1, 1.5, 2, NA, NA),
    c(rep(TRUE, 8), FALSE)), c(1, 2, 3, 4, 5, 6, 7, 8, NA))
})

testthat::test_that("SPI batch reuses outputs and calibration when forced to redraw", {
  testthat::skip_if_not_installed("MASS")
  root <- tempfile("spi-batch-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  box <- c(0, 0, 2/24, 2/24); cache <- file.path(root, "cache")
  plan <- plan_prism_monthly_download(start = "2020-01", end = "2023-12", cache_dir = cache, bbox = box)
  fetch <- function(item, destination) {
    r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2/24, ymin = 0, ymax = 2/24, crs = "EPSG:4326")
    year <- as.integer(substr(item$month, 1, 4)) - 2019
    value <- if (item$variable == "pcpn") year else 10 + year + if (item$variable == "maxt") 2 else -2
    terra::values(r) <- c(value, value, value, NA); terra::time(r) <- prism_monthly_month(item$month)
    terra::writeRaster(r, destination)
  }
  download_prism_monthly_plan(plan, max_requests = Inf, delay_seconds = 0, fetch = fetch)
  policy <- prism_monthly_spi_policy()
  policy$calibration_start <- 2020L; policy$calibration_end <- 2022L
  policy$min_years <- 2L; policy$min_positive <- 2L; policy$max_positive_cdf_error <- 1
  run <- function(force = FALSE) build_prism_monthly_spi_pilots(end = "2023-12", durations = c(1L, 3L, 6L, 12L),
    cache_dir = cache, output_dir = file.path(root, "out"), fit_dir = file.path(root, "fits"),
    audit_dir = file.path(root, "audit"), start = "2020-01", policy = policy,
    bbox = box, make_maps = FALSE, force = force)
  first <- run()
  testthat::expect_equal(first$summary$status, "READY")
  testthat::expect_equal(first$summary$built, 4)
  testthat::expect_true(all(!first$results$fit_reused))
  again <- run()
  testthat::expect_equal(again$summary$reused, 4)
  redraw <- run(TRUE)
  testthat::expect_equal(redraw$summary$built, 4)
  testthat::expect_true(all(redraw$results$fit_reused))
})
