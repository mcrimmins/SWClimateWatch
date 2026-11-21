# Build a separate combined Station Conditions preview from verified snapshots.
station_history_integration_root <- function() "data/diagnostics/station-history-integration"
station_history_browser_files <- function(files) {
  files[!grepl("^cumulative/", files) & grepl("[.](html|js|css|json|png|svg|gif|woff2?)$|^(station-explorer-data|coverage-by-station|coverage-summary)[.]csv$|^leaflet-package-LICENSE$", files)]
}

station_history_copy <- function(paths, from, to, source_hashes = NULL, preserve_dates = FALSE) {
  source <- file.path(from, paths); target <- file.path(to, paths)
  if (any(!file.exists(source))) stop("Missing integration asset: ", source[!file.exists(source)][1L])
  exists <- file.exists(target); changed <- !exists
  if (!is.null(source_hashes) && (length(source_hashes) != length(paths) || anyNA(source_hashes))) stop("Invalid source checksums.")
  if (any(exists)) changed[exists] <- (if (is.null(source_hashes)) unname(tools::md5sum(source[exists])) else unname(source_hashes[exists])) != unname(tools::md5sum(target[exists]))
  if (any(changed)) {
    for (directory in unique(dirname(target[changed]))) dir.create(directory, recursive = TRUE, showWarnings = FALSE)
    if (!all(file.copy(source[changed], target[changed], overwrite = TRUE, copy.date = preserve_dates))) stop("Could not copy one or more integration assets.")
  }
  sum(changed)
}

station_history_page_payload <- function(path) {
  document <- xml2::read_html(path)
  xml2::xml_text(xml2::xml_find_first(document, "//script[@id='explorer-data']"))
}

