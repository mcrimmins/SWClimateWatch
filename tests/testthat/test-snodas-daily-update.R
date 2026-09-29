source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "audit-snodas.R"))
source(file.path(project_root, "R", "snodas-inventory.R"))
source(file.path(project_root, "R", "snodas-bootstrap.R"))
source(file.path(project_root, "R", "snodas-daily-update.R"))

snodas_pair_fixture <- function(directory, date) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  stamp <- format(date, "%Y%m%d")
  files <- character()
  for (variable in c(swe = "11034", depth = "11036")) {
    stem <- paste0("us_ssmv", variable, "tS__T0001TTNATS", stamp, "05HP001")
    header_file <- file.path(directory, paste0(stem, ".txt.gz"))
    data_file <- file.path(directory, paste0(stem, ".dat.gz"))
    header <- c(
      "Data units: Meters / 1000.000000", "Data bytes per pixel: 2",
      "Number of columns: 3", "Number of rows: 2",
      "Minimum x-axis coordinate: -112", "Maximum y-axis coordinate: 33",
      "X-axis resolution: 1", "Y-axis resolution: 1",
      "No data value: -9999",
      paste0("Start year: ", format(date, "%Y")),
      paste0("Start month: ", as.integer(format(date, "%m"))),
      paste0("Start day: ", as.integer(format(date, "%d"))),
      "Start hour: 6", "Start minute: 0"
    )
    con <- gzfile(header_file, "wt")
    writeLines(header, con)
    close(con)
    con <- gzfile(data_file, "wb")
    writeBin(as.integer(c(0, 25, 50, -9999, 100, 200)),
             con, size = 2L, endian = "big")
    close(con)
    files <- c(files, basename(header_file), basename(data_file))
  }
  archive <- file.path(directory, paste0("SNODAS_", stamp, ".tar"))
  old <- setwd(directory)
  on.exit(setwd(old), add = TRUE)
  utils::tar(archive, files = files, compression = "none", tar = "internal")
  archive
}

testthat::test_that("SNODAS updater skips summer without requests", {
  called <- FALSE
  result <- run_snodas_daily_update(
    today = as.Date("2026-09-27"),
    fetch_lines = function(url) {
      called <<- TRUE
      stop("Unexpected listing request")
    }
  )
  testthat::expect_false(result$in_season)
  testthat::expect_false(called)
  testthat::expect_null(result$summary)
  testthat::expect_equal(
    snodas_update_season(as.Date("2026-06-03"))$end,
    as.Date("2026-05-31"))
  testthat::expect_null(snodas_update_season(as.Date("2026-06-15")))
  october <- snodas_update_season(as.Date("2026-10-01"))
  testthat::expect_equal(october$water_year, 2027L)
  testthat::expect_equal(october$start, as.Date("2026-10-01"))
  testthat::expect_equal(october$end, as.Date("2026-10-01"))
})

testthat::test_that("inventory refresh is bounded and revisits month end", {
  root <- tempfile("snodas-update-inventory-")
  cache_path <- file.path(root, "inventory.csv")
  calls <- character()
  fetch <- function(url) {
    calls <<- c(calls, url)
    if (grepl("10_Oct", url, fixed = TRUE)) {
      return("SNODAS_20251001.tar SNODAS_20251031.tar")
    }
    "SNODAS_20251101.tar"
  }
  first <- refresh_snodas_update_inventory(
    as.Date("2025-11-02"), cache_path, delay_seconds = 0,
    fetch_lines = fetch)
  testthat::expect_equal(first$checked_this_run, 2L)
  testthat::expect_equal(first$months_pending, 0L)
  testthat::expect_equal(nrow(first$cache), 2L)
  testthat::expect_equal(length(calls), 2L)
  second <- refresh_snodas_update_inventory(
    as.Date("2025-11-03"), cache_path, delay_seconds = 0,
    fetch_lines = fetch)
  testthat::expect_equal(second$checked_this_run, 1L)
  testthat::expect_equal(length(calls), 3L)
  testthat::expect_error(refresh_snodas_update_inventory(
    as.Date("2025-11-03"), cache_path, max_requests = 3L,
    fetch_lines = fetch), "0-2")
})

