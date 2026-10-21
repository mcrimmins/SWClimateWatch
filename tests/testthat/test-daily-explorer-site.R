source(file.path(project_root, "R", "daily-explorer.R"))
source(file.path(project_root, "R", "daily-explorer-site.R"))
source(file.path(project_root, "R", "daily-publish.R"))

explorer_asset_fixture <- function(directory) {
  dir.create(file.path(directory, "maps"), recursive = TRUE, showWarnings = FALSE)
  for (name in c("index.html", "explorer.js", "explorer.css")) writeLines("fixture", file.path(directory, name))
  image <- "maps/2026-10-02-pcpn-observed.png"
  writeBin(as.raw(c(137, 80, 78, 71)), file.path(directory, image))
  payload <- list(schema_version = 1L, latest_cached_date = "2026-10-02",
    days = list(list(date = "2026-10-02", images = list(pcpn_observed = image))))
  jsonlite::write_json(payload, file.path(directory, "daily-data.json"), auto_unbox = TRUE)
  payload
}

testthat::test_that("site window grows the data water year and includes preceding September", {
  path <- tempfile(); writeLines("grid", path)
  on.exit(unlink(path), add = TRUE)
  manifest <- data.frame(product = "daily", aoi_id = swc_prism$aoi_id,
    variable = "pcpn", path = path, end_date = as.Date("2026-10-02"))
  window <- daily_explorer_site_window(manifest)
  testthat::expect_equal(window$start_date, as.Date("2026-09-01"))
  testthat::expect_equal(window$end_date, as.Date("2026-10-02"))
  testthat::expect_equal(window$water_years, 2026:2027)
  manifest$end_date <- as.Date("2027-03-15")
  testthat::expect_equal(daily_explorer_site_window(manifest)$start_date, window$start_date)
  manifest$end_date <- as.Date("2024-09-30")
  leap <- daily_explorer_site_window(manifest)
  testthat::expect_equal(leap$start_date, as.Date("2023-09-01"))
  testthat::expect_equal(as.integer(leap$end_date - leap$start_date) + 1L, 396L)
  manifest$end_date <- as.Date("2024-10-01")
  testthat::expect_equal(daily_explorer_site_window(manifest)$start_date, as.Date("2024-09-01"))
  short <- daily_explorer_site_window(manifest, 3L)
  testthat::expect_equal(short$start_date, as.Date("2024-09-29"))
  testthat::expect_error(daily_explorer_site_window(manifest, 0), "positive integer")
  testthat::expect_error(daily_explorer_site_window(manifest, "3"), "positive integer")
})

testthat::test_that("missing, unsafe and stale explorer resources block publication", {
  directory <- tempfile(); dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  payload <- explorer_asset_fixture(directory)
  testthat::expect_equal(validate_daily_explorer_assets(directory)$maps, 1)
  path <- file.path(directory, "daily-data.json")
  payload$days[[1L]]$images$pcpn_observed <- "../outside.png"
  jsonlite::write_json(payload, path, auto_unbox = TRUE)
  testthat::expect_error(validate_daily_explorer_assets(directory), "references")
  payload <- explorer_asset_fixture(directory)
  unlink(file.path(directory, payload$days[[1L]]$images$pcpn_observed))
  testthat::expect_error(validate_daily_explorer_assets(directory), "images are missing")
  payload <- explorer_asset_fixture(directory)
  payload$latest_cached_date <- "2026-10-03"
  jsonlite::write_json(payload, path, auto_unbox = TRUE)
  testthat::expect_error(validate_daily_explorer_assets(directory), "stale")
})

testthat::test_that("staging excludes private caches and preserves unchanged asset bytes", {
  directory <- tempfile(); dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  work <- file.path(directory, "work"); output <- file.path(directory, "public")
  raw <- file.path(directory, "input"); writeLines("grid", raw)
  manifest <- data.frame(product = "daily", aoi_id = swc_prism$aoi_id,
    variable = "pcpn", path = raw, end_date = as.Date("2026-10-02"))
  builder <- function(output_dir, ...) {
    explorer_asset_fixture(output_dir)
    dir.create(file.path(output_dir, "cache"), showWarnings = FALSE)
    saveRDS("private", file.path(output_dir, "cache", "date.rds"))
    list(built = 1L, reused = 0L)
  }
  first <- stage_daily_explorer_site(output_dir = output, work_dir = work,
    manifest = manifest, builder = builder)
  testthat::expect_identical(first$status, "STAGED")
  testthat::expect_false(dir.exists(file.path(output, "cache")))
  json <- file.path(output, "daily-data.json")
  before <- tools::md5sum(json); mtime <- file.info(json)$mtime
  obsolete <- file.path(output, "maps", "2026-10-01-pcpn-observed.png")
  keep <- file.path(output, "maps", "do-not-remove.txt")
  writeLines("old", obsolete); writeLines("keep", keep)
  stage_daily_explorer_site(output_dir = output, work_dir = work,
    manifest = manifest, builder = builder)
  testthat::expect_identical(tools::md5sum(json), before)
  testthat::expect_identical(file.info(json)$mtime, mtime)
  testthat::expect_false(file.exists(obsolete))
  testthat::expect_true(file.exists(keep))
})

testthat::test_that("rendered explorer must link the frame and match the staged payload", {
  directory <- tempfile(); dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  staged <- file.path(directory, "source")
  rendered <- file.path(directory, "rendered")
  explorer_asset_fixture(staged)
  explorer_asset_fixture(file.path(rendered, "daily-explorer"))
  dir.create(file.path(rendered, "pages"))
  page <- file.path(rendered, "pages", "daily-explorer.html")
  writeLines('<iframe src="../daily-explorer/index.html?embedded=1"></iframe>', page)
  testthat::expect_equal(swc_daily_publish_validate_explorer(rendered, staged)$maps, 1)
  writeLines("missing frame", page)
  testthat::expect_error(swc_daily_publish_validate_explorer(rendered, staged), "unlinked")
  writeLines('<iframe src="../daily-explorer/index.html?embedded=1"></iframe>', page)
  # Same dates but changed metadata must not silently pass an old Quarto render.
  payload <- jsonlite::read_json(file.path(staged, "daily-data.json"))
  payload$changed <- TRUE
  jsonlite::write_json(payload, file.path(staged, "daily-data.json"), auto_unbox = TRUE)
  testthat::expect_error(swc_daily_publish_validate_explorer(rendered, staged), "stale")
  explorer_asset_fixture(staged)
  writeLines("stale pixels", file.path(rendered, "daily-explorer", "maps", "2026-10-02-pcpn-observed.png"))
  testthat::expect_error(swc_daily_publish_validate_explorer(rendered, staged), "assets are stale")
})
