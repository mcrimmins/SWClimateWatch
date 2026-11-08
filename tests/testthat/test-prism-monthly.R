source(file.path(project_root, "R", "prism-monthly.R"))

monthly_fixture_fetch <- function(item, destination) {
  r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2/24,
    ymin = 0, ymax = 2/24, crs = "EPSG:4326")
  terra::values(r) <- c(0, 1, 2, NA)
  terra::time(r) <- prism_monthly_month(item$month)
  terra::writeRaster(r, destination, overwrite = TRUE)
}

monthly_fixture_plan <- function(cache_dir) {
  plan_prism_monthly_download(months = c("1895-01", "2020-07"),
    variables = "pcpn", cache_dir = cache_dir, bbox = c(0, 0, 2/24, 2/24))
}

testthat::test_that("monthly planning uses completed months and explicit monthly reductions", {
  testthat::expect_equal(prism_monthly_latest_complete(as.Date("2026-01-01")), "2025-12")
  testthat::expect_error(prism_monthly_month("2020-13"), "Invalid")
  testthat::expect_error(prism_monthly_month("2020-1"), "YYYY-MM")
  testthat::expect_error(plan_prism_monthly_download(months = "1894-12"), "1895")
  testthat::expect_error(plan_prism_monthly_download(months = "2026-11", today = as.Date("2026-11-06")), "complete")
  testthat::expect_error(plan_prism_monthly_download(months = "2020-01", variables = "tmean"), "maxt")
  p <- plan_prism_monthly_download(months = "2020-01", cache_dir = tempfile())
  testthat::expect_equal(nrow(p), 3L)
  testthat::expect_equal(prism_monthly_payload(p[p$variable == "pcpn", ])$elems[[1]]$reduce, "sum")
  t <- prism_monthly_payload(p[p$variable == "maxt", ])$elems[[1]]
  testthat::expect_equal(t$reduce, "mean")
  testthat::expect_equal(t$units, "degreeF")
  testthat::expect_equal(t$interval, "mly")
})

testthat::test_that("monthly cache resumes, checks provenance, and detects corrupt files", {
  root <- tempfile("monthly-test-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  p <- monthly_fixture_plan(root)
  first <- download_prism_monthly_plan(p, max_requests = 1, delay_seconds = 0, fetch = monthly_fixture_fetch)
  testthat::expect_equal(first$status, "CACHED")
  testthat::expect_equal(terra::values(terra::rast(p$path[1]), mat = FALSE), c(0, 1, 2, NA))
  p <- monthly_fixture_plan(root)
  testthat::expect_equal(p$complete, c(TRUE, FALSE))
  second <- download_prism_monthly_plan(p, delay_seconds = 0, fetch = monthly_fixture_fetch)
  testthat::expect_equal(nrow(second), 1L)
  p <- monthly_fixture_plan(root)
  testthat::expect_true(all(p$complete))
  reused <- download_prism_monthly_plan(p, fetch = function(...) stop("Should not download"))
  testthat::expect_equal(nrow(reused), 0L)
  changed <- plan_prism_monthly_download(months = "1895-01", variables = "pcpn",
    cache_dir = root, bbox = c(0, 0, 3/24, 2/24))
  testthat::expect_false(changed$complete)
  writeBin(as.raw(1:4), p$path[1])
  testthat::expect_equal(monthly_fixture_plan(root)$complete, c(FALSE, TRUE))
})

testthat::test_that("bad ranges and wrong geometries are rejected before installation", {
  root <- tempfile("monthly-invalid-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  p <- monthly_fixture_plan(root)[1, , drop = FALSE]
  attr(p, "manifest_path") <- file.path(root, "manifest.csv")
  negative <- function(item, destination) {
    monthly_fixture_fetch(item, destination)
    r <- terra::rast(destination)
    r <- r * 0 - 1
    terra::time(r) <- prism_monthly_month(item$month)
    terra::writeRaster(r, destination, overwrite = TRUE)
  }
  result <- download_prism_monthly_plan(p, delay_seconds = 0, fetch = negative)
  testthat::expect_equal(result$status, "FAILED")
  testthat::expect_false(file.exists(p$path))
  testthat::expect_false(file.exists(attr(p, "manifest_path")))
  wrong_extent <- function(item, destination) {
    monthly_fixture_fetch(item, destination)
    r <- terra::rast(destination)
    terra::ext(r) <- c(1, 1 + 2/24, 1, 1 + 2/24)
    out <- tempfile(fileext = ".tif")
    on.exit(unlink(out), add = TRUE)
    terra::writeRaster(r, out)
    file.copy(out, destination, overwrite = TRUE)
  }
  result <- download_prism_monthly_plan(p, delay_seconds = 0, fetch = wrong_extent)
  testthat::expect_equal(result$status, "FAILED")
  testthat::expect_match(result$note, "extent")
})

testthat::test_that("invalid refresh preserves the old verified file", {
  root <- tempfile("monthly-refresh-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  p <- monthly_fixture_plan(root)
  download_prism_monthly_plan(p, delay_seconds = 0, fetch = monthly_fixture_fetch)
  p <- monthly_fixture_plan(root)
  before <- unname(tools::md5sum(p$path))
  bad <- function(item, destination) {
    item$month <- "2000-01"
    monthly_fixture_fetch(item, destination)
  }
  result <- download_prism_monthly_plan(p, refresh = TRUE, delay_seconds = 0, fetch = bad)
  testthat::expect_true(all(result$status == "FAILED"))
  testthat::expect_equal(unname(tools::md5sum(p$path)), before)
  testthat::expect_true(all(monthly_fixture_plan(root)$complete))
})
