source(file.path(project_root, "R", "daily-publish.R"))

daily_publish_prism_fixture <- function(changed = FALSE) {
  function() list(summary = data.frame(data_changed = changed))
}

daily_publish_snow_fixture <- function(today) {
  list(maps = list(status = "OUT_OF_SEASON"))
}

daily_publish_station_fixture <- function(today) {
  list(status = "UPDATED", date = as.Date(today) - 1L, pending = 0L)
}

testthat::test_that("ntfy stays off without a topic and rejects unsafe topic names", {
  previous <- Sys.getenv("SWC_NTFY_TOPIC", unset = NA_character_)
  on.exit({
    if (is.na(previous)) Sys.unsetenv("SWC_NTFY_TOPIC") else
      Sys.setenv(SWC_NTFY_TOPIC = previous)
  }, add = TRUE)
  Sys.unsetenv("SWC_NTFY_TOPIC")
  testthat::expect_false(swc_ntfy_notify("test", "offline test"))
  Sys.setenv(SWC_NTFY_TOPIC = "topic/with/slashes")
  testthat::expect_error(swc_ntfy_notify("test", "offline test"),
                         "SWC_NTFY_TOPIC")
})

testthat::test_that("ntfy builds a bounded HTTPS request without sending it", {
  variables <- c("SWC_NTFY_TOPIC", "SWC_NTFY_SERVER", "SWC_NTFY_TOKEN")
  previous <- Sys.getenv(variables, unset = NA_character_)
  on.exit({
    for (index in seq_along(variables)) {
      if (is.na(previous[[index]])) {
        Sys.unsetenv(variables[[index]])
      } else {
        do.call(Sys.setenv,
                setNames(list(previous[[index]]), variables[[index]]))
      }
    }
  }, add = TRUE)
  Sys.setenv(SWC_NTFY_TOPIC = "private-example-123",
             SWC_NTFY_SERVER = "https://ntfy.example.org/",
             SWC_NTFY_TOKEN = "test-token")
  captured <- NULL
  swc_ntfy_notify("success", "Published", perform = function(request) {
    captured <<- request
    invisible(NULL)
  })
  testthat::expect_identical(captured$url,
                             "https://ntfy.example.org/private-example-123")
  testthat::expect_identical(captured$method, "POST")
  testthat::expect_identical(captured$headers[["X-Priority"]], "3")
  # httr2 stores sensitive authorization headers as protected references.
  testthat::expect_true("Authorization" %in% names(captured$headers))
})

