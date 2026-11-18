source(file.path(project_root, "R", "prism-monthly.R"))
source(file.path(project_root, "R", "prism-monthly-audit.R"))
source(file.path(project_root, "R", "prism-monthly-temperature.R"))

testthat::test_that("monthly windows cross years and weight leap February correctly", {
  testthat::expect_equal(format(prism_monthly_window("2026-10"), "%Y-%m"),
    c("2025-11", "2025-12", sprintf("2026-%02d", 1:10)))
  testthat::expect_equal(unname(prism_monthly_day_weights(as.Date(c("2020-01-01", "2020-02-01")))), c(31, 29))
  testthat::expect_equal(unname(prism_monthly_day_weights(as.Date("2021-02-01"))), 28)
  testthat::expect_error(prism_monthly_window("2020-01", 1.5), "whole")
})

testthat::test_that("ranking includes current once, averages ties, and withholds low support", {
  x <- rbind(c(1, 2, 3, 4), c(2, 2, 2, 2), c(1, NA, NA, 4), c(1, 2, 3, NA))
  s <- prism_monthly_temperature_statistics(x, 2000:2003, 2003,
    min_years = 2, min_fraction = .75, normal_years = 2000:2002, min_normal_years = 3)
  testthat::expect_equal(unname(s[1, c("percentile", "warm_rank", "cold_rank")]), c(87.5, 1, 4))
  testthat::expect_equal(unname(s[2, c("percentile", "warm_rank", "cold_rank")]), c(50, 2.5, 2.5))
  testthat::expect_true(all(is.na(s[3:4, "percentile"])))
  testthat::expect_equal(unname(s[1, "departure_f"]), 2)
  testthat::expect_true(is.na(s[3, "departure_f"]))
  testthat::expect_error(prism_monthly_temperature_statistics(x, c(2000, 2001, 2003, 2003), 2003), "unique")
})

testthat::test_that("temperature aggregation uses day weights and does not fill cell gaps", {
  root <- tempfile("monthly-weights-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  plan <- expand.grid(variable = c("maxt", "mint"), month = c("2020-01", "2020-02"), stringsAsFactors = FALSE)
  plan$path <- file.path(root, paste0(plan$variable, plan$month, ".tif"))
  plan$complete <- TRUE
  for (i in seq_len(nrow(plan))) {
    r <- terra::rast(nrows = 1, ncols = 2, xmin = 0, xmax = 2/24, ymin = 0, ymax = 1/24)
    mean <- if (plan$month[i] == "2020-01") 0 else 10
    value <- mean + if (plan$variable[i] == "maxt") 2 else -2
    terra::values(r) <- c(value, if (plan$month[i] == "2020-02") NA else value)
    terra::writeRaster(r, plan$path[i])
  }
  result <- terra::values(prism_monthly_temperature_window(plan, "2020-02", 2L), mat = FALSE)
  testthat::expect_equal(result, c(290/60, NA))
})

testthat::test_that("audit and pilot enforce complete windows and resume audit safely", {
  root <- tempfile("monthly-analysis-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  box <- c(0, 0, 2/24, 2/24)
  cache <- file.path(root, "cache"); reports <- file.path(root, "audit")
  plan <- plan_prism_monthly_download(start = "2020-01", end = "2022-12", cache_dir = cache, bbox = box)
  fetch <- function(item, destination) {
    r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2/24,
      ymin = 0, ymax = 2/24, crs = "EPSG:4326")
    year <- as.integer(substr(item$month, 1, 4))
    value <- if (item$variable == "pcpn") 1 else (year - 2019) * 5 + if (item$variable == "maxt") 2 else -2
    terra::values(r) <- c(value, value, value, NA)
    terra::time(r) <- prism_monthly_month(item$month)
    terra::writeRaster(r, destination)
  }
  download_prism_monthly_plan(plan, max_requests = Inf, delay_seconds = 0, fetch = fetch)
  audit <- audit_prism_monthly_cache("2020-01", "2022-12", cache, reports, box)
  testthat::expect_equal(audit$summary$status, "PASS")
  testthat::expect_equal(audit$summary$months, 36)
  repeated <- audit_prism_monthly_cache("2020-01", "2022-12", cache, reports, box)
  testthat::expect_equal(repeated$summary$reused_months, 36)
  window <- prism_monthly_temperature_window(audit$plan, "2020-12")
  testthat::expect_equal(terra::values(window, mat = FALSE), c(5, 5, 5, NA))
  incomplete <- audit$plan
  incomplete$complete[incomplete$month == "2020-02"] <- FALSE
  testthat::expect_error(prism_monthly_temperature_window(incomplete, "2020-12"), "unverified")
  pilot <- build_prism_monthly_temperature_pilot(end = "2022-12", start = "2020-01", cache_dir = cache,
    output_dir = file.path(root, "pilot"), audit_dir = reports, bbox = box, min_years = 2, make_map = FALSE)
  testthat::expect_equal(pilot$summary$comparison_windows, 3)
  testthat::expect_equal(pilot$summary$supported_cells, 3)
  testthat::expect_equal(terra::values(terra::rast(pilot$paths[["warm_rank"]]), mat = FALSE), c(1, 1, 1, NA))
  unlink(plan$path[1])
  changed <- audit_prism_monthly_cache("2020-01", "2022-12", cache, reports, box)
  testthat::expect_equal(changed$summary$status, "FAIL")
  testthat::expect_equal(changed$summary$failed_months, 1)
})
