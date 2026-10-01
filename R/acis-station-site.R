# Publishable snapshot of the screened, local ACIS station explorer.
# Source after the station explorer and publication-audit modules.

swc_station_beta_files <- c(
  "index.html", "explorer.js", "explorer.css", "leaflet.js", "leaflet.css",
  "leaflet-package-LICENSE", "station-explorer-data.csv",
  "coverage-by-station.csv", "coverage-summary.csv")

swc_station_beta_snapshot <- function(directory) {
  paths <- file.path(directory, swc_station_beta_files)
  if (!all(file.exists(paths)) || any(file.info(paths)$size <= 0))
    stop("Station snapshot is missing a required nonempty file.", call. = FALSE)
  rows <- read.csv(file.path(directory, "station-explorer-data.csv"),
                   stringsAsFactors = FALSE)
  required <- c("uid", "role", "period", "as_of", "pcpn_status",
                "tmean_status", "pcpn_value", "tmean_value",
                "pcpn_anomaly", "pcpn_percentile")
  if (!nrow(rows) || !all(required %in% names(rows)) ||
      length(unique(rows$as_of)) != 1L ||
      is.na(as.Date(rows$as_of[[1L]])) ||
      anyDuplicated(rows[c("uid", "period")]) ||
      !setequal(unique(rows$period), acis_station_explorer_periods))
    stop("Station snapshot has invalid data or period coverage.", call. = FALSE)
  details <- file.path(directory, "station-details",
                       paste0(unique(rows$uid), ".json"))
  if (!all(file.exists(details)) || any(file.info(details)$size <= 0))
    stop("Station snapshot is missing one or more station details.", call. = FALSE)
  html <- paste(readLines(file.path(directory, "index.html"), warn = FALSE),
                collapse = "\n")
  if (!grepl("id=\"explorer-data\"", html, fixed = TRUE) ||
      !grepl(rows$as_of[[1L]], html, fixed = TRUE))
    stop("Station snapshot HTML does not match its data date.", call. = FALSE)
  if (any(rows$pcpn_status == "PROVISIONAL" &
          (is.finite(rows$pcpn_anomaly) | is.finite(rows$pcpn_percentile))))
    stop("A provisional precipitation total has a comparison value.",
         call. = FALSE)
  list(date = as.Date(rows$as_of[[1L]]), rows = rows,
       stations = length(unique(rows$uid)),
       mapped = length(unique(rows$uid[rows$role == "fixed"])),
       provisional_30day = sum(rows$period == "30day" &
                                 rows$pcpn_status == "PROVISIONAL"),
       partial_temperature_30day = sum(rows$period == "30day" &
                                         rows$tmean_status == "PARTIAL"))
}

swc_station_beta_stage <- function(
    source_dir = file.path(swc_acis_station_dir, "station-explorer-prototype"),
    destination = file.path("site", "stations")) {
  parent <- normalizePath(dirname(destination), winslash = "/", mustWork = TRUE)
  if (basename(destination) != "stations" ||
      basename(parent) != "site" ||
      !file.exists(file.path(parent, "_quarto.yml")))
    stop("Station staging destination must be this site's stations directory.",
         call. = FALSE)
  snapshot <- swc_station_beta_snapshot(source_dir)
  if (dir.exists(destination)) {
    previous <- swc_station_beta_snapshot(destination)
    if (previous$date > snapshot$date)
      stop("Refusing to replace a newer verified station snapshot.",
           call. = FALSE)
  }
  stage <- tempfile("stations-stage-", tmpdir = parent)
  backup <- tempfile("stations-backup-", tmpdir = parent)
  dir.create(stage)
  on.exit(if (dir.exists(stage)) unlink(stage, recursive = TRUE), add = TRUE)
  copied <- file.copy(file.path(source_dir, swc_station_beta_files), stage)
  dir.create(file.path(stage, "station-details"))
  details <- list.files(file.path(source_dir, "station-details"),
                        pattern = "^[0-9]+\\.json$", full.names = TRUE)
  detail_copied <- file.copy(details, file.path(stage, "station-details"))
  if (!all(copied) || !length(details) || !all(detail_copied))
    stop("Could not copy the full station snapshot; last good page retained.",
         call. = FALSE)
  swc_station_beta_snapshot(stage)
  had_previous <- dir.exists(destination)
  if (had_previous && !file.rename(destination, backup))
    stop("Could not preserve the last good station page.", call. = FALSE)
  promoted <- file.rename(stage, destination)
  if (!promoted) {
    if (had_previous && !file.rename(backup, destination))
      stop("Station promotion failed and the previous page needs manual recovery at ",
           backup, call. = FALSE)
    stop("Station promotion failed; last good page restored.", call. = FALSE)
  }
  if (had_previous) unlink(backup, recursive = TRUE)
  snapshot
}

swc_station_beta_log <- function(row, path = file.path(
    "data", "diagnostics", "acis-stations", "beta-update-runs.csv")) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write.table(row, path, sep = ",", row.names = FALSE,
              col.names = !file.exists(path) || file.info(path)$size == 0,
              append = file.exists(path) && file.info(path)$size > 0,
              qmethod = "double")
  invisible(path)
}

run_swc_station_beta_update <- function(today = Sys.Date(),
                                        max_requests = 62L,
                                        refresh_days = 45L,
                                        fetch = acis_station_fetch,
                                        log_path = file.path(
                                          "data", "diagnostics", "acis-stations",
                                          "beta-update-runs.csv")) {
  started <- Sys.time()
  target <- as.Date(today) - 1L
  row <- data.frame(run_utc = format(started, "%Y-%m-%d %H:%M:%S UTC", tz = "UTC"),
                    target_date = as.character(target), status = "ERROR",
                    station_date = NA_character_, stations = NA_integer_,
                    mapped = NA_integer_, pending_caches = NA_integer_,
                    refresh_failures = NA_integer_, provisional_30day = NA_integer_,
                    partial_temperature_30day = NA_integer_,
                    error = NA_character_, elapsed_seconds = NA_real_)
  on.exit({
    row$elapsed_seconds <- round(as.numeric(difftime(Sys.time(), started,
                                                      units = "secs")), 3)
    swc_station_beta_log(row, log_path)
  }, add = TRUE)
  tryCatch({
    update <- run_acis_station_explorer_update_pilot(
      as_of = target, max_requests = max_requests,
      refresh_days = refresh_days, build_page = TRUE, fetch = fetch)
    if (is.na(update$page)) stop("Station explorer did not build a page.")
    # The publication screen writes the fully screened page and readiness files.
    sys.source(file.path("scripts", "audit-acis-station-publication.R"),
               envir = environment())
    snapshot <- swc_station_beta_stage()
    row$status <- if (length(update$failures) || any(update$after$pending))
      "UPDATED_WITH_STALE_STATIONS" else "UPDATED"
    row$station_date <- as.character(snapshot$date)
    row$stations <- snapshot$stations
    row$mapped <- snapshot$mapped
    row$pending_caches <- sum(update$after$pending)
    row$refresh_failures <- length(update$failures)
    row$provisional_30day <- snapshot$provisional_30day
    row$partial_temperature_30day <- snapshot$partial_temperature_30day
    list(status = row$status, date = snapshot$date,
         stations = snapshot$stations, mapped = snapshot$mapped,
         pending = row$pending_caches, failures = update$failures,
         provisional_30day = snapshot$provisional_30day,
         partial_temperature_30day = snapshot$partial_temperature_30day)
  }, error = function(error) {
    row$error <<- conditionMessage(error)
    stop(error)
  })
}