testthat::test_that("site fingerprint notices source changes but ignores render output", {
  root <- tempfile("swc-site-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeLines("project:", file.path(root, "_quarto.yml"))
  writeLines("first", file.path(root, "index.qmd"))
  original <- swc_daily_publish_site_fingerprint(root)
  dir.create(file.path(root, "_site"))
  writeLines("rendered", file.path(root, "_site", "index.html"))
  testthat::expect_identical(swc_daily_publish_site_fingerprint(root), original)
  writeLines("second", file.path(root, "index.qmd"))
  testthat::expect_false(identical(swc_daily_publish_site_fingerprint(root), original))
})

testthat::test_that("live publish records success and skips an unchanged rerun", {
  directory <- tempfile("swc-publish-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  marker <- file.path(directory, "success.csv")
  log <- file.path(directory, "runs.csv")
  calls <- 0L
  publish <- function(dry_run) {
    testthat::expect_false(dry_run)
    calls <<- calls + 1L
  }
  args <- list(today = as.Date("2026-09-29"), dry_run = FALSE,
               marker_path = marker, log_path = log,
               prism_update = daily_publish_prism_fixture(FALSE),
               snow_update = daily_publish_snow_fixture,
               station_update = daily_publish_station_fixture,
               site_fingerprint = function() "source-a", publish = publish,
               notify = function(event, message) invisible(NULL))
  first <- do.call(run_swc_daily_publish, args)
  second <- do.call(run_swc_daily_publish, args)
  testthat::expect_identical(first$status, "PUBLISHED")
  testthat::expect_identical(second$status, "SKIPPED_UNCHANGED")
  testthat::expect_identical(calls, 1L)
  testthat::expect_identical(swc_daily_publish_read_marker(marker), "source-a")
  testthat::expect_equal(nrow(utils::read.csv(log)), 2L)
})

testthat::test_that("dry run and failed sync never advance the success marker", {
  directory <- tempfile("swc-preview-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  marker <- file.path(directory, "success.csv")
  log <- file.path(directory, "runs.csv")
  args <- list(today = as.Date("2026-10-01"), dry_run = TRUE,
               marker_path = marker, log_path = log,
               prism_update = daily_publish_prism_fixture(TRUE),
               snow_update = daily_publish_snow_fixture,
               station_update = daily_publish_station_fixture,
               site_fingerprint = function() "source-b",
               publish = function(dry_run) testthat::expect_true(dry_run),
               notify = function(event, message) invisible(NULL))
  result <- do.call(run_swc_daily_publish, args)
  testthat::expect_identical(result$status, "PREVIEW")
  testthat::expect_false(file.exists(marker))
  args$dry_run <- FALSE
  args$publish <- function(dry_run) stop("sync failed")
  testthat::expect_error(do.call(run_swc_daily_publish, args), "sync failed")
  testthat::expect_false(file.exists(marker))
  testthat::expect_identical(tail(utils::read.csv(log)$status, 1L), "FAILED")
})

testthat::test_that("snow failure is logged without blocking updated PRISM maps", {
  directory <- tempfile("swc-snow-fail-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  called <- FALSE
  testthat::expect_warning(result <- run_swc_daily_publish(
    today = as.Date("2026-10-02"), dry_run = FALSE,
    marker_path = file.path(directory, "success.csv"),
    log_path = file.path(directory, "runs.csv"),
    prism_update = daily_publish_prism_fixture(TRUE),
    snow_update = function(today) stop("snow source unavailable"),
    station_update = daily_publish_station_fixture,
    site_fingerprint = function() "prism-map-change",
    publish = function(dry_run) called <<- TRUE,
    notify = function(event, message) invisible(NULL)),
    "SNODAS update failed")
  log <- utils::read.csv(file.path(directory, "runs.csv"))
  testthat::expect_true(called)
  testthat::expect_identical(result$status, "PUBLISHED")
  testthat::expect_identical(log$snow_status, "ERROR")
  testthat::expect_match(log$snow_error, "snow source unavailable")
})

testthat::test_that("station failure retains beta snapshot and does not block other maps", {
  directory <- tempfile("swc-station-fail-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  called <- FALSE
  testthat::expect_warning(result <- run_swc_daily_publish(
    today = as.Date("2026-10-02"), dry_run = FALSE,
    marker_path = file.path(directory, "success.csv"),
    log_path = file.path(directory, "runs.csv"),
    prism_update = daily_publish_prism_fixture(TRUE),
    snow_update = daily_publish_snow_fixture,
    station_update = function(today) stop("ACIS unavailable"),
    site_fingerprint = function() "other-map-change",
    publish = function(dry_run) called <<- TRUE,
    notify = function(event, message) invisible(NULL)),
    "Station update failed")
  testthat::expect_true(called)
  testthat::expect_identical(result$status, "PUBLISHED")
  testthat::expect_identical(result$stations$status, "ERROR")
})

testthat::test_that("PRISM failure stops publication", {
  directory <- tempfile("swc-prism-fail-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  called <- FALSE
  testthat::expect_error(run_swc_daily_publish(
    marker_path = file.path(directory, "success.csv"),
    log_path = file.path(directory, "runs.csv"),
    prism_update = function() stop("PRISM failed"),
    snow_update = daily_publish_snow_fixture,
    station_update = daily_publish_station_fixture,
    site_fingerprint = function() "new",
    publish = function(dry_run) called <<- TRUE,
    notify = function(event, message) invisible(NULL)), "PRISM failed")
  testthat::expect_false(called)
  testthat::expect_false(file.exists(file.path(directory, "success.csv")))
})

testthat::test_that("live workflow reports milestones and a success", {
  directory <- tempfile("swc-notify-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  events <- character()
  result <- run_swc_daily_publish(
    today = as.Date("2026-10-02"), dry_run = FALSE,
    marker_path = file.path(directory, "success.csv"),
    log_path = file.path(directory, "runs.csv"),
    prism_update = daily_publish_prism_fixture(TRUE),
    snow_update = daily_publish_snow_fixture,
    station_update = daily_publish_station_fixture,
    site_fingerprint = function() "new-site",
    publish = function(dry_run) invisible(NULL),
    notify = function(event, message) events <<- c(events, event))
  testthat::expect_identical(result$status, "PUBLISHED")
  testthat::expect_identical(events,
                             c("started", "progress", "progress", "progress",
                               "success"))
})

testthat::test_that("final notices report elapsed time and fresh run statistics", {
  directory <- tempfile("swc-summary-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  notices <- list()
  prism <- function() list(summary = data.frame(
    data_changed = TRUE, downloaded = 27L, downloaded_changed = 3L,
    processed = 3L, maps_rebuilt = TRUE))
  publish <- function(dry_run) list(validation = list(
    current_passed = 51L, current_total = 51L,
    archive_passed = 352L, archive_total = 352L,
    archive_years = 44L, legacy_layout_maps = 16L))
  args <- list(today = as.Date("2026-10-02"), dry_run = FALSE,
               marker_path = file.path(directory, "success.csv"),
               log_path = file.path(directory, "runs.csv"),
               prism_update = prism,
               snow_update = daily_publish_snow_fixture,
               station_update = function(today) list(
                 status = "UPDATED", stations = 62L, mapped = 51L,
                 pending = 0L),
               site_fingerprint = function() "new-site", publish = publish,
               notify = function(event, message)
                 notices[[length(notices) + 1L]] <<- list(
                   event = event, message = message))
  first <- do.call(run_swc_daily_publish, args)
  success <- tail(notices, 1L)[[1L]]$message
  testthat::expect_match(success, "Published in [0-9]+[smh]")
  testthat::expect_match(success, "PRISM: 27 checked, 3 changed, 3 processed; maps rebuilt")
  testthat::expect_match(success, "Stations: updated; 62 records \\(51 mapped\\)")
  testthat::expect_match(success, "51/51 current, 352/352 historic passed")
  testthat::expect_false(grepl("legacy", success, fixed = TRUE))
  testthat::expect_true(is.finite(first$elapsed_seconds))
  testthat::expect_equal(first$validation$current_passed, 51L)
  notices <- list()
  second <- do.call(run_swc_daily_publish, args)
  testthat::expect_identical(second$status, "SKIPPED_UNCHANGED")
  testthat::expect_match(tail(notices, 1L)[[1L]]$message,
                         "upload skipped", fixed = TRUE)
  testthat::expect_false(grepl("Validated maps", tail(notices, 1L)[[1L]]$message,
                              fixed = TRUE))
})

testthat::test_that("failure notice includes elapsed time and stage, not raw error", {
  directory <- tempfile("swc-error-summary-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  last_notice <- NULL
  testthat::expect_error(run_swc_daily_publish(
    today = as.Date("2026-10-02"), dry_run = FALSE,
    marker_path = file.path(directory, "success.csv"),
    log_path = file.path(directory, "runs.csv"),
    prism_update = daily_publish_prism_fixture(FALSE),
    snow_update = daily_publish_snow_fixture,
    station_update = daily_publish_station_fixture,
    site_fingerprint = function() "new-site",
    publish = function(dry_run) stop("private render detail"),
    notify = function(event, message) if (event == "error")
      last_notice <<- message), "private render detail")
  testthat::expect_match(last_notice, "Failed in [0-9]+[smh]")
  testthat::expect_match(last_notice, "Stage: site publication")
  testthat::expect_false(grepl("private render detail", last_notice, fixed = TRUE))
})

testthat::test_that("invalid PRISM result still reports the original failure", {
  directory <- tempfile("swc-invalid-prism-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  notice <- NULL
  testthat::expect_error(run_swc_daily_publish(
    dry_run = FALSE,
    marker_path = file.path(directory, "success.csv"),
    log_path = file.path(directory, "runs.csv"),
    prism_update = function() list(summary = data.frame(other = TRUE)),
    snow_update = daily_publish_snow_fixture,
    station_update = daily_publish_station_fixture,
    site_fingerprint = function() "unchanged",
    publish = function(dry_run) stop("should not publish"),
    notify = function(event, message) if (event == "error")
      notice <<- message), "PRISM update returned an invalid summary")
  testthat::expect_match(notice, "Stage: PRISM update")
})

testthat::test_that("deployment summary keeps validation counts compact", {
  source(file.path(project_root, "scripts", "deploy-site-s3.R"), local = TRUE)
  directory <- tempfile("swc-validation-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  current <- file.path(directory, "current.csv")
  archive <- file.path(directory, "archive.csv")
  write.csv(data.frame(enabled = c(TRUE, TRUE, FALSE),
                       validation_status = c("PASS", "PASS", "PASS")),
            current, row.names = FALSE)
  write.csv(data.frame(water_year = c(2024L, 2024L, 2025L),
                       validation_status = rep("PASS", 3L),
                       legacy_layout = c(FALSE, TRUE, FALSE)),
            archive, row.names = FALSE)
  result <- swc_deploy_validation_summary(current, archive)
  testthat::expect_equal(result$current_passed, 2L)
  testthat::expect_equal(result$current_total, 2L)
  testthat::expect_equal(result$archive_years, 2L)
  testthat::expect_equal(result$legacy_layout_maps, 1L)
  write.csv(data.frame(water_year = 2024L,
                       validation_status = "FAIL", legacy_layout = FALSE),
            archive, row.names = FALSE)
  testthat::expect_error(swc_deploy_validation_summary(current, archive),
                         "contain failures")
})

testthat::test_that("dry runs do not send phone alerts", {
  directory <- tempfile("swc-notify-preview-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  called <- FALSE
  run_swc_daily_publish(
    today = as.Date("2026-10-02"), dry_run = TRUE,
    marker_path = file.path(directory, "success.csv"),
    log_path = file.path(directory, "runs.csv"),
    prism_update = daily_publish_prism_fixture(TRUE),
    snow_update = daily_publish_snow_fixture,
    station_update = daily_publish_station_fixture,
    site_fingerprint = function() "new-site",
    publish = function(dry_run) invisible(NULL),
    notify = function(event, message) called <<- TRUE)
  testthat::expect_false(called)
})

testthat::test_that("publication errors alert without hiding the original failure", {
  directory <- tempfile("swc-notify-error-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  events <- character()
  testthat::expect_error(run_swc_daily_publish(
    today = as.Date("2026-10-02"), dry_run = FALSE,
    marker_path = file.path(directory, "success.csv"),
    log_path = file.path(directory, "runs.csv"),
    prism_update = daily_publish_prism_fixture(TRUE),
    snow_update = daily_publish_snow_fixture,
    station_update = daily_publish_station_fixture,
    site_fingerprint = function() "new-site",
    publish = function(dry_run) stop("render failed"),
    notify = function(event, message) events <<- c(events, event)),
    "render failed")
  testthat::expect_identical(tail(events, 1L), "error")
})

testthat::test_that("ntfy delivery errors do not fail publication", {
  directory <- tempfile("swc-notify-delivery-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  testthat::expect_warning(result <- run_swc_daily_publish(
    today = as.Date("2026-10-02"), dry_run = FALSE,
    marker_path = file.path(directory, "success.csv"),
    log_path = file.path(directory, "runs.csv"),
    prism_update = daily_publish_prism_fixture(TRUE),
    snow_update = daily_publish_snow_fixture,
    station_update = daily_publish_station_fixture,
    site_fingerprint = function() "new-site",
    publish = function(dry_run) invisible(NULL),
    notify = function(event, message) stop("token should not appear")),
    "ntfy notification could not be delivered")
  testthat::expect_identical(result$status, "PUBLISHED")
})

testthat::test_that("rendered snow page must link its current images", {
  directory <- tempfile("swc-snow-page-")
  dir.create(file.path(directory, "pages"), recursive = TRUE)
  site <- tempfile("swc-snow-source-")
  dir.create(site)
  on.exit({
    unlink(directory, recursive = TRUE)
    unlink(site, recursive = TRUE)
  }, add = TRUE)
  page <- file.path(site, "current-snow.qmd")
  rendered <- file.path(directory, "pages", "current-snow.html")
  writeLines("Current-season snow maps are waiting for a listed archive.", page)
  writeLines("<p>waiting for a listed archive</p>", rendered)
  testthat::expect_invisible(swc_daily_publish_validate_snow(directory, page))
  links <- paste0("../maps/generated/snodas/current/",
                  c("swe-observed.png", "swe-departure.png"))
  writeLines(c("**Latest map date: October 1, 2026**",
               paste0("![](", links, ")")), page)
  rendered_links <- function(paths) c("<p>October 1, 2026</p>",
    paste0('<img src="', paths, '">'),
    paste0('<a href="', paths, '">Open full-resolution PNG</a>'))
  writeLines(rendered_links(links), rendered)
  testthat::expect_error(swc_daily_publish_validate_snow(directory, page),
                         "images are missing")
  image_dir <- file.path(directory, "maps", "generated", "snodas", "current")
  dir.create(image_dir, recursive = TRUE)
  writeBin(as.raw(1L), file.path(image_dir, "swe-observed.png"))
  writeBin(as.raw(1L), file.path(image_dir, "swe-departure.png"))
  testthat::expect_invisible(swc_daily_publish_validate_snow(directory, page))
  writeLines(sub("October 1, 2026", "old date", rendered_links(links)), rendered)
  testthat::expect_error(swc_daily_publish_validate_snow(directory, page),
                         "date is stale")
  writeLines(rendered_links(sub("^\\.\\./", "../../", links)), rendered)
  testthat::expect_error(swc_daily_publish_validate_snow(directory, page),
                         "unlinked")
})
