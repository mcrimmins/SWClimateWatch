source(file.path(project_root, "R", "audit-prism-availability.R"))

testthat::test_that("availability distinguishes genuine missing fields from dry weather", {
  check <- function(x, control = c(1, 2, NA_real_)) {
    prism_availability_metrics(x, control, c(0, 100))
  }
  testthat::expect_identical(check(c(0, 0, NA_real_))$status, "AVAILABLE")
  testthat::expect_identical(check(rep(NA_real_, 3))$status, "ALL_MISSING")
  testthat::expect_identical(check(c(0, NA_real_, NA_real_))$status, "PARTIAL")
  testthat::expect_identical(check(c(-999, 1, NA_real_))$status, "INVALID_RANGE")
  testthat::expect_identical(check(c(Inf, 1, NA_real_))$status, "INVALID_RANGE")
  testthat::expect_identical(check(c(1, 2, 3), rep(NA_real_, 3))$status, "NO_CONTROL")
  testthat::expect_equal(check(c(0, 0, NA_real_))$control_coverage, 1)
})

latest_prism_fixture <- function() {
  directory <- tempfile("latest-prism-")
  plan <- plan_prism_download("update", today = as.Date("2026-10-30"),
    revision_ages = 2L, manifest = data.frame(), raw_dir = directory)
  for (path in plan$path) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines("control", path)
  }
  list(directory = directory, plan = plan,
       manifest = prism_manifest_path(directory),
       fetch = function(item, path) writeLines(paste(item$variable, item$start_date), path),
       validate = function(path, item, control_path) TRUE)
}

testthat::test_that("yesterday is installed as one complete set and unchanged reruns reuse hashes", {
  f <- latest_prism_fixture()
  on.exit(unlink(f$directory, recursive = TRUE))
  result <- download_prism_latest_set(f$plan, delay_seconds = 0,
    fetch_function = f$fetch, validate_function = f$validate)
  testthat::expect_equal(result$status$status, "ACCEPTED")
  testthat::expect_equal(result$status$selected_date, "2026-10-29")
  testthat::expect_equal(result$status$requests, 3)
  testthat::expect_equal(nrow(result$records), 3)
  testthat::expect_true(all(result$records$changed))
  manifest <- read_prism_manifest(f$manifest)
  testthat::expect_equal(nrow(manifest), 3)
  testthat::expect_true(all(manifest$start_date == as.Date("2026-10-29")))
  again <- download_prism_latest_set(f$plan, delay_seconds = 0,
    fetch_function = f$fetch, validate_function = f$validate)
  testthat::expect_false(any(again$records$changed))
  testthat::expect_equal(nrow(read_prism_manifest(f$manifest)), 3)
})

testthat::test_that("one failed or invalid field leaves no candidate files or manifest rows", {
  for (cause in c("HTTP 404", "timeout", "ALL_MISSING", "PARTIAL", "wrong Date metadata")) {
    f <- latest_prism_fixture()
    tryCatch({
      validate <- function(path, item, control_path) {
        if (item$variable == "mint") stop(cause)
      }
      result <- download_prism_latest_set(f$plan, delay_seconds = 0,
        fetch_function = f$fetch, validate_function = validate)
      testthat::expect_equal(result$status$status, "FALLBACK", info = cause)
      testthat::expect_equal(result$status$selected_date, "2026-10-28")
      testthat::expect_equal(result$status$requests, 2)
      testthat::expect_equal(nrow(result$records), 0)
      testthat::expect_false(file.exists(f$manifest))
      testthat::expect_length(list.files(f$directory, pattern = "2026-10-29", recursive = TRUE), 0)
      testthat::expect_equal(readLines(f$plan$path[1L]), "control")
    }, finally = unlink(f$directory, recursive = TRUE))
  }
})

testthat::test_that("request errors retain an earlier verified same-day set", {
  f <- latest_prism_fixture()
  on.exit(unlink(f$directory, recursive = TRUE))
  accepted <- download_prism_latest_set(f$plan, delay_seconds = 0,
    fetch_function = f$fetch, validate_function = f$validate)
  before <- tools::md5sum(c(accepted$records$path, f$manifest))
  failed <- download_prism_latest_set(f$plan, delay_seconds = 0,
    fetch_function = function(item, path) stop("timeout"), validate_function = f$validate)
  testthat::expect_equal(failed$status$status, "RETAINED")
  testthat::expect_equal(failed$status$selected_date, "2026-10-29")
  testthat::expect_identical(tools::md5sum(names(before)), before)
})

