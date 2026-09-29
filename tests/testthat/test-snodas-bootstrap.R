source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "audit-snodas.R"))
source(file.path(project_root, "R", "snodas-inventory.R"))
source(file.path(project_root, "R", "snodas-bootstrap.R"))

testthat::test_that("cool-season pilot uses verified listings and skips known gaps", {
  months <- seq(as.Date("2023-10-01"), as.Date("2024-05-01"), by = "month")
  missing <- as.Date("2024-02-14")
  entries <- lapply(months, function(month) {
    next_month <- seq(month, by = "month", length.out = 2L)[2L]
    dates <- seq(month, next_month - 1L, by = "day")
    dates <- dates[dates != missing]
    data.frame(month = as.character(month), checked_utc = "2026-09-25 UTC",
               listed_dates = paste(dates, collapse = ","))
  })
  inventory_path <- tempfile(fileext = ".csv")
  utils::write.csv(do.call(rbind, entries), inventory_path, row.names = FALSE)
  raw_dir <- tempfile("snodas-raw-")
  errata <- list(all_missing = missing, bad_swe = as.Date(character()))
  plan <- plan_snodas_cool_season(2024L, inventory_path, raw_dir, errata)
  testthat::expect_equal(nrow(plan), 243L)
  testthat::expect_equal(attr(plan, "known_missing_dates"), missing)
  testthat::expect_false(missing %in% plan$date)
  testthat::expect_equal(preview_snodas_download(plan)$scheduled, 5L)
  status <- snodas_cool_season_status(plan, tempfile("snodas-processed-"))
  testthat::expect_equal(status$raw_pending, 243L)
  testthat::expect_equal(status$paired_processed, 0L)
  testthat::expect_equal(status$known_missing_dates, 1L)

  bad <- utils::read.csv(inventory_path, stringsAsFactors = FALSE)
  bad <- bad[bad$month != "2024-05-01", ]
  utils::write.csv(bad, inventory_path, row.names = FALSE)
  testthat::expect_error(
    plan_snodas_cool_season(2024L, inventory_path, raw_dir, errata),
    "not ready"
  )
  testthat::expect_error(
    plan_snodas_cool_season(2026L, inventory_path, raw_dir, errata),
    "2005-2025"
  )
  testthat::expect_error(
    run_snodas_cool_season_stage(max_batches = 5L),
    "1-4 five-request"
  )
})

testthat::test_that("validated regional grids remain complete after raw release", {
  date <- as.Date("2024-02-15")
  root <- tempfile("snodas-lean-")
  raw_dir <- file.path(root, "raw")
  processed_dir <- file.path(root, "processed")
  archive <- snodas_archive_path(date, raw_dir)
  dir.create(dirname(archive), recursive = TRUE, showWarnings = FALSE)
  writeBin(as.raw(1:10), archive)
  source_md5 <- unname(tools::md5sum(archive))
  for (variable in c("swe", "depth")) {
    path <- snodas_processed_path(date, variable, processed_dir)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    grid <- terra::rast(nrows = 2, ncols = 2, xmin = -111, xmax = -110,
                        ymin = 35, ymax = 36, crs = "EPSG:4326")
    terra::values(grid) <- c(0, 1, 2, NA)
    terra::time(grid) <- date
    terra::writeRaster(grid, path)
    record <- data.frame(
      date = as.character(date), variable = variable, path = path,
      bytes = file.info(path)$size,
      md5 = unname(tools::md5sum(path)), source_md5 = source_md5
    )
    write_snodas_manifest_row(
      record, snodas_manifest_path("processed", processed_dir),
      c("date", "variable")
    )
  }
  plan <- plan_snodas_download(date, raw_dir = raw_dir)
  testthat::expect_true(snodas_cool_season_processed(
    plan, processed_dir)$complete)
  testthat::expect_true(snodas_verify_processed_pair(
    date, archive, processed_dir))
  snodas_release_archive(date, raw_dir, processed_dir)
  testthat::expect_false(file.exists(archive))
  testthat::expect_false(plan_snodas_download(date, raw_dir = raw_dir)$complete)
  testthat::expect_true(snodas_cool_season_processed(
    plan_snodas_download(date, raw_dir = raw_dir),
    processed_dir
  )$complete)

  writeBin(as.raw(11:20), archive)
  testthat::expect_error(
    snodas_release_archive(date, raw_dir, processed_dir),
    "failed verification"
  )
  testthat::expect_true(file.exists(archive))
  writeBin(as.raw(1:10), archive)
  file.remove(snodas_processed_path(date, "depth", processed_dir))
  testthat::expect_error(
    snodas_release_archive(date, raw_dir, processed_dir), "incomplete"
  )
  testthat::expect_true(file.exists(archive))
})
