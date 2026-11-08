source(file.path(project_root, "R", "prism-monthly.R"))
source(file.path(project_root, "R", "prism-monthly-audit.R"))
source(file.path(project_root, "R", "prism-monthly-temperature.R"))
source(file.path(project_root, "R", "prism-monthly-precipitation.R"))
source(file.path(project_root, "R", "prism-monthly-ranking-pilots.R"))

testthat::test_that("precipitation sums monthly totals without weighting or filling gaps", {
  root <- tempfile("monthly-precip-sum-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  plan <- data.frame(variable = "pcpn", month = c("2020-01", "2020-02"), complete = TRUE)
  plan$path <- file.path(root, paste0(plan$month, ".tif"))
  for (i in seq_len(nrow(plan))) {
    r <- terra::rast(nrows = 1, ncols = 3, xmin = 0, xmax = 3/24, ymin = 0, ymax = 1/24)
    terra::values(r) <- if (i == 1) c(1, 1, 0) else c(2, NA, 0)
    terra::writeRaster(r, plan$path[i])
  }
  result <- prism_monthly_precipitation_window(plan, "2020-02", 2)
  testthat::expect_equal(terra::values(result, mat = FALSE), c(3, NA, 0))
  testthat::expect_equal(terra::values(prism_monthly_precipitation_window(plan, "2020-02", 1), mat = FALSE), c(2, NA, 0))
  plan$complete[1] <- FALSE
  testthat::expect_error(prism_monthly_precipitation_window(plan, "2020-02", 2), "unverified")
})

testthat::test_that("precipitation rankings handle zero mass, ties, and normal support", {
  values <- rbind(c(0, 0, 1, 2), c(0, 0, 0, 0), c(1, NA, NA, 3))
  dry <- prism_monthly_precipitation_statistics(values, 2000:2003, 2000,
    min_years = 2, min_fraction = .75, normal_years = 2000:2002, min_normal_years = 3)
  testthat::expect_equal(unname(dry[1, c("percentile", "dry_rank", "wet_rank", "zero_fraction")]), c(25, 1.5, 3.5, .5))
  testthat::expect_equal(unname(dry[2, c("percentile", "zero_fraction")]), c(50, 1))
  testthat::expect_equal(unname(dry[2, "record_high"]), 0)
  testthat::expect_true(is.na(dry[3, "percentile"]))
  wet <- prism_monthly_precipitation_statistics(values, 2000:2003, 2003,
    min_years = 2, min_fraction = .75, normal_years = 2000:2002, min_normal_years = 3)
  testthat::expect_equal(unname(wet[1, c("wet_rank", "departure_inches")]), c(1, 2 - 1/3))
  testthat::expect_error(prism_monthly_precipitation_statistics(matrix(c(-1, 0), nrow = 1), 2000:2001, 2001), "negative")
  windows <- prism_monthly_comparison_windows("1895-01", "2026-10", 1)
  testthat::expect_equal(nrow(windows), 132L)
  testthat::expect_equal(nrow(prism_monthly_comparison_windows("1895-01", "2026-10", 12)), 131L)
})

testthat::test_that("true records require all windows and include meaningful tied maxima", {
  values <- rbind(c(1, 2, 3, 4), c(1, 4, 4, 4), c(1, NA, 3, 4),
    c(2, 2, 2, 2), c(1, 4, 3, 2))
  s <- prism_monthly_ranking_statistics(values, 2000:2003, 2003, min_years = 2, min_fraction = .75)
  testthat::expect_equal(unname(s[, "record_high"]), c(1, 1, NA, 0, 0))
  testthat::expect_equal(unname(s[, "record_high_tied"]), c(0, 1, NA, 0, 0))
  testthat::expect_true(is.finite(s[3, "percentile"]))
  display <- prism_monthly_record_display(s[, "percentile"], s[, "record_high"])
  testthat::expect_equal(unname(display[1:2]), c(101, 101))
  testthat::expect_equal(unname(display[3]), unname(s[3, "percentile"]))
  testthat::expect_true(all(s[, "percentile"] <= 100, na.rm = TRUE))
  testthat::expect_equal(prism_monthly_record_display(NA_real_, 1), NA_real_)
})

testthat::test_that("record lows need full history and distinguish tied and constant temperatures", {
  x <- rbind(c(4, 3, 2, 1), c(4, 1, 1, 1), c(4, NA, 2, 1), c(1, 1, 1, 1))
  s <- prism_monthly_temperature_statistics(x, 2000:2003, 2003, min_years = 2, min_fraction = .75)
  testthat::expect_equal(unname(s[, "record_low"]), c(1, 1, NA, 0))
  testthat::expect_equal(unname(s[, "record_low_tied"]), c(0, 1, NA, 0))
  display <- prism_monthly_record_display(s[, "percentile"], s[, "record_high"], s[, "record_low"])
  testthat::expect_equal(unname(display[1:2]), c(-1, -1))
  testthat::expect_equal(unname(display[3]), unname(s[3, "percentile"]))
  testthat::expect_error(prism_monthly_record_display(50, 1, 1), "both")
})

testthat::test_that("zero-total dry records require no more than two percent zero windows", {
  x <- rbind(c(rep(1, 99), 0), c(rep(1, 98), 0, 0), c(rep(1, 97), 0, 0, 0),
    rep(0, 100), c(rep(2, 99), 1), c(rep(2, 98), 1, 1))
  s <- prism_monthly_precipitation_statistics(x, 1900:1999, 1999)
  testthat::expect_equal(unname(s[, "record_low"]), c(1, 1, 0, 0, 1, 1))
  testthat::expect_equal(unname(s[, "record_low_tied"]), c(0, 1, 0, 0, 0, 1))
  testthat::expect_equal(unname(s[, "record_low_zero_withheld"]), c(0, 0, 1, 0, 0, 0))
  testthat::expect_equal(unname(s[4, "percentile"]), 50)
  display <- prism_monthly_record_display(s[, "percentile"], s[, "record_high"], s[, "record_low"])
  testthat::expect_equal(unname(display[3]), unname(s[3, "percentile"]))
  testthat::expect_error(prism_monthly_precipitation_statistics(x, 1900:1999, 1999,
    max_record_zero_fraction = -1), "threshold")
  footer <- prism_monthly_precipitation_footer(data.frame(minimum_years = 119, comparison_windows = 132))
  testthat::expect_equal(length(strsplit(footer, "\n", fixed = TRUE)[[1]]), 3L)
  testthat::expect_match(footer, "<=2% historical zeros", fixed = TRUE)
})

testthat::test_that("all durations build, resume, and invalidate only a damaged product", {
  root <- tempfile("monthly-ranking-batch-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  box <- c(0, 0, 2/24, 2/24)
  cache <- file.path(root, "cache"); output <- file.path(root, "results")
  plan <- plan_prism_monthly_download(start = "2020-01", end = "2022-12", cache_dir = cache, bbox = box)
  fetch <- function(item, destination) {
    r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2/24, ymin = 0, ymax = 2/24, crs = "EPSG:4326")
    year <- as.integer(substr(item$month, 1, 4)) - 2019
    value <- if (item$variable == "pcpn") year else year * 5 + if (item$variable == "maxt") 2 else -2
    terra::values(r) <- c(value, value, value, NA)
    terra::time(r) <- prism_monthly_month(item$month)
    terra::writeRaster(r, destination)
  }
  download_prism_monthly_plan(plan, max_requests = Inf, delay_seconds = 0, fetch = fetch)
  run <- function() build_prism_monthly_ranking_pilots(end = "2022-12", start = "2020-01", cache_dir = cache,
    output_dir = output, audit_dir = file.path(root, "audit"), bbox = box, min_years = 2, make_maps = FALSE)
  first <- run()
  testthat::expect_equal(first$summary$status, "READY")
  testthat::expect_equal(first$summary$built, 8)
  total_path <- file.path(output, "2022-12", "precipitation", "06month", "total_precipitation_inches.tif")
  testthat::expect_equal(terra::values(terra::rast(total_path), mat = FALSE), c(18, 18, 18, NA))
  second <- run()
  testthat::expect_equal(second$summary$reused, 8)
  unlink(total_path)
  third <- run()
  testthat::expect_equal(third$summary$built, 1)
  testthat::expect_equal(third$summary$reused, 7)
  testthat::expect_equal(third$results$variable[third$results$event == "BUILT"], "precipitation")
  testthat::expect_equal(third$results$duration_months[third$results$event == "BUILT"], 6)
  # A revised January total only affects the December-ending 12-month rank,
  # not shorter December windows or any temperature product.
  revised <- plan_prism_monthly_download(months = "2020-01", variables = "pcpn", cache_dir = cache, bbox = box)
  fetch_revised <- function(item, destination) {
    r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2/24, ymin = 0, ymax = 2/24, crs = "EPSG:4326")
    terra::values(r) <- c(2, 2, 2, NA); terra::time(r) <- prism_monthly_month(item$month)
    terra::writeRaster(r, destination)
  }
  download_prism_monthly_plan(revised, refresh = TRUE, delay_seconds = 0, fetch = fetch_revised)
  selective <- run()
  testthat::expect_equal(selective$summary$built, 1)
  testthat::expect_equal(selective$summary$reused, 7)
  testthat::expect_equal(selective$results$variable[selective$results$event == "BUILT"], "precipitation")
  testthat::expect_equal(selective$results$duration_months[selective$results$event == "BUILT"], 12)
  testthat::expect_error(build_prism_monthly_ranking_pilots(temperature_durations = 1.5), "whole")
  testthat::expect_error(build_prism_monthly_ranking_pilots(temperature_durations = NULL,
    precipitation_durations = NULL), "whole")
})
