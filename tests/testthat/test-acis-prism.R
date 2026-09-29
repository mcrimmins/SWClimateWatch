testthat::test_that("bootstrap plans are chunked by variable and date", {
  plan <- plan_prism_download(
    mode = "bootstrap",
    variables = c("maxt", "pcpn"),
    start = as.Date("1991-01-01"),
    end = as.Date("1991-02-10"),
    chunk_days = 31L,
    raw_dir = tempfile("raw-")
  )

  testthat::expect_equal(nrow(plan), 4L)
  testthat::expect_equal(unique(plan$start_date), as.Date(c("1991-01-01", "1991-02-01")))
  testthat::expect_equal(unique(plan$end_date), as.Date(c("1991-01-31", "1991-02-10")))
  testthat::expect_setequal(unique(plan$variable), c("maxt", "pcpn"))
  testthat::expect_true(all(!plan$refresh))
  testthat::expect_true(all(grepl("az-nm-pad050", plan$path, fixed = TRUE)))
})

testthat::test_that("default bootstrap chunks follow calendar months", {
  plan <- plan_prism_download(
    mode = "bootstrap",
    variables = "maxt",
    start = as.Date("2020-01-15"),
    end = as.Date("2020-03-10"),
    raw_dir = tempfile("raw-")
  )

  testthat::expect_equal(
    plan$start_date,
    as.Date(c("2020-01-15", "2020-02-01", "2020-03-01"))
  )
  testthat::expect_equal(
    plan$end_date,
    as.Date(c("2020-01-31", "2020-02-29", "2020-03-10"))
  )
})

testthat::test_that("default bootstrap spans the documented stable archive", {
  plan <- plan_prism_download(
    mode = "bootstrap",
    raw_dir = tempfile("raw-")
  )

  testthat::expect_equal(nrow(plan), 1620L)
  testthat::expect_equal(min(plan$start_date), as.Date("1981-01-01"))
  testthat::expect_equal(max(plan$end_date), as.Date("2025-12-31"))
  testthat::expect_setequal(unique(plan$variable), c("maxt", "mint", "pcpn"))
})

testthat::test_that("default AOI includes a half-degree pad", {
  testthat::expect_equal(
    unname(swc_region$bbox),
    c(-115.6, 30.75, -102.45, 37.6)
  )

  plan <- plan_prism_download(
    "bootstrap",
    variables = "maxt",
    start = as.Date("2020-01-01"),
    end = as.Date("2020-01-01"),
    raw_dir = tempfile("raw-")
  )
  testthat::expect_equal(plan$bbox, "-115.6,30.75,-102.45,37.6")
  testthat::expect_equal(plan$aoi_id, "az-nm-pad050")
})

testthat::test_that("update plans contain the PRISM revision schedule", {
  plan <- plan_prism_download(
    mode = "update",
    variables = "maxt",
    today = as.Date("2026-08-30"),
    revision_ages = c(2L, 6L, 31L),
    manifest = data.frame(),
    raw_dir = tempfile("raw-")
  )

  testthat::expect_equal(
    plan$start_date,
    as.Date(c("2026-07-30", "2026-08-24", "2026-08-28"))
  )
  testthat::expect_true(all(plan$start_date == plan$end_date))
  testthat::expect_true(all(plan$refresh))
})

testthat::test_that("default update includes a post-six-month finalization check", {
  today <- as.Date("2026-09-23")
  plan <- plan_prism_download(
    mode = "update",
    today = today,
    manifest = data.frame(),
    raw_dir = tempfile("raw-")
  )

  testthat::expect_equal(tail(swc_prism$revision_ages, 1L), 215L)
  testthat::expect_equal(nrow(plan), 27L)
  testthat::expect_setequal(
    unique(plan$start_date),
    today - swc_prism$revision_ages
  )
  testthat::expect_equal(
    sum(plan$start_date == today - 215L),
    length(swc_prism$variables)
  )
  testthat::expect_true(all(plan$refresh))
})