testthat::test_that("an optional set respects caps and requires the full control network", {
  f <- latest_prism_fixture()
  on.exit(unlink(f$directory, recursive = TRUE))
  no_fetch <- function(...) stop("must not request")
  capped <- download_prism_latest_set(f$plan, request_budget = 2, fetch_function = no_fetch)
  testthat::expect_equal(capped$status$status, "DEFERRED")
  testthat::expect_equal(capped$status$requests, 0)
  partial <- download_prism_latest_set(f$plan[1L, ], fetch_function = no_fetch)
  testthat::expect_equal(partial$status$status, "SKIPPED")
  testthat::expect_equal(partial$status$requests, 0)
})

testthat::test_that("sync retains the revision queue and combines optional downloads", {
  f <- latest_prism_fixture()
  on.exit(unlink(f$directory, recursive = TRUE))
  called <- list()
  result <- sync_prism("update", today = as.Date("2026-10-30"), raw_dir = f$directory,
    manifest = data.frame(), revision_ages = c(2L, 6L), max_requests = 9L,
    availability_path = file.path(f$directory, "status.csv"), quiet = TRUE,
    download_function = function(plan, ...) {
      called$dates <<- sort(unique(plan$start_date))
      data.frame(path = "base")
    }, candidate_function = function(plan, request_budget, ...) {
      called$budget <<- request_budget
      list(records = data.frame(path = "yesterday"),
           status = data.frame(status = "ACCEPTED", selected_date = "2026-10-29", note = "ok"))
    })
  testthat::expect_equal(called$dates, as.Date(c("2026-10-24", "2026-10-28")))
  testthat::expect_equal(called$budget, 3)
  testthat::expect_equal(result$path, c("base", "yesterday"))
  testthat::expect_equal(attr(result, "availability")$status, "ACCEPTED")
})

testthat::test_that("real GeoTIFF validation rejects missing, partial, misdated and shifted fields", {
  directory <- tempfile("latest-grid-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  grid <- terra::rast(nrows = 2, ncols = 2, xmin = -112, xmax = -112 + 2/24,
    ymin = 33, ymax = 33 + 2/24, crs = "EPSG:4326")
  terra::values(grid) <- c(0, 1, 2, 3)
  control <- file.path(directory, "control.tif")
  candidate <- file.path(directory, "candidate.tif")
  terra::writeRaster(grid, control)
  write_candidate <- function(raster, date = "2026-10-29") {
    terra::writeRaster(raster, candidate, overwrite = TRUE)
    # A GDAL PAM sidecar supplies the same band-level Date key as ACIS.
    writeLines(paste0('<PAMDataset><PAMRasterBand band="1"><Metadata>',
      '<MDI key="Date">', date, '</MDI></Metadata></PAMRasterBand></PAMDataset>'),
      paste0(candidate, ".aux.xml"))
  }
  write_candidate(grid)
  item <- data.frame(start_date = as.Date("2026-10-29"),
    end_date = as.Date("2026-10-29"), variable = "pcpn")
  testthat::expect_true(validate_prism_latest_field(candidate, item, control))
  terra::values(grid) <- NA_real_
  write_candidate(grid)
  testthat::expect_error(validate_prism_latest_field(candidate, item, control), "ALL_MISSING")
  terra::values(grid) <- c(0, 1, 2, NA)
  write_candidate(grid)
  testthat::expect_error(validate_prism_latest_field(candidate, item, control), "PARTIAL")
  terra::values(grid) <- c(0, 1, 2, 3)
  write_candidate(grid, "2026-10-28")
  testthat::expect_error(validate_prism_latest_field(candidate, item, control), "Date metadata")
  shifted <- terra::shift(grid, dx = 1/24)
  write_candidate(shifted)
  testthat::expect_error(validate_prism_latest_field(candidate, item, control), "geometry")
})

testthat::test_that("a local manifest-write failure rolls back candidate files and stays fatal", {
  f <- latest_prism_fixture()
  on.exit(unlink(f$directory, recursive = TRUE))
  accepted <- download_prism_latest_set(f$plan, delay_seconds = 0,
    fetch_function = f$fetch, validate_function = f$validate)
  before <- tools::md5sum(c(accepted$records$path, f$manifest))
  env <- environment(install_prism_latest_set)
  original_writer <- get("write_prism_manifest", envir = env)
  assign("write_prism_manifest", function(...) stop("disk write failed"), envir = env)
  on.exit(assign("write_prism_manifest", original_writer, envir = env), add = TRUE)
  testthat::expect_error(download_prism_latest_set(f$plan, delay_seconds = 0,
    fetch_function = function(item, path) writeLines("new revision", path),
    validate_function = f$validate), "disk write failed")
  testthat::expect_identical(tools::md5sum(names(before)), before)
})
