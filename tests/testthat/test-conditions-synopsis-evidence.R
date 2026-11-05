source(file.path(project_root, "R/conditions-synopsis-evidence.R"))
synopsis_test_config <- function() synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))

testthat::test_that("seasonal priorities cover boundaries and leap day without asserting onset", {
  config <- synopsis_test_config()
  dates <- c("2026-12-01", "2027-03-31", "2027-04-01", "2027-05-31", "2027-06-01",
    "2027-06-14", "2027-06-15", "2027-09-30", "2027-10-01", "2028-02-29")
  actual <- vapply(dates, function(d) synopsis_season(d, config)$id, character(1))
  testthat::expect_equal(unname(actual), c("winter", "winter", "spring", "spring", "early_summer",
    "early_summer", "summer", "summer", "fall", "winter"))
  specs <- synopsis_grid_specs(".", "2026-10-01")
  testthat::expect_equal(specs$start, c(rep("2026-09-02", 3), rep("2026-10-01", 2)))
  testthat::expect_error(synopsis_date(c("2026-01-01", "2026-01-02")), "one valid")
})

testthat::test_that("regional statistics use area support, strict tails and unavailable rather than zero", {
  config <- synopsis_test_config()
  stat <- synopsis_regional_stats(c(0, 100), c(1, 3), "percentile", config)
  testthat::expect_equal(unname(stat$values), c(25, 75, 25, 75))
  edge <- synopsis_regional_stats(c(10, 33, 67, 90), rep(1, 4), "percentile", config)
  testthat::expect_equal(unname(edge$values), c(25, 25, 0, 0))
  rain <- synopsis_regional_stats(c(.1 - 1e-8, 0), c(1, 3), "rain", config)
  testthat::expect_equal(rain$values[[2]], 25)
  low <- synopsis_regional_stats(c(1, NA), c(97, 3), "rain", config)
  testthat::expect_equal(low$status, "LOW_COVERAGE")
  testthat::expect_true(all(is.na(low$values)))
  enough <- synopsis_regional_stats(c(0, NA), c(98, 2), "rain", config)
  testthat::expect_equal(enough$status, "AVAILABLE_CACHED")
  testthat::expect_equal(enough$values[[1]], 0)
  for (x in list(c(101, 50), c(Inf, 50), c(-1, 50))) {
    testthat::expect_equal(synopsis_regional_stats(x, c(1, 1), "percentile", config)$status, "INVALID_RANGE")
  }
  testthat::expect_equal(synopsis_regional_stats(c(1, 2), c(0, 0), "rain", config)$status, "LOW_COVERAGE")
})

testthat::test_that("bad or missing grids withhold evidence and date identity is enforced", {
  root <- tempfile(); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  specs <- synopsis_grid_specs(root, "2026-10-05")
  r <- terra::rast(nrows = 1, ncols = 2, xmin = -114, xmax = -110, ymin = 32, ymax = 34, crs = "EPSG:4326")
  terra::values(r) <- c(5, 7); terra::time(r) <- as.Date("2026-10-04")
  dir.create(dirname(specs$path[1]), recursive = TRUE)
  terra::writeRaster(r, specs$path[1])
  facts <- synopsis_grid_facts(specs, synopsis_test_config(), function(r) list(AZNM = c(1, 3), AZ = c(1, 0), NM = c(0, 3)))
  testthat::expect_equal(nrow(facts), 39L)
  testthat::expect_true(all(is.na(facts$value)))
  testthat::expect_true(all(facts$status == "UNAVAILABLE"))
  testthat::expect_match(facts$note[1], "time does not match")
  testthat::expect_true(any(grepl("missing", facts$note)))
})

