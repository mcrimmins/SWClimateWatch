source(file.path(project_root, "R", "acis-station-explorer-prototype.R"))
source(file.path(project_root, "R", "acis-station-site.R"))
source(file.path(project_root, "R", "daily-publish.R"))

station_beta_fixture <- function(path, date) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(path, "station-details"), showWarnings = FALSE)
  for (name in setdiff(swc_station_beta_files,
                       c("index.html", "station-explorer-data.csv")))
    writeLines("fixture", file.path(path, name))
  rows <- data.frame(uid = rep(123L, 5L), role = "fixed",
                     period = acis_station_explorer_periods,
                     as_of = as.character(date), pcpn_status = "COMPLETE",
                     tmean_status = "COMPLETE", pcpn_value = 1,
                     tmean_value = 70, pcpn_anomaly = 0,
                     pcpn_percentile = 50)
  write.csv(rows, file.path(path, "station-explorer-data.csv"), row.names = FALSE)
  writeLines(paste0('<div id="explorer-data">', date, '</div>'),
             file.path(path, "index.html"))
  writeLines("{}", file.path(path, "station-details", "123.json"))
  invisible(rows)
}

testthat::test_that("staging rejects invalid or older source without losing the good page", {
  root <- tempfile("swc-station-stage-")
  site <- file.path(root, "site")
  dir.create(site, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeLines("project:", file.path(site, "_quarto.yml"))
  source <- file.path(root, "source")
  destination <- file.path(site, "stations")
  station_beta_fixture(source, "2026-09-30")
  first <- swc_station_beta_stage(source, destination)
  testthat::expect_identical(first$stations, 1L)
  testthat::expect_identical(swc_station_beta_snapshot(destination)$date,
                             as.Date("2026-09-30"))
  station_beta_fixture(source, "2026-09-29")
  testthat::expect_error(swc_station_beta_stage(source, destination), "newer")
  testthat::expect_identical(swc_station_beta_snapshot(destination)$date,
                             as.Date("2026-09-30"))
  station_beta_fixture(source, "2026-10-01")
  rows <- read.csv(file.path(source, "station-explorer-data.csv"))
  rows$pcpn_status[[1L]] <- "PROVISIONAL"
  rows$pcpn_anomaly[[1L]] <- 1
  write.csv(rows, file.path(source, "station-explorer-data.csv"), row.names = FALSE)
  testthat::expect_error(swc_station_beta_stage(source, destination),
                         "provisional")
  testthat::expect_identical(swc_station_beta_snapshot(destination)$date,
                             as.Date("2026-09-30"))
})

testthat::test_that("render validation requires the page and every station detail", {
  root <- tempfile("swc-station-render-")
  station_beta_fixture(file.path(root, "stations"), "2026-09-30")
  dir.create(file.path(root, "pages"))
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeLines('<iframe src="../stations/index.html?embedded=1"></iframe>',
             file.path(root, "pages", "station-conditions.html"))
  testthat::expect_invisible(swc_daily_publish_validate_stations(root))
  unlink(file.path(root, "stations", "station-details", "123.json"))
  testthat::expect_error(swc_daily_publish_validate_stations(root),
                         "details are missing")
})

testthat::test_that("station staging carries cumulative curves and rejects missing comparisons", {
  root <- tempfile("swc-cumulative-stage-")
  site <- file.path(root, "site"); dir.create(site, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeLines("project:", file.path(site, "_quarto.yml"))
  source_dir <- file.path(root, "source")
  station_beta_fixture(source_dir, "2025-03-01")
  rows <- read.csv(file.path(source_dir, "station-explorer-data.csv"))
  rows$uid <- 1L
  write.csv(rows, file.path(source_dir, "station-explorer-data.csv"), row.names = FALSE)
  file.rename(file.path(source_dir, "station-details", "123.json"),
    file.path(source_dir, "station-details", "1.json"))
  station <- data.frame(uid = 1L, sid = "test", name = "Test", state = "AZ", role = "fixed")
  dates <- seq(as.Date("2022-10-01"), as.Date("2025-03-01"), by = "day")
  cache <- list(uid = 1L, as_of = as.Date("2025-03-01"), daily = data.frame(
    date = dates, variable = "pcpn", numeric_value = 0.1, observed = TRUE,
    flag = "", trace = FALSE, accumulated = FALSE))
  write_acis_station_cumulative_site(station, list(cache), cache$as_of, source_dir,
    file.path(root, "cache"), file.path(project_root, "scripts", "station-cumulative-assets"))
  writeLines('const cumulative = "cumulative/index.html";', file.path(source_dir, "explorer.js"))
  destination <- file.path(site, "stations")
  swc_station_beta_stage(source_dir, destination)
  testthat::expect_true(file.exists(file.path(destination, "cumulative", "history", "1", "2023.json")))
  dir.create(file.path(site, "pages"))
  writeLines('<iframe src="../stations/index.html?embedded=1"></iframe>',
    file.path(site, "pages", "station-conditions.html"))
  testthat::expect_invisible(swc_daily_publish_validate_stations(site))
  unlink(file.path(destination, "cumulative", "history", "1", "2023.json"))
  testthat::expect_error(swc_daily_publish_validate_stations(site), "comparison curve")
  unlink(file.path(source_dir, "cumulative", "1.json"))
  testthat::expect_error(swc_station_beta_stage(source_dir, destination), "payload is missing")
})