testthat::test_that("catchup plans use complete calendar months", {
  plan <- plan_prism_download(
    mode = "catchup",
    variables = "maxt",
    today = as.Date("2026-09-11"),
    raw_dir = tempfile("raw-")
  )

  testthat::expect_equal(nrow(plan), 8L)
  testthat::expect_equal(min(plan$start_date), as.Date("2026-01-01"))
  testthat::expect_equal(max(plan$end_date), as.Date("2026-08-31"))
  testthat::expect_true(all(grepl("catchup", plan$path, fixed = TRUE)))
  testthat::expect_true(all(!plan$refresh))
})

testthat::test_that("catchup is empty when no complete month follows the archive", {
  plan <- plan_prism_download(
    mode = "catchup",
    variables = "maxt",
    today = as.Date("2026-01-15"),
    raw_dir = tempfile("raw-")
  )

  testthat::expect_equal(nrow(plan), 0L)
})

testthat::test_that("an up-to-date manifest does not create a backwards missing tail", {
  manifest <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    end_date = as.Date("2026-08-29")
  )
  plan <- plan_prism_download(
    mode = "update",
    variables = "maxt",
    today = as.Date("2026-08-30"),
    revision_ages = 2L,
    manifest = manifest,
    raw_dir = tempfile("raw-")
  )

  testthat::expect_equal(plan$start_date, as.Date("2026-08-28"))
})

testthat::test_that("update planning ignores manifest records from another AOI", {
  manifest <- data.frame(
    product = "daily",
    aoi_id = "old-unpadded-aoi",
    end_date = as.Date("2020-01-31")
  )
  plan <- plan_prism_download(
    mode = "update",
    variables = "maxt",
    today = as.Date("2026-08-30"),
    revision_ages = 2L,
    manifest = manifest,
    raw_dir = tempfile("raw-")
  )

  testthat::expect_equal(plan$start_date, as.Date("2026-08-28"))
})

testthat::test_that("update planning repairs an interior gap for one variable", {
  days <- seq(as.Date("2026-09-01"), as.Date("2026-09-21"), by = "day")
  manifest <- expand.grid(
    variable = c("maxt", "mint", "pcpn"),
    day = days,
    stringsAsFactors = FALSE
  )
  manifest <- manifest[!(
    manifest$variable == "mint" &
      manifest$day == as.Date("2026-09-17")
  ), , drop = FALSE]
  manifest$product <- "daily"
  manifest$aoi_id <- "az-nm-pad050"
  manifest$start_date <- as.Date(manifest$day)
  manifest$end_date <- as.Date(manifest$day)
  plan <- plan_prism_download(
    "update", today = as.Date("2026-09-24"),
    revision_ages = c(2L, 6L), gap_lookback_days = 23L,
    manifest = manifest, raw_dir = tempfile("raw-")
  )
  gap <- plan[plan$start_date == as.Date("2026-09-17"), , drop = FALSE]
  testthat::expect_identical(gap$variable, "mint")
  testthat::expect_equal(nrow(plan), 7L)
  testthat::expect_true(all(plan$refresh))
})

testthat::test_that("monthly files cover days without individual daily entries", {
  manifest <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    variable = c("maxt", "mint", "pcpn"),
    start_date = as.Date("2026-09-01"),
    end_date = as.Date("2026-09-21")
  )
  plan <- plan_prism_download(
    "update", today = as.Date("2026-09-24"),
    revision_ages = c(2L, 6L), gap_lookback_days = 23L,
    manifest = manifest, raw_dir = tempfile("raw-")
  )
  testthat::expect_equal(nrow(plan), 6L)
  testthat::expect_false(any(plan$start_date == as.Date("2026-09-17")))
})

testthat::test_that("new manifest records can extend a legacy manifest", {
  directory <- tempfile("manifest-")
  dir.create(directory)
  path <- file.path(directory, "manifest.csv")
  legacy <- data.frame(
    product = "daily",
    variable = "maxt",
    path = "legacy.tif",
    start_date = "2020-01-01",
    end_date = "2020-01-01"
  )
  utils::write.csv(legacy, path, row.names = FALSE)
  record <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    variable = "maxt",
    path = "padded.tif",
    start_date = as.Date("2020-01-02"),
    end_date = as.Date("2020-01-02")
  )

  combined <- write_prism_manifest(record, path)
  testthat::expect_equal(nrow(combined), 2L)
  testthat::expect_true("aoi_id" %in% names(combined))
  testthat::expect_true(is.na(combined$aoi_id[combined$path == "legacy.tif"]))
})

