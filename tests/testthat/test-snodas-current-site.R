source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "audit-snodas.R"))
source(file.path(project_root, "R", "snodas-inventory.R"))
source(file.path(project_root, "R", "snodas-bootstrap.R"))
source(file.path(project_root, "R", "snodas-daily-update.R"))
source(file.path(project_root, "R", "snodas-daily-climatology.R"))
source(file.path(project_root, "R", "snodas-current-site.R"))
source(file.path(project_root, "R", "snodas-analysis-qc.R"))
source(file.path(project_root, "R", "snodas-grid.R"))
source(file.path(project_root, "R", "snodas-daily-comparison-pilot.R"))
source(file.path(project_root, "R", "snodas-current-comparisons.R"))

snodas_current_site_fixture <- function(root, date = as.Date("2026-10-01")) {
  processed_dir <- file.path(root, "processed")
  climatology_root <- file.path(root, "climatology")
  reference <- snodas_climatology_day_paths(climatology_root,
                                           format(date, "%m-%d"))
  paths <- c(swe = snodas_processed_path(date, "swe", processed_dir),
             depth = snodas_processed_path(date, "depth", processed_dir),
             median = reference[["median_swe"]],
             samples = reference[["sample_years"]],
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

testthat::test_that("comparison cache tracks reference support and exact prior endpoint arrival", {
  root <- tempfile("snow-signature-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  fixture <- snodas_current_site_fixture(root)
  date <- as.Date("2026-10-01")
  signature <- function() snodas_current_site_source_signature(date,
    fixture$processed_dir, fixture$climatology_root)
  initial <- signature()
  prior <- snodas_processed_path(date - 7L, "swe", fixture$processed_dir)
  dir.create(dirname(prior), recursive = TRUE, showWarnings = FALSE)
  writeBin(as.raw(1:3), prior)
  testthat::expect_false(identical(initial, signature()))
  before <- signature()
  reference <- snodas_climatology_day_paths(fixture$climatology_root, "10-01")
  writeBin(as.raw(1:5), reference[["sample_years"]])
  testthat::expect_false(identical(before, signature()))
})

testthat::test_that("operational change endpoints need verified paired quality", {
  root <- tempfile("snow-endpoint-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  date <- as.Date("2025-02-08")
  grid <- terra::rast(nrows = 2, ncols = 5, xmin = -112, xmax = -111,
    ymin = 34, ymax = 35, crs = "EPSG:4326")
  store <- function(swe, depth) {
    for (variable in c("swe", "depth")) {
      raster <- terra::setValues(grid, if (variable == "swe") swe else depth)
      terra::time(raster) <- date
      path <- snodas_processed_path(date, variable, root)
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      terra::writeRaster(raster, path, overwrite = TRUE)
      write_snodas_manifest_row(data.frame(date = as.character(date), variable = variable,
        path = path, bytes = file.info(path)$size,
        md5 = unname(tools::md5sum(path)), source_md5 = "fixture"),
        snodas_manifest_path("processed", root), c("date", "variable"))
    }
  }
  read <- function() snodas_current_change_endpoint(date, grid, root)
  testthat::expect_null(read()$swe)
  store(rep(1, 10), rep(2, 10))
  testthat::expect_s4_class(read()$swe, "SpatRaster")
  store(c(51, rep(1, 9)), rep(60, 10))
  testthat::expect_null(read()$swe)
  store(c(3, rep(1, 9)), rep(2, 10))
  testthat::expect_null(read()$swe)
  store(c(rep(NA, 3), rep(1, 7)), c(rep(NA, 3), rep(2, 7)))
  testthat::expect_null(read()$swe)
  writeBin(as.raw(1L), snodas_processed_path(date, "depth", root))
  testthat::expect_match(read()$reason, "unverified")
})

testthat::test_that("current snow page has a waiting state and no repeat captions", {
  waiting <- snodas_current_site_page_text(2027L)
  testthat::expect_true(any(grepl("waiting for a listed", waiting,
                                  fixed = TRUE)))
  testthat::expect_false(any(grepl("swe-observed.png", waiting,
                                   fixed = TRUE)))
  live <- snodas_current_site_page_text(2027L, as.Date("2026-10-01"))
  testthat::expect_equal(sum(grepl("Open full-resolution PNG", live,
                                    fixed = TRUE)), 3L)
  testthat::expect_true(any(grepl('fig-alt="Observed snow water', live,
                                  fixed = TRUE)))
  testthat::expect_equal(sum(grepl("../maps/generated/snodas/current/", live,
                                   fixed = TRUE)), 6L)
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
            list(build_maps = build, build_comparisons = function(...) {
              result <- build(...)
              calls <<- calls - 1L
              list(paths = c(percent = result$paths[["observed"]],
                             change = result$paths[["departure"]]),
                   change_available = TRUE, change_note = "")
            }))
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
  # A comparison losing its verified prior endpoint must remove the old map.
  args$build_comparisons <- function(...) {
    result <- build(...); calls <<- calls - 1L
    list(paths = c(percent = result$paths[["observed"]]),
         change_available = FALSE, change_note = "Exact prior endpoint is missing or unverified.")
  }
  writeBin(as.raw(c(3, 4)), fixture$swe_path)
  third <- do.call(update_snodas_current_site, args)
  testthat::expect_false(file.exists(file.path(fixture$site_map_dir, "swe-change-7day.png")))
  testthat::expect_true(any(grepl("Seven-day SWE change unavailable", readLines(fixture$page_path), fixed = TRUE)))
  testthat::expect_identical(do.call(update_snodas_current_site, args)$status, "UNCHANGED")
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
