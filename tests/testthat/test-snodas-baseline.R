source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "audit-snodas.R"))
source(file.path(project_root, "R", "snodas-inventory.R"))
source(file.path(project_root, "R", "snodas-bootstrap.R"))
source(file.path(project_root, "R", "snodas-quality-pilot.R"))
source(file.path(project_root, "R", "snodas-season-audit.R"))
source(file.path(project_root, "R", "snodas-baseline.R"))

testthat::test_that("baseline years are explicit and validated", {
  testthat::expect_equal(validate_snodas_baseline_years(c(2024, 2005, 2024)),
                         c(2005L, 2024L))
  testthat::expect_error(validate_snodas_baseline_years(numeric()),
                         "Choose one or more")
  testthat::expect_error(validate_snodas_baseline_years(2026), "2005-2025")
  testthat::expect_error(validate_snodas_baseline_years(2005.5),
                         "whole SNODAS")
})

testthat::test_that("multi-year preview is offline and preserves known gaps", {
  root <- tempfile("snodas-baseline-")
  raw_dir <- file.path(root, "raw")
  processed_dir <- file.path(root, "processed")
  dir.create(file.path(raw_dir, "snodas", "reference"), recursive = TRUE)
  writeLines(c("MISSING MASKED FILES", "2005-02-14",
               "The following dates are missing individual files:",
               "MISSING UNMASKED FILES"),
             file.path(raw_dir, "snodas", "reference",
                       "G02158_missing_files.txt"))
  months <- c(seq(as.Date("2004-10-01"), as.Date("2005-05-01"), by = "month"),
              seq(as.Date("2005-10-01"), as.Date("2006-05-01"), by = "month"))
  missing <- as.Date("2005-02-14")
  entries <- lapply(months, function(month) {
    next_month <- seq(month, by = "month", length.out = 2L)[2L]
    dates <- seq(month, next_month - 1L, by = "day")
    dates <- dates[dates != missing]
    data.frame(month = as.character(month), checked_utc = "2026-09-25 UTC",
               listed_dates = paste(dates, collapse = ","))
  })
  inventory_path <- file.path(root, "inventory.csv")
  utils::write.csv(do.call(rbind, entries), inventory_path, row.names = FALSE)
  log_path <- file.path(root, "overnight-log.csv")

  plan <- plan_snodas_baseline(c(2006, 2005, 2005), inventory_path,
                               raw_dir, processed_dir)
  testthat::expect_equal(plan$water_year, c(2005L, 2006L))
  testthat::expect_equal(plan$known_missing_dates, c(1L, 0L))
  testthat::expect_equal(plan$paired_processed, c(0L, 0L))
  testthat::expect_equal(plan$processing_pending, plan$listed_dates)

  preview <- run_snodas_baseline(c(2006, 2005), inventory_path,
                                 raw_dir, processed_dir, log_path,
                                 dry_run = TRUE)
  testthat::expect_equal(preview$initial, plan)
  testthat::expect_equal(preview$stages_attempted, 0L)
  testthat::expect_false(file.exists(log_path))
  testthat::expect_false(dir.exists(file.path(raw_dir, "snodas", "daily")))
})
