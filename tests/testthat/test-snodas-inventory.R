source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "audit-snodas.R"))
source(file.path(project_root, "R", "snodas-inventory.R"))

testthat::test_that("monthly inventory resumes, obeys its cap, and compares errata", {
  months <- as.Date(c("2007-02-01", "2007-03-01"))
  cache_path <- tempfile(fileext = ".csv")
  calls <- character()
  fetch <- function(url) {
    calls <<- c(calls, url)
    month <- if (grepl("02_Feb", url, fixed = TRUE)) months[1L] else months[2L]
    end <- seq(month, by = "month", length.out = 2L)[2L] - 1L
    dates <- seq(month, end, by = "day")
    if (month == months[1L]) dates <- dates[dates != as.Date("2007-02-14")]
    paste0('<a href="SNODAS_', format(dates, "%Y%m%d"), '.tar">file</a>')
  }
  first <- snodas_inventory_batch(months, cache_path, max_requests = 1L,
                                  delay_seconds = 0, fetch_lines = fetch)
  testthat::expect_equal(first$checked_this_run, 1L)
  testthat::expect_equal(first$remaining, 1L)
  testthat::expect_equal(length(calls), 1L)
  partial_calendar <- snodas_inventory_calendar(
    first$cache, as.Date("2007-02-01"), as.Date("2007-03-31"),
    list(all_missing = as.Date("2007-02-14"),
         bad_swe = as.Date(character()))
  )
  partial_months <- summarize_snodas_inventory(partial_calendar)
  testthat::expect_true(is.na(partial_months$listed_days[2L]))
  testthat::expect_equal(summarize_snodas_inventory_water_year(
    partial_months)$status, "PARTIAL")
  unchecked_calendar <- snodas_inventory_calendar(
    read_snodas_inventory(tempfile()), as.Date("2007-02-01"),
    as.Date("2007-03-31"),
    list(all_missing = as.Date(character()),
         bad_swe = as.Date(character()))
  )
  unchecked_year <- summarize_snodas_inventory_water_year(
    summarize_snodas_inventory(unchecked_calendar))
  testthat::expect_equal(unchecked_year$status, "NOT_CHECKED")
  testthat::expect_true(is.na(unchecked_year$listed_days))
  second <- snodas_inventory_batch(months, cache_path, max_requests = 1L,
                                   delay_seconds = 0, fetch_lines = fetch)
  testthat::expect_equal(second$remaining, 0L)
  testthat::expect_equal(length(calls), 2L)
  third <- snodas_inventory_batch(months, cache_path, max_requests = 1L,
                                  delay_seconds = 0, fetch_lines = fetch)
  testthat::expect_equal(third$checked_this_run, 0L)
  testthat::expect_equal(length(calls), 2L)
  errata <- list(all_missing = as.Date("2007-02-14"),
                 bad_swe = as.Date(character()))
  calendar <- snodas_inventory_calendar(third$cache,
                                        as.Date("2007-02-01"),
                                        as.Date("2007-03-31"), errata)
  testthat::expect_equal(calendar$status[calendar$date ==
                                          as.Date("2007-02-14")],
                         "known_missing_all")
  summary <- summarize_snodas_inventory(calendar)
  testthat::expect_equal(summary$known_missing_all[1L], 1L)
  testthat::expect_equal(sum(summary$unexplained_unlisted), 0L)
  by_year <- summarize_snodas_inventory_water_year(summary)
  testthat::expect_equal(by_year$status, "COMPLETE")
  testthat::expect_equal(by_year$months_checked, 2L)
  testthat::expect_equal(by_year$known_missing_all, 1L)
  testthat::expect_error(snodas_inventory_batch(months, cache_path,
                                                  max_requests = 13L,
                                                  fetch_lines = fetch),
                         "limited to 0-12")
})

testthat::test_that("empty or broken directory listings are not cached", {
  path <- tempfile(fileext = ".csv")
  testthat::expect_error(snodas_inventory_batch(
    as.Date("2007-02-01"), path, max_requests = 1L,
    delay_seconds = 0, fetch_lines = function(url) "temporary server error"
  ), "No SNODAS archives")
  testthat::expect_false(file.exists(path))
})