station_history_refresh_assets <- function(source_dir, root) {
  copied <- station_history_copy(c("explorer.js", "explorer.css", "station-chart-tools.js", "temperature-normals.js", "temperature-normals.css", "monthly-climatology.js", "monthly-climatology.css"), "scripts/station-explorer-assets", root)
  payload <- station_history_page_payload(file.path(source_dir, "index.html"))
  html <- paste(readLines("scripts/station-explorer-assets/index.html", warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  parts <- strsplit(html, "__EXPLORER_DATA__", fixed = TRUE)[[1L]]
  if (length(parts) != 2L) stop("Current station HTML template changed.")
  html <- paste0(parts[1L], payload, parts[2L])
  html <- sub('<script src="explorer.js"', '<script src="station-history-tabs.js" defer></script><script src="explorer.js"', html, fixed = TRUE)
  html <- sub('</head>', '<link rel="stylesheet" href="station-history-tabs.css"></head>', html, fixed = TRUE)
  writeLines(html, file.path(root, "index.html"), useBytes = TRUE)
  copied <- copied + station_history_copy(c("station-history-tabs.js", "station-history-tabs.css"), "scripts/station-custom-dates-assets", root)
  copied + station_history_copy(c("index.html", "model.js", "worker.js", "app.js", "styles.css"), "scripts/station-custom-dates-assets", file.path(root, "custom-history"))
}

build_station_history_integration <- function(
    source_dir = "data/diagnostics/acis-stations/station-explorer-prototype",
    history_dir = "data/diagnostics/station-custom-dates-pilot", output_dir = station_history_integration_root(),
    mode = c("auto", "full")) {
  mode <- match.arg(mode)
  ready <- file.path(output_dir, "integration-summary.csv")
  if (mode == "full" || !file.exists(ready))
    return(build_station_history_integration_full(source_dir, history_dir, output_dir))
  started <- proc.time()[["elapsed"]]
  root <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)
  allowed <- paste0(tolower(normalizePath("data/diagnostics", winslash = "/", mustWork = TRUE)), "/")
  if (!startsWith(tolower(root), allowed) || tolower(root) %in% tolower(normalizePath(c(source_dir, history_dir), winslash = "/", mustWork = TRUE))) stop("Use a separate integration folder inside data/diagnostics.")
  lock <- filelock::lock(file.path(root, "build.lock"), timeout = 0)
  if (is.null(lock)) stop("Another Station Conditions integration build is running.")
  on.exit(filelock::unlock(lock), add = TRUE)
  summary <- read.csv(ready)
  history <- read.csv(file.path(history_dir, "update-summary.csv"))
  require_full <- function() stop('Source data differ from the verified preview. Run build_station_history_integration(mode = "full") for a full snapshot rebuild.')
  if (!identical(summary$status, "READY") || !identical(history$status, "READY")) require_full()
  inventory <- read.csv(file.path(root, "history-checksums.csv"), stringsAsFactors = FALSE)
  expected <- setNames(inventory$md5, inventory$file)
  if (!identical(unname(tools::md5sum(file.path(history_dir, "catalog.json"))), unname(expected["catalog.json"])) ||
      !identical(unname(tools::md5sum(file.path(root, "custom-history/catalog.json"))), unname(expected["catalog.json"]))) require_full()
  if (!identical(station_history_page_payload(file.path(source_dir, "index.html")), station_history_page_payload(file.path(root, "index.html")))) require_full()
  rows <- read.csv(file.path(source_dir, "station-explorer-data.csv"), stringsAsFactors = FALSE)
  if (length(unique(rows$as_of)) != 1L || unique(rows$as_of) != summary$current_cutoff) require_full()
  details <- paste0("station-details/", unique(rows$uid), ".json")
  anchors <- c("station-explorer-data.csv", details)
  if (!identical(unname(tools::md5sum(file.path(source_dir, anchors))), unname(tools::md5sum(file.path(root, anchors)))) ||
      anyNA(tools::md5sum(file.path(root, anchors)))) require_full()
  # Read the 62 compact build markers, not every annual payload. Full validation
  # still hashes the actual preview payloads before staging/publication.
  for (uid in unique(rows$uid)) {
    marker <- readRDS(file.path(history_dir, "history", uid, "build.rds"))
    if (!identical(unname(expected[marker$files]), unname(marker$md5))) require_full()
  }
  copied <- station_history_refresh_assets(source_dir, root)
  result <- data.frame(status = "READY", mode = "assets-only", copied_files = copied,
    history_files_hashed = 0L, full_validation_rerun = FALSE, seconds = round(proc.time()[["elapsed"]] - started, 3))
  validate_station_history_integration(root, full = FALSE)
  write.csv(result, file.path(root, "asset-refresh-summary.csv"), row.names = FALSE)
  message("Refreshed preview layout only; use the check script for full payload validation before staging.")
  result
}

build_station_history_integration_full <- function(
    source_dir = "data/diagnostics/acis-stations/station-explorer-prototype",
    history_dir = station_custom_pilot_root(), output_dir = station_history_integration_root()) {
  started <- proc.time()[["elapsed"]]
  parent <- normalizePath(dirname(output_dir), winslash = "/", mustWork = TRUE)
  root <- file.path(parent, basename(output_dir))
  allowed <- paste0(tolower(normalizePath("data/diagnostics", winslash = "/", mustWork = TRUE)), "/")
  if (basename(output_dir) %in% c(".", "..") || !startsWith(tolower(root), allowed)) stop("Integration output must remain inside data/diagnostics.")
  source_dir <- normalizePath(source_dir, winslash = "/", mustWork = TRUE)
  history_dir <- normalizePath(history_dir, winslash = "/", mustWork = TRUE)
  if (tolower(root) %in% tolower(c(source_dir, history_dir))) stop("Use a separate integration folder.")
  summary <- read.csv(file.path(history_dir, "update-summary.csv"))
  if (!identical(summary$status, "READY")) stop("Complete the historical pilot build first.")
  rows <- read.csv(file.path(source_dir, "station-explorer-data.csv"), stringsAsFactors = FALSE)
  dates <- unique(rows$as_of)
  if (length(dates) != 1L || is.na(as.Date(dates))) stop("The current snapshot has an invalid cutoff.")
  catalog <- jsonlite::read_json(file.path(history_dir, "catalog.json"), simplifyVector = TRUE)$stations
  if (any(!unique(rows$uid) %in% catalog$uid)) stop("The historical pilot is missing a selected-station UID.")
  for (uid in unique(rows$uid)) {
    detail <- jsonlite::read_json(file.path(source_dir, "station-details", paste0(uid, ".json")))
    if (as.character(detail$as_of) != dates || is.null(detail$monthly_climatology) || is.null(detail$precipitation_records))
      stop("Refresh the standard station snapshot before integrating history: ", uid)
  }
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  lock <- filelock::lock(file.path(root, "build.lock"), timeout = 0)
  if (is.null(lock)) stop("Another Station Conditions integration build is running.")
  on.exit(filelock::unlock(lock), add = TRUE)
  write.csv(data.frame(status = "BUILDING"), file.path(root, "integration-summary.csv"), row.names = FALSE)
  source_files <- list.files(source_dir, recursive = TRUE, full.names = FALSE)
  # The current UI uses seasonal/, not the obsolete cumulative/ pilot. RDS build
  # markers and old diagnostics are not browser dependencies.
  source_files <- station_history_browser_files(source_files)
  message("Preparing the current Station Conditions snapshot (", length(source_files), " files)...")
  source_hashes <- unname(tools::md5sum(file.path(source_dir, source_files)))
  # Copy the existing current/seasonal/climatology payloads verbatim, then use
  # current source templates around the same embedded map/summary JSON.
  copied <- station_history_copy(source_files, source_dir, root, source_hashes)
  source_html <- xml2::read_html(file.path(source_dir, "index.html"))
  payload <- xml2::xml_text(xml2::xml_find_first(source_html, "//script[@id='explorer-data']"))
  if (!nzchar(payload) || !identical(jsonlite::fromJSON(payload)$as_of, dates)) stop("Current HTML and summary dates differ.")
  assets <- c("explorer.js", "explorer.css", "station-chart-tools.js", "temperature-normals.js", "temperature-normals.css", "monthly-climatology.js", "monthly-climatology.css")
  copied <- copied + station_history_copy(assets, "scripts/station-explorer-assets", root)
  html <- paste(readLines("scripts/station-explorer-assets/index.html", warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  parts <- strsplit(html, "__EXPLORER_DATA__", fixed = TRUE)[[1L]]
  if (length(parts) != 2L) stop("Current station HTML template changed.")
  html <- paste0(parts[1L], payload, parts[2L])
  html <- sub('<script src="explorer.js"', '<script src="station-history-tabs.js" defer></script><script src="explorer.js"', html, fixed = TRUE)
  html <- sub('</head>', '<link rel="stylesheet" href="station-history-tabs.css"></head>', html, fixed = TRUE)
  writeLines(html, file.path(root, "index.html"), useBytes = TRUE)
  copied <- copied + station_history_copy(c("station-history-tabs.js", "station-history-tabs.css"), "scripts/station-custom-dates-assets", root)
  custom <- file.path(root, "custom-history"); dir.create(custom, showWarnings = FALSE)
  # The embedded and standalone modes share one implementation and worker.
  copied <- copied + station_history_copy(c("index.html", "model.js", "worker.js", "app.js", "styles.css"), "scripts/station-custom-dates-assets", custom)
  copied <- copied + station_history_copy("catalog.json", history_dir, custom)
  message("Verifying and copying historical payloads for ", length(unique(rows$uid)), " stations...")
  files <- hashes <- character()
  for (uid in unique(rows$uid)) {
    marker <- readRDS(file.path(history_dir, "history", uid, "build.rds"))
    if (!identical(unname(tools::md5sum(file.path(history_dir, marker$files))), marker$md5)) stop("Historical payload checksum mismatch: ", uid)
    files <- c(files, marker$files)
    hashes <- c(hashes, marker$md5)
  }
  copied <- copied + station_history_copy(files, history_dir, custom, hashes)
  if (!identical(unname(tools::md5sum(file.path(source_dir, source_files))), source_hashes)) stop("Current station snapshot changed during integration; rerun.")
  detail_files <- paste0("station-details/", unique(rows$uid), ".json")
  if (!identical(unname(tools::md5sum(file.path(root, detail_files))), unname(tools::md5sum(file.path(source_dir, detail_files))))) stop("Current station detail payloads changed.")
  result <- data.frame(status = "READY", stations = length(unique(rows$uid)), current_cutoff = dates,
    historical_chunks = summary$years, copied_files = copied, seconds = round(proc.time()[["elapsed"]] - started, 3))
  write.csv(result, file.path(root, "integration-summary.csv"), row.names = FALSE)
  write.csv(data.frame(file = c("catalog.json", files), md5 = c(unname(tools::md5sum(file.path(history_dir, "catalog.json"))), unname(hashes))),
    file.path(root, "history-checksums.csv"), row.names = FALSE)
  validate_station_history_integration(root)
  result
}

validate_station_history_integration <- function(root = station_history_integration_root(), full = TRUE) {
  summary <- read.csv(file.path(root, "integration-summary.csv"))
  if (!identical(summary$status, "READY")) stop("Complete the integrated preview build first.")
  inventory <- read.csv(file.path(root, "history-checksums.csv"), stringsAsFactors = FALSE)
  if (full && !identical(unname(tools::md5sum(file.path(root, "custom-history", inventory$file))), inventory$md5)) stop("Integrated historical payload checksum mismatch.")
  html <- paste(readLines(file.path(root, "index.html"), warn = FALSE), collapse = "\n")
  if (!grepl('src="station-history-tabs(\\.swc-[a-f0-9]{16})?\\.js"', html) || !grepl('href="station-history-tabs(\\.swc-[a-f0-9]{16})?\\.css"', html)) stop("Station history tab assets are missing.")
  child <- paste(readLines(file.path(root, "custom-history/app.js"), warn = FALSE), collapse = "\n")
  if (!grepl("requestedUid", child, fixed = TRUE) || !grepl("swc-station-history-selection", child, fixed = TRUE)) stop("Selected-station history linkage is missing.")
  child_html <- paste(readLines(file.path(root, "custom-history/index.html"), warn = FALSE), collapse = "\n")
  if (!all(vapply(c('id="precip-selection"', 'id="temp-selection"', 'id="precip-next"', 'id="temp-next"'),
    grepl, logical(1), x = child_html, fixed = TRUE)) || !grepl("function selectInterval", child, fixed = TRUE))
    stop("Linked historical chart tables are missing; rebuild the integrated preview.")
  data.frame(status = "PASS", scope = if (full) "full-payloads" else "layout-only", stations = summary$stations, historical_chunks = summary$historical_chunks)
}
