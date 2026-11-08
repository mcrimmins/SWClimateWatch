source(file.path(project_root, "R", "prism-monthly.R"))
source(file.path(project_root, "R", "prism-monthly-audit.R"))
source(file.path(project_root, "R", "prism-monthly-temperature.R"))
source(file.path(project_root, "R", "prism-monthly-temperature-check.R"))

testthat::test_that("independent daily expansion includes leap days and requires every month", {
  monthly <- data.frame(month = c("2020-01", "2020-02"), maxt = c(2, 12), mint = c(-2, 8))
  testthat::expect_equal(prism_monthly_check_window(monthly, "2020-02", 2), 290/60)
  monthly$month <- c("2021-01", "2021-02")
  testthat::expect_equal(prism_monthly_check_window(monthly, "2021-02", 2), 280/59)
  testthat::expect_true(is.na(prism_monthly_check_window(monthly[1, ], "2021-02", 2)))
  monthly$mint[2] <- 20
  testthat::expect_true(is.na(prism_monthly_check_window(monthly, "2021-02", 2)))
})

testthat::test_that("independent base ranks agree on ties, direction, and insufficient support", {
  result <- prism_monthly_check_statistics(c(1, 2, 2, 4), 2000:2003, 2002, min_years = 2)
  testthat::expect_equal(unname(result[c("warm_rank", "cold_rank", "percentile")]), c(2.5, 2.5, 50))
  missing <- prism_monthly_check_statistics(c(1, NA, NA, 4), 2000:2003, 2003, min_years = 2)
  testthat::expect_true(is.na(missing[["percentile"]]))
  testthat::expect_identical(prism_monthly_check_close(c(NA, NA, 1), c(NA, 2, 2)), c(TRUE, FALSE, FALSE))
})

testthat::test_that("independent point checks validate saved outputs and detect a changed raster", {
  root <- tempfile("monthly-check-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  box <- c(0, 0, 2/24, 2/24)
  cache <- file.path(root, "cache"); pilot_dir <- file.path(root, "pilot")
  plan <- plan_prism_monthly_download(start = "2020-01", end = "2022-12", cache_dir = cache, bbox = box)
  fetch <- function(item, destination) {
    r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2/24, ymin = 0, ymax = 2/24, crs = "EPSG:4326")
    base <- (as.integer(substr(item$month, 1, 4)) - 2019) * 5 + as.integer(substr(item$month, 6, 7))
    value <- if (item$variable == "pcpn") 1 else base + if (item$variable == "maxt") 2 else -2
    terra::values(r) <- c(value, value, value, NA)
    terra::time(r) <- prism_monthly_month(item$month)
    terra::writeRaster(r, destination)
  }
  download_prism_monthly_plan(plan, max_requests = Inf, delay_seconds = 0, fetch = fetch)
  build_prism_monthly_temperature_pilot(end = "2022-12", duration = 2L, start = "2020-01", cache_dir = cache,
    output_dir = pilot_dir, audit_dir = file.path(root, "audit"), bbox = box, min_years = 2, make_map = FALSE)
  points <- data.frame(location = "test grid cell", longitude = 1/48, latitude = 3/48)
  run <- function() check_prism_monthly_temperature_pilot(pilot_dir = pilot_dir,
    report_dir = file.path(root, "check"), cache_dir = cache, start = "2020-01",
    historical_year = 2021, points = points, bbox = box, min_years = 2)
  first <- run()
  testthat::expect_equal(first$summary$status, "PASS")
  testthat::expect_false(first$summary$point_cache_reused)
  second <- run()
  testthat::expect_true(second$summary$point_cache_reused)
  # Alter one output while preserving its date: a stale/incorrect map must fail.
  path <- file.path(pilot_dir, "warm_rank.tif")
  r <- terra::rast(path); r <- r + 1
  terra::time(r) <- as.Date("2022-12-01")
  temporary <- file.path(root, "altered.tif")
  terra::writeRaster(r, temporary)
  r <- NULL
  file.copy(temporary, path, overwrite = TRUE)
  changed <- run()
  testthat::expect_equal(changed$summary$status, "FAIL")
  testthat::expect_true(any(changed$comparisons$metric == "warm_rank" & changed$comparisons$status == "FAIL"))
})