testthat::test_that("a not-yet-created October directory waits, but outages fail", {
  root <- tempfile("snodas-new-season-")
  cache_path <- file.path(root, "inventory.csv")
  missing <- refresh_snodas_update_inventory(
    as.Date("2026-10-01"), cache_path, delay_seconds = 0,
    fetch_lines = function(url) stop("HTTP 404 Not Found"))
  testthat::expect_equal(missing$checked_this_run, 1L)
  testthat::expect_equal(missing$months_pending, 1L)
  testthat::expect_false(file.exists(cache_path))
  warned <- refresh_snodas_update_inventory(
    as.Date("2026-10-01"), cache_path, delay_seconds = 0,
    fetch_lines = function(url) {
      warning("HTTP 404 Not Found")
      stop("cannot open connection")
    })
  testthat::expect_equal(warned$months_pending, 1L)
  testthat::expect_error(refresh_snodas_update_inventory(
    as.Date("2026-10-01"), cache_path, delay_seconds = 0,
    fetch_lines = function(url) stop("HTTP 500 Internal Server Error")),
    "500")
  testthat::expect_error(refresh_snodas_update_inventory(
    as.Date("2026-11-01"), cache_path, delay_seconds = 0,
    fetch_lines = function(url) stop("HTTP 404 Not Found")), "404")
})

testthat::test_that("daily plan prioritizes cached files within the cap", {
  dates <- seq(as.Date("2025-10-01"), by = "day", length.out = 8L)
  cache <- data.frame(
    month = "2025-10-01", checked_utc = "2025-10-09 00:00:00 UTC",
    listed_dates = paste(dates, collapse = ","))
  raw_dir <- tempfile("snodas-update-plan-")
  first <- snodas_archive_path(dates[1L], raw_dir)
  dir.create(dirname(first), recursive = TRUE, showWarnings = FALSE)
  writeBin(as.raw(1:10), first)
  plan <- plan_snodas_daily_update(
    as.Date("2025-10-09"), cache, raw_dir,
    processed_dir = tempfile("snodas-update-processed-"))
  summary <- preview_snodas_daily_update(plan)
  testthat::expect_equal(summary$cached_to_process, 1L)
  testthat::expect_equal(summary$downloads, 4L)
  testthat::expect_equal(summary$deferred, 3L)
  testthat::expect_error(preview_snodas_daily_update(
    plan, max_dates = 6L), "0-5")
})

testthat::test_that("listed SNODAS dates process once and release full tar", {
  root <- tempfile("snodas-daily-run-")
  date <- as.Date("2025-10-01")
  source_archive <- snodas_pair_fixture(file.path(root, "source"), date)
  cache_path <- file.path(root, "inventory.csv")
  raw_dir <- file.path(root, "raw")
  processed_dir <- file.path(root, "processed")
  fetches <- 0L
  listings <- function(url) "SNODAS_20251001.tar"
  fetch_archive <- function(url, destination) {
    fetches <<- fetches + 1L
    file.copy(source_archive, destination)
    0L
  }
  result <- run_snodas_daily_update(
    today = as.Date("2025-10-03"), cache_path = cache_path,
    raw_dir = raw_dir, processed_dir = processed_dir,
    fetch_lines = listings, fetch_archive = fetch_archive)
  testthat::expect_equal(result$summary$processed_this_run, 1L)
  testthat::expect_equal(result$summary$remaining, 0L)
  testthat::expect_equal(fetches, 1L)
  testthat::expect_false(file.exists(snodas_archive_path(date, raw_dir)))
  testthat::expect_true(file.exists(
    snodas_processed_path(date, "swe", processed_dir)))
  testthat::expect_true(file.exists(
    snodas_processed_path(date, "depth", processed_dir)))
  again <- run_snodas_daily_update(
    today = as.Date("2025-10-03"), cache_path = cache_path,
    raw_dir = raw_dir, processed_dir = processed_dir,
    fetch_lines = listings, fetch_archive = fetch_archive)
  testthat::expect_equal(again$summary$processed_this_run, 0L)
  testthat::expect_equal(fetches, 1L)
  testthat::expect_error(run_snodas_daily_update(
    today = as.Date("2025-10-03"), cache_path = cache_path,
    raw_dir = raw_dir, processed_dir = processed_dir,
    max_requests = 6L, fetch_lines = listings,
    fetch_archive = fetch_archive), "configured SNODAS cap")
})
