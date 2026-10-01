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
