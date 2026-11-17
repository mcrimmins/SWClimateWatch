source(file.path(project_root, "R/snodas-current-site.R"))
source(file.path(project_root, "R/interactive-map-pilot.R"))
source(file.path(project_root, "R/interactive-map-workflow.R"))
source(file.path(project_root, "R/interactive-map-snow-current.R"))

testthat::test_that("Snow reconciliation rebuilds only the verified date and respects season and quality", {
  root <- tempfile("snow-prepare-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  publication <- file.path(root, "publication.csv")
  row <- data.frame(water_year = 2027, date = "2026-11-16", source_signature = "old",
    observed_md5 = "a", departure_md5 = "b", page_md5 = "c")
  write.csv(row, publication, row.names = FALSE)
  fresh <- FALSE; calls <- 0L; held <- FALSE
  get <- function(...) {if (!fresh) stop("stale page/signature"); list(date = row$date)}
  update <- function(plan, today, ...) {
    calls <<- calls + 1L
    testthat::expect_identical(as.character(plan$date), row$date)
    testthat::expect_identical(today, plan$date)
    testthat::expect_true(plan$processed)
    if (held) return(list(status = "HELD"))
    fresh <<- TRUE; list(status = "STAGED")
  }
  args <- list(site_dir = root, today = as.Date("2026-11-17"), publication_path = publication,
    .get = get, .update = update, .season = function(today) list(water_year = 2027))
  testthat::expect_equal(do.call(prepare_interactive_snow_current, args)$status, "READY")
  testthat::expect_equal(calls, 1L)
  do.call(prepare_interactive_snow_current, args)
  testthat::expect_equal(calls, 1L)
  args$.season <- function(today) list(water_year = 2028)
  testthat::expect_equal(do.call(prepare_interactive_snow_current, args)$status, "WAITING")
  testthat::expect_equal(calls, 1L)
  args$.season <- function(today) NULL
  testthat::expect_equal(do.call(prepare_interactive_snow_current, args)$status, "READY")
  fresh <- FALSE; held <- TRUE
  testthat::expect_error(do.call(prepare_interactive_snow_current, args), "quality gate")
  args$publication_path <- file.path(root, "missing.csv")
  testthat::expect_equal(do.call(prepare_interactive_snow_current, args)$status, "WAITING")
})

testthat::test_that("Snow reuses unchanged bundles, repairs corruption and follows revisions and endpoints", {
  root <- tempfile("snow-refresh-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  base <- file.path(root, "base"); out <- file.path(root, "out"); site <- file.path(root, "site")
  dir.create(base); dir.create(file.path(site, "interactive-maps"), recursive = TRUE)
  writeLines("base", file.path(base, "manifest.json"))
  release <- list(date = "2026-11-16", source_signature = "first", change_available = TRUE)
  builds <- stages <- 0L
  build <- function(output_dir, ...) {
    builds <<- builds + 1L; dir.create(output_dir, showWarnings = FALSE)
    writeLines("verified payload", file.path(output_dir, "payload"))
    entry <- list(source_signature = release$source_signature, change_available = release$change_available)
    list(manifest = list(snow_mode = "verified_current", layers = setNames(list(entry), paste0("snow-", release$date))))
  }
  stage <- function(output_dir, site_dir) {
    if (!identical(readLines(file.path(output_dir, "payload")), "verified payload")) stop("corrupt cache")
    stages <<- stages + 1L
    file.copy(file.path(output_dir, "manifest.json"), file.path(site_dir, "interactive-maps/manifest.json"), overwrite = TRUE)
  }
  validate <- function(site_dir) {
    if (!file.exists(file.path(site_dir, "interactive-maps/manifest.json"))) stop("missing site")
  }
  args <- list(site_dir = site, base_dir = base, output_dir = out, .get = function(...) release,
    .build = build, .stage = stage, .validate = validate,
    .signature = function(release, base_dir) digest::digest(list(release, tools::md5sum(file.path(base_dir, "manifest.json")))))
  testthat::expect_equal(do.call(stage_interactive_snow_current, args)$status, "READY")
  testthat::expect_equal(do.call(stage_interactive_snow_current, args)$status, "REUSED")
  testthat::expect_equal(builds, 1L)
  unlink(file.path(site, "interactive-maps/manifest.json"))
  testthat::expect_equal(do.call(stage_interactive_snow_current, args)$status, "REUSED")
  testthat::expect_equal(builds, 1L)
  testthat::expect_equal(stages, 2L)
  writeLines("corrupt", file.path(out, "payload")); unlink(file.path(site, "interactive-maps/manifest.json"))
  testthat::expect_equal(do.call(stage_interactive_snow_current, args)$status, "READY")
  testthat::expect_equal(builds, 2L)
  release$source_signature <- "revised same date"
  testthat::expect_equal(do.call(stage_interactive_snow_current, args)$status, "READY")
  release$change_available <- FALSE
  result <- do.call(stage_interactive_snow_current, args)
  testthat::expect_false(result$change_available)
  release$change_available <- TRUE; release$date <- "2026-11-17"
  testthat::expect_equal(do.call(stage_interactive_snow_current, args)$date, "2026-11-17")
  testthat::expect_equal(builds, 5L)
  writeLines("revised PRISM", file.path(base, "manifest.json"))
  testthat::expect_equal(do.call(stage_interactive_snow_current, args)$status, "READY")
  testthat::expect_equal(builds, 6L)
})

testthat::test_that("waiting and disabled Snow clear retained catalogs and reports include current counts", {
  root <- tempfile("snow-wrapper-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  dir.create(file.path(root, "interactive-maps"))
  file <- file.path(root, "interactive-maps/manifest.json")
  jsonlite::write_json(list(current = list(variables = list(snow = list(label = "Snow")))), file, auto_unbox = TRUE)
  base <- list(status = "REUSED", current_products = 39L, current_unavailable = 0L, elapsed_seconds = 1)
  staged <- 0L
  prepare <- function(...) list(status = "WAITING")
  stage <- function(...) {staged <<- staged + 1L; jsonlite::write_json(list(current = list()), file)}
  args <- list(base_result = base, site_dir = root, base_dir = root, .prepare = prepare, .stage_base = stage)
  testthat::expect_equal(do.call(refresh_interactive_snow_workflow, args)$snow_status, "WAITING")
  testthat::expect_equal(staged, 1L)
  args$enabled <- FALSE; args$.prepare <- function(...) stop("must not run")
  testthat::expect_equal(do.call(refresh_interactive_snow_workflow, args)$snow_status, "DISABLED")
  args$enabled <- TRUE; args$.prepare <- function(...) list(status = "READY", release = list())
  args$.refresh <- function(...) list(status = "REUSED", date = "2026-11-16", change_available = FALSE, elapsed_seconds = 2)
  result <- do.call(refresh_interactive_snow_workflow, args)
  testthat::expect_equal(result$current_products, 43L)
  testthat::expect_equal(result$current_unavailable, 1L)
  testthat::expect_equal(result$elapsed_seconds, 3)
})