testthat::test_that("payload uses Grid2 JSON and one element", {
  plan <- plan_prism_download(
    mode = "bootstrap",
    variables = "mint",
    start = as.Date("2020-01-01"),
    end = as.Date("2020-01-02"),
    raw_dir = tempfile("raw-")
  )
  payload <- prism_daily_payload(plan[1L, ])

  testthat::expect_equal(payload$grid, "prism")
  testthat::expect_equal(payload$elems, list(list(name = "mint")))
  testthat::expect_equal(payload$output, "geotiff")
  testthat::expect_length(payload$bbox, 4L)
})

testthat::test_that("invalid variables and bounding boxes fail early", {
  testthat::expect_error(
    plan_prism_download("bootstrap", variables = "snow"),
    "Unsupported PRISM"
  )
  testthat::expect_error(
    plan_prism_download("bootstrap", bbox = c(-100, 35, -110, 40)),
    "west < east"
  )
  testthat::expect_error(
    plan_prism_download("bootstrap", aoi_id = "AZ NM"),
    "aoi_id"
  )
})

testthat::test_that("request queue skips completed files and enforces its cap", {
  raw_dir <- tempfile("raw-")
  plan <- plan_prism_download(
    "bootstrap",
    variables = "maxt",
    start = as.Date("2020-01-01"),
    end = as.Date("2020-04-30"),
    chunk_days = 31L,
    raw_dir = raw_dir
  )
  dir.create(dirname(plan$path[1L]), recursive = TRUE)
  file.create(plan$path[1L])

  prepared <- prepare_prism_request_queue(plan, max_requests = 2L)

  testthat::expect_equal(prepared$summary[["total"]], 4L)
  testthat::expect_equal(prepared$summary[["already_complete"]], 1L)
  testthat::expect_equal(prepared$summary[["will_run"]], 2L)
  testthat::expect_equal(prepared$summary[["deferred"]], 1L)
  testthat::expect_equal(prepared$queue$path, plan$path[2:3])
  testthat::expect_match(format_prism_plan_summary(prepared$summary), "2 scheduled")
})

testthat::test_that("refresh requests remain eligible when their files exist", {
  plan <- plan_prism_download(
    "update",
    variables = "maxt",
    today = as.Date("2026-08-30"),
    revision_ages = 2L,
    manifest = data.frame(),
    raw_dir = tempfile("raw-")
  )
  dir.create(dirname(plan$path), recursive = TRUE)
  file.create(plan$path)

  prepared <- prepare_prism_request_queue(plan, max_requests = 1L)
  testthat::expect_equal(prepared$summary[["already_complete"]], 0L)
  testthat::expect_equal(prepared$summary[["will_run"]], 1L)
})

testthat::test_that("request safety inputs reject invalid values", {
  plan <- plan_prism_download(
    "bootstrap",
    variables = "maxt",
    start = as.Date("2020-01-01"),
    end = as.Date("2020-01-01"),
    raw_dir = tempfile("raw-")
  )

  testthat::expect_error(prepare_prism_request_queue(plan, max_requests = 0), "positive")
  testthat::expect_error(prepare_prism_request_queue(plan, max_requests = 1.5), "whole")
  testthat::expect_error(
    download_prism_plan(plan, delay_seconds = -1, quiet = TRUE),
    "non-negative"
  )
})

testthat::test_that("an empty plan is safe to preview and download", {
  plan <- data.frame()
  summary <- preview_prism_download(plan)
  records <- download_prism_plan(plan, quiet = TRUE)

  testthat::expect_equal(summary[["total"]], 0L)
  testthat::expect_equal(nrow(records), 0L)
})
