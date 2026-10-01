source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "audit-snodas.R"))
source(file.path(project_root, "R", "snodas-inventory.R"))
source(file.path(project_root, "R", "snodas-bootstrap.R"))
source(file.path(project_root, "R", "snodas-daily-update.R"))
source(file.path(project_root, "R", "snodas-daily-climatology.R"))
source(file.path(project_root, "R", "snodas-current-site.R"))

snodas_current_site_fixture <- function(root, date = as.Date("2026-10-01")) {
  processed_dir <- file.path(root, "processed")
  climatology_root <- file.path(root, "climatology")
  reference <- snodas_climatology_day_paths(climatology_root,
                                           format(date, "%m-%d"))
  paths <- c(swe = snodas_processed_path(date, "swe", processed_dir),
             depth = snodas_processed_path(date, "depth", processed_dir),
             median = reference[["median_swe"]],
             marker = reference[["complete"]])
  for (index in seq_along(paths)) {
    dir.create(dirname(paths[[index]]), recursive = TRUE,
               showWarnings = FALSE)
    writeBin(as.raw(index), paths[[index]])
  }
  list(processed_dir = processed_dir,
       climatology_root = climatology_root,
       site_map_dir = file.path(root, "site", "maps"),
       page_path = file.path(root, "site", "current-snow.qmd"),
       diagnostics_dir = file.path(root, "diagnostics"),
       swe_path = paths[["swe"]])
}

testthat::test_that("current snow selects only verified dates in this season", {
  plan <- data.frame(date = as.Date(c("2026-09-30", "2026-10-01",
                                      "2026-10-02")),
                     processed = c(TRUE, TRUE, FALSE))
  testthat::expect_equal(
    snodas_current_site_latest_date(plan, as.Date("2026-10-02")),
    as.Date("2026-10-01"))
  testthat::expect_true(is.na(snodas_current_site_latest_date(
    plan[3L, , drop = FALSE], as.Date("2026-10-02"))))
  testthat::expect_true(is.na(snodas_current_site_latest_date(
    plan, as.Date("2026-09-29"))))
})

testthat::test_that("current snow page has a waiting state and no repeat captions", {
  waiting <- snodas_current_site_page_text(2027L)
  testthat::expect_true(any(grepl("waiting for a listed", waiting,
                                  fixed = TRUE)))
  testthat::expect_false(any(grepl("swe-observed.png", waiting,
                                   fixed = TRUE)))
  live <- snodas_current_site_page_text(2027L, as.Date("2026-10-01"))
  testthat::expect_equal(sum(grepl("Open full-resolution PNG", live,
                                    fixed = TRUE)), 2L)
  testthat::expect_true(any(grepl('fig-alt="Observed snow water', live,
                                  fixed = TRUE)))
  testthat::expect_equal(sum(grepl("../maps/generated/snodas/current/", live,
                                   fixed = TRUE)), 4L)
  testthat::expect_false(any(grepl("../../maps/generated/snodas/current/", live,
                                   fixed = TRUE)))
  testthat::expect_false(any(grepl("![Observed snow water", live,
                                   fixed = TRUE)))
})

testthat::test_that("current snow stages only PASS maps and skips unchanged runs", {
  root <- tempfile("snodas-current-site-")
  fixture <- snodas_current_site_fixture(root)
  date <- as.Date("2026-10-01")
  plan <- data.frame(date = date, processed = TRUE)
  calls <- 0L
  build <- function(date, output_dir, processed_dir, climatology_root) {
    calls <<- calls + 1L
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    image <- magick::image_blank(8, 8, color = "white")
    paths <- setNames(file.path(output_dir,
                                c("observed.png", "departure.png")),
                      c("observed", "departure"))
    for (path in paths) magick::image_write(image, path)
    list(paths = paths, gate = data.frame(status = "PASS", reasons = ""))
  }
  args <- c(list(plan = plan, today = as.Date("2026-10-02")),
            fixture[c("processed_dir", "climatology_root", "site_map_dir",
                      "page_path", "diagnostics_dir")],
            list(build_maps = build))
  first <- do.call(update_snodas_current_site, args)
  testthat::expect_identical(first$status, "STAGED")
  testthat::expect_true(all(file.exists(first$paths)))
  testthat::expect_equal(calls, 1L)
  testthat::expect_true(any(grepl("October 1, 2026",
                                  readLines(fixture$page_path), fixed = TRUE)))
  second <- do.call(update_snodas_current_site, args)
  testthat::expect_identical(second$status, "UNCHANGED")
  testthat::expect_equal(calls, 1L)
  writeBin(as.raw(c(1, 2)), fixture$swe_path)
  third <- do.call(update_snodas_current_site, args)
  testthat::expect_identical(third$status, "STAGED")
  testthat::expect_equal(calls, 2L)
  snodas_current_site_fixture(root, as.Date("2026-10-02"))
  prior_md5 <- unname(tools::md5sum(c(third$paths,
                                      fixture$page_path)))
  args$plan <- data.frame(date = as.Date("2026-10-02"), processed = TRUE)
  args$build_maps <- function(...) list(gate = data.frame(
    status = "REVIEW", reasons = "high modeled SWE"))
  held <- do.call(update_snodas_current_site, args)
  testthat::expect_identical(held$status, "HELD")
  testthat::expect_identical(
    unname(tools::md5sum(c(third$paths, fixture$page_path))), prior_md5)
})

testthat::test_that("quality hold and new-season wait never show old maps", {
  root <- tempfile("snodas-current-hold-")
  fixture <- snodas_current_site_fixture(root)
  write_snodas_current_site_page(2026L, as.Date("2025-10-01"),
                                 fixture$page_path)
  plan <- data.frame(date = as.Date("2026-10-01"), processed = TRUE)
  hold <- function(...) list(gate = data.frame(
    status = "REVIEW", reasons = "SWE at or above 50 inches"))
  args <- c(list(plan = plan, today = as.Date("2026-10-02")),
            fixture[c("processed_dir", "climatology_root", "site_map_dir",
                      "page_path", "diagnostics_dir")],
            list(build_maps = hold))
  result <- do.call(update_snodas_current_site, args)
  testthat::expect_identical(result$status, "HELD")
  testthat::expect_false(dir.exists(fixture$site_map_dir))
  text <- readLines(fixture$page_path, warn = FALSE)
  testthat::expect_true(any(grepl("waiting for a listed", text,
                                  fixed = TRUE)))
  testthat::expect_false(any(grepl("2025-10-01", text, fixed = TRUE)))
  waiting_args <- args
  waiting_args$plan <- plan[FALSE, , drop = FALSE]
  waiting_args$build_maps <- NULL
  waiting <- do.call(update_snodas_current_site, waiting_args)
  testthat::expect_identical(waiting$status, "WAITING")
})
