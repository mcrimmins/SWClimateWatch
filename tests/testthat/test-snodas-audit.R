source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "audit-snodas.R"))

testthat::test_that("official masked errata are distinct from unmasked errata", {
  path <- tempfile(fileext = ".txt")
  writeLines(c(
    "MISSING MASKED FILES",
    "The following dates are missing ALL data (YYYY-MM-DD):",
    "2007-02-14",
    "The following dates are missing individual files or have no data in the files:",
    "2005-07-31 erroneously contains all zeros in the SWE file",
    "MISSING UNMASKED FILES",
    "The following dates are missing ALL data (YYYY-MM-DD):",
    "2017-02-15"
  ), path)
  errata <- read_snodas_missing_days(path)
  testthat::expect_equal(errata$all_missing, as.Date("2007-02-14"))
  testthat::expect_equal(errata$bad_swe, as.Date("2005-07-31"))
  calendar <- snodas_availability_calendar(as.Date("2007-02-13"),
                                            as.Date("2007-02-15"), errata)
  testthat::expect_equal(calendar$status,
                         c("not_flagged", "missing_all", "not_flagged"))
  testthat::expect_equal(summarize_snodas_availability(calendar)$snow_season_flagged,
                         1)
})

testthat::test_that("month-listing probes are capped and report gaps", {
  month <- as.Date("2007-02-01")
  days <- format(seq(month, by = "day", length.out = 28L), "%Y%m%d")
  html <- paste0('<a href="SNODAS_', days[-14L], '.tar">file</a>')
  testthat::expect_equal(length(snodas_parse_month_listing(html, month)), 27L)
  result <- snodas_probe_months(month, max_requests = 1L,
                                delay_seconds = 0,
                                fetch_lines = function(url) html)
  testthat::expect_equal(result$unlisted_dates, "2007-02-14")
  testthat::expect_error(snodas_probe_months(month, max_requests = 4L),
                         "limited to 0-3")
})
