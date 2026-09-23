daily_update_fixture <- function(
    downloads = data.frame(),
    processed = data.frame(),
    advance_date = FALSE) {
  calls <- new.env(parent = emptyenv())
  calls$maps <- 0L
  calls$overview <- 0L
  calls$site <- 0L
  calls$plan <- 0L
  calls$planned_rows <- NA_integer_
  calls$date <- "2026-09-19"
  list(
    calls = calls,
    sync = function(mode = "update", quiet = FALSE) {
      if (advance_date) calls$date <- "2026-09-20"
      downloads
    },
    plan = function(raw_manifest = NULL, verify_source_md5 = TRUE) {
      calls$plan <- calls$plan + 1L
      calls$planned_rows <- if (is.null(raw_manifest)) NA_integer_ else nrow(raw_manifest)
      calls$verify_source_md5 <- verify_source_md5
      data.frame(refresh = logical())
    },
    process = function(plan, quiet = FALSE) processed,
    maps = function(quiet = FALSE) {
      calls$maps <- calls$maps + 1L
      list(example = data.frame(path = "map.png"))
    },
    overview = function() {
      calls$overview <- calls$overview + 1L
      "overview.png"
    },
    site = function(expected_data_dates = NULL) {
      calls$site <- calls$site + 1L
      data.frame(enabled = c(TRUE, TRUE))
    },
    dates = function() c(
      Temperature = calls$date,
      Precipitation = calls$date
    )
  )
}

testthat::test_that("daily update skips maps when no files changed", {
  fixture <- daily_update_fixture(
    downloads = data.frame(
      path = paste0("revision-", seq_len(24L), ".tif"),
      changed = FALSE
    )
  )
  timing_path <- tempfile(fileext = ".csv")
  result <- run_swc_daily_update(
    update_prism = TRUE,
    timing_path = timing_path,
    sync_function = fixture$sync,
    processing_plan_function = fixture$plan,
    processing_function = fixture$process,
    map_function = fixture$maps,
    overview_function = fixture$overview,
    site_function = fixture$site,
    date_function = fixture$dates,
    quiet = TRUE
  )

  testthat::expect_false(result$summary$data_changed)
  testthat::expect_false(result$summary$maps_rebuilt)
  testthat::expect_equal(result$summary$downloaded, 24L)
  testthat::expect_equal(result$summary$downloaded_changed, 0L)
  testthat::expect_equal(fixture$calls$maps, 0L)
  testthat::expect_equal(fixture$calls$overview, 0L)
  testthat::expect_equal(fixture$calls$site, 1L)
  testthat::expect_equal(fixture$calls$plan, 1L)
  testthat::expect_false(fixture$calls$verify_source_md5)
  testthat::expect_true(file.exists(timing_path))
  testthat::expect_equal(
    result$timings$status[result$timings$stage == "processing_plan"],
    "COMPLETE"
  )
  testthat::expect_equal(
    result$timings$status[result$timings$stage == "map_products"],
    "SKIPPED"
  )
})

testthat::test_that("daily update rebuilds maps after data changes", {
  fixture <- daily_update_fixture(
    downloads = data.frame(path = "raw.tif"),
    processed = data.frame(path = "processed.tif"),
    advance_date = TRUE
  )
  result <- run_swc_daily_update(
    update_prism = TRUE,
    timing_path = NULL,
    sync_function = fixture$sync,
    processing_plan_function = fixture$plan,
    processing_function = fixture$process,
    map_function = fixture$maps,
    overview_function = fixture$overview,
    site_function = fixture$site,
    date_function = fixture$dates,
    quiet = TRUE
  )

  testthat::expect_true(result$summary$data_changed)
  testthat::expect_true(result$summary$maps_rebuilt)
  testthat::expect_equal(result$summary$downloaded, 1L)
  testthat::expect_equal(result$summary$processed, 1L)
  testthat::expect_equal(fixture$calls$plan, 1L)
  testthat::expect_false(fixture$calls$verify_source_md5)
  testthat::expect_equal(fixture$calls$maps, 1L)
  testthat::expect_equal(fixture$calls$overview, 1L)
  testthat::expect_equal(result$summary$before_dates, "Temperature=2026-09-19;Precipitation=2026-09-19")
  testthat::expect_equal(result$summary$after_dates, "Temperature=2026-09-20;Precipitation=2026-09-20")
})

testthat::test_that("daily update supports deliberate map-only rebuilds", {
  fixture <- daily_update_fixture()
  result <- run_swc_daily_update(
    update_prism = FALSE,
    force_maps = TRUE,
    timing_path = NULL,
    sync_function = fixture$sync,
    processing_plan_function = fixture$plan,
    processing_function = fixture$process,
    map_function = fixture$maps,
    overview_function = fixture$overview,
    site_function = fixture$site,
    date_function = fixture$dates,
    quiet = TRUE
  )

  testthat::expect_false(result$summary$data_changed)
  testthat::expect_true(result$summary$maps_rebuilt)
  testthat::expect_equal(result$summary$downloaded, 0L)
  testthat::expect_equal(fixture$calls$plan, 0L)
  testthat::expect_equal(fixture$calls$maps, 1L)
  testthat::expect_equal(fixture$calls$overview, 1L)
  testthat::expect_equal(
    result$timings$status[result$timings$stage == "download"],
    "SKIPPED"
  )
  testthat::expect_equal(
    result$timings$status[result$timings$stage == "map_products"],
    "COMPLETE"
  )
})

testthat::test_that("development mode retains overview and catalog builds", {
  fixture <- daily_update_fixture()
  result <- run_swc_daily_update(
    update_prism = FALSE,
    timing_path = NULL,
    sync_function = fixture$sync,
    processing_plan_function = fixture$plan,
    processing_function = fixture$process,
    map_function = fixture$maps,
    overview_function = fixture$overview,
    site_function = fixture$site,
    date_function = fixture$dates,
    quiet = TRUE
  )

  testthat::expect_false(result$summary$maps_rebuilt)
  testthat::expect_equal(fixture$calls$maps, 0L)
  testthat::expect_equal(fixture$calls$overview, 1L)
  testthat::expect_equal(fixture$calls$site, 1L)
})