testthat::test_that("station candidates need exact periods, complete values and fixed-station identity", {
  root <- tempfile(); dir.create(file.path(root, "site/stations"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  x <- data.frame(uid = 1:5, name = letters[1:5], state = "AZ", role = c("fixed", "threadex", "fixed", "fixed", "fixed"),
    period = "30day", as_of = c(rep("2026-10-05", 4), "2026-10-06"), period_start = "2026-09-06",
    pcpn_status = c("AVAILABLE", "AVAILABLE", "PARTIAL", "AVAILABLE", "AVAILABLE"),
    pcpn_missing_days = 0, pcpn_flagged_days = c(0, 0, 0, 1, 0),
    max_daily_pcpn = c(1, 20, 10, 12, 13), max_daily_pcpn_date = "2026-10-01")
  utils::write.csv(x, file.path(root, "site/stations/station-explorer-data.csv"), row.names = FALSE)
  inventory <- synopsis_station_inventory(root, as.Date("2026-10-05"), synopsis_test_config())
  testthat::expect_equal(inventory$eligible_stations, 1L)
  testthat::expect_equal(inventory$examples$uid, 1L)
  testthat::expect_equal(inventory$matching_rows, 4L)
  testthat::expect_equal(synopsis_snow_inventory(root, as.Date("2026-06-01"))$status, "INACTIVE_SEASON")
  testthat::expect_equal(synopsis_snow_inventory(root, as.Date("2026-12-01"))$status, "UNAVAILABLE")
})

testthat::test_that("inventory reuses grids, invalidates changed content and never advances publication", {
  root <- tempfile(); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  dir.create(file.path(root, "config")); dir.create(file.path(root, "R"))
  file.copy(file.path(project_root, "config/conditions-synopsis.yml"), file.path(root, "config"))
  file.copy(file.path(project_root, "R/config.R"), file.path(root, "R"))
  specs <- synopsis_grid_specs(root, "2026-10-05")
  r <- terra::rast(nrows = 3, ncols = 4, xmin = -114, xmax = -104, ymin = 32, ymax = 36, crs = "EPSG:4326")
  terra::values(r) <- 1; terra::time(r) <- as.Date("2026-10-05")
  for (path in specs$path) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(r, path)
  }
  before <- tools::md5sum(specs$path)
  a <- suppressMessages(build_conditions_synopsis_evidence(root = root, today = as.Date("2026-11-04")))
  b <- suppressMessages(build_conditions_synopsis_evidence(root = root, today = as.Date("2026-11-04")))
  testthat::expect_equal(a$snapshot_date, "2026-10-05")
  testthat::expect_false(a$regional_cache_reused)
  testthat::expect_true(b$regional_cache_reused)
  testthat::expect_null(b$previous_published_snapshot)
  testthat::expect_equal(before, tools::md5sum(specs$path))
  testthat::expect_true(file.exists(file.path(root, "data/diagnostics/conditions-synopsis/report.md")))
  testthat::expect_match(b$facts$reference[b$facts$product == "pcpn_water_year_percentile"][1], "exact calendar endpoint")
  terra::values(r) <- 2; terra::writeRaster(r, specs$path[1], overwrite = TRUE)
  c <- suppressMessages(build_conditions_synopsis_evidence(root = root, today = as.Date("2026-11-04")))
  testthat::expect_false(c$regional_cache_reused)
  testthat::expect_true(all(c$facts$value[c$facts$product == "pcpn_total_30day" & c$facts$metric == "mean"] == 2))
  testthat::expect_error(build_conditions_synopsis_evidence("2026-11-05", root = root, today = as.Date("2026-11-04")), "later")
})

testthat::test_that("snow availability requires both paired checksums and exact prior endpoints", {
  root <- tempfile(); dir.create(file.path(root, "data/processed/snodas"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  x <- expand.grid(date = c("2026-10-05", "2026-09-28"), variable = c("swe", "depth"), stringsAsFactors = FALSE)
  x$path <- paste0(x$date, "-", x$variable, ".tif")
  for (path in x$path) writeLines("checksum fixture, not a raster", file.path(root, path))
  x$md5 <- unname(tools::md5sum(file.path(root, x$path))); x$units <- "inch"
  utils::write.csv(x, file.path(root, "data/processed/snodas/manifest.csv"), row.names = FALSE)
  good <- synopsis_snow_inventory(root, as.Date("2026-10-05"))
  testthat::expect_equal(good$status, "PAIRED_FILES_CHECKSUM_VERIFIED")
  testthat::expect_true(good$seven_day_prior_verified)
  testthat::expect_equal(good$regional_metrics, "DEFERRED_MASK_DEFINITION")
  writeLines("corrupted", file.path(root, x$path[1]))
  testthat::expect_equal(synopsis_snow_inventory(root, as.Date("2026-10-05"))$status, "UNAVAILABLE")
})
