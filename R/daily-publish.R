# One local, date-aware PRISM + SNODAS + station update followed by site sync.

# ntfy is opt-in. Never store a topic or access token in repository files.
swc_ntfy_notify <- function(event, message, perform = httr2::req_perform) {
  topic <- Sys.getenv("SWC_NTFY_TOPIC", unset = "")
  if (!nzchar(topic)) return(invisible(FALSE))
  if (!grepl("^[A-Za-z0-9_-]{1,64}$", topic)) {
    stop("SWC_NTFY_TOPIC must be 1-64 letters, numbers, dashes, or underscores.",
         call. = FALSE)
  }
  server <- sub("/+$", "", Sys.getenv("SWC_NTFY_SERVER",
                                        unset = "https://ntfy.sh"))
  if (!grepl("^https://[^/?#@]+(/[^?#]*)?$", server)) {
    stop("SWC_NTFY_SERVER must be an HTTPS base URL without credentials or a query.",
         call. = FALSE)
  }
  event <- match.arg(event, c("started", "progress", "warning", "success",
                              "error", "test"))
  priority <- switch(event, started = "2", progress = "2", warning = "4",
                     success = "3", error = "5", test = "3")
  title <- switch(event, started = "Climate Watch: started",
                  progress = "Climate Watch: progress",
                  warning = "Climate Watch: warning",
                  success = "Climate Watch: complete",
                  error = "Climate Watch: failed",
                  test = "Climate Watch: test")
  request <- httr2::request(paste0(server, "/", topic))
  request <- httr2::req_method(request, "POST")
  request <- httr2::req_headers(request, "X-Title" = title,
                                "X-Priority" = priority)
  token <- Sys.getenv("SWC_NTFY_TOKEN", unset = "")
  if (nzchar(token)) {
    request <- httr2::req_headers(request,
                                  Authorization = paste("Bearer", token))
  }
  request <- httr2::req_body_raw(request, charToRaw(as.character(message)),
                                 type = "text/plain; charset=utf-8")
  request <- httr2::req_timeout(request, seconds = 5)
  invisible(perform(request))
}

swc_ntfy_send_safe <- function(event, message, notify = swc_ntfy_notify) {
  tryCatch({
    notify(event, message)
    invisible(TRUE)
  }, error = function(error) {
    # HTTP errors may contain server details; never print a token or topic.
    warning("ntfy notification could not be delivered; continuing. Check the ntfy settings and connection.",
            call. = FALSE)
    invisible(FALSE)
  })
}
# Source scripts/load-daily-publish.R first. No work runs when this file is sourced.

swc_daily_publish_live_destination <- function() {
  "s3://cales-climate-reports/climate/watch/"
}

swc_daily_publish_deploy_script <- function() {
  path <- file.path("scripts", "deploy-site-s3.R")
  if (!file.exists(path)) {
    path <- file.path("..", "..", "scripts", "deploy-site-s3.R")
  }
  if (!file.exists(path) && exists("project_root", inherits = TRUE)) {
    path <- file.path(get("project_root", inherits = TRUE),
                      "scripts", "deploy-site-s3.R")
  }
  if (!file.exists(path)) stop("Cannot find scripts/deploy-site-s3.R.", call. = FALSE)
  path
}

swc_daily_publish_destination <- function(
    destination = Sys.getenv("SWC_S3_DESTINATION", unset = "")) {
  if (length(destination) == 1L && !is.na(destination) &&
      !nzchar(destination)) destination <- swc_daily_publish_live_destination()
  source(swc_daily_publish_deploy_script(), local = TRUE)
  swc_deploy_destination(destination)
}

swc_daily_publish_marker_path <- function(destination) {
  destination <- swc_daily_publish_destination(destination)
  directory <- file.path("data", "diagnostics", "daily-publish")
  if (identical(destination, swc_daily_publish_live_destination())) {
    return(file.path(directory, "last-success.csv"))
  }
  suffix <- substr(digest::digest(destination, algo = "sha256"), 1L, 12L)
  file.path(directory, paste0("last-success-", suffix, ".csv"))
}

swc_publish_elapsed <- function(seconds) {
  seconds <- max(0, round(as.numeric(seconds)))
  if (seconds >= 3600L) {
    return(sprintf("%dh %02dm %02ds", seconds %/% 3600L,
                   (seconds %% 3600L) %/% 60L, seconds %% 60L))
  }
  if (seconds >= 60L) return(sprintf("%dm %02ds", seconds %/% 60L,
                                     seconds %% 60L))
  sprintf("%ds", seconds)
}

swc_daily_publish_summary_lines <- function(record, prism = NULL, snow = NULL,
                                            stations = NULL, validation = NULL,
                                            failed_stage = NULL,
                                            destination = swc_daily_publish_live_destination()) {
  status <- switch(record$status[[1L]],
                   PUBLISHED = "Published", PREVIEW = "Preview complete",
                   SKIPPED_UNCHANGED = "Update complete; upload skipped",
                   FAILED = "Failed", record$status[[1L]])
  first <- paste0("Daily site workflow: ", status, " in ",
                  swc_publish_elapsed(record$elapsed_seconds[[1L]]), ".")
  if (!is.null(failed_stage)) first <- paste0(first, " Stage: ", failed_stage, ".")
  lines <- first
  if (is.list(prism) && is.data.frame(prism$summary) && nrow(prism$summary)) {
    row <- prism$summary[1L, , drop = FALSE]
    changed <- if (!"data_changed" %in% names(row)) "unknown" else
      if (isTRUE(row$data_changed[[1L]])) "changed" else "unchanged"
    if (all(c("downloaded", "downloaded_changed", "processed",
              "maps_rebuilt") %in% names(row))) {
      lines <- c(lines, sprintf(
        "PRISM: %d checked, %d changed, %d processed; maps %s.",
        row$downloaded, row$downloaded_changed, row$processed,
        if (isTRUE(row$maps_rebuilt[[1L]])) "rebuilt" else "skipped"))
    } else lines <- c(lines, paste0("PRISM: data ", changed, "."))
  }
  if (is.list(snow) && is.list(snow$maps) && length(snow$maps$status) == 1L) {
    snow_line <- paste0("Snow: ", gsub("_", " ", tolower(snow$maps$status)),
                        if (!is.null(snow$maps$date) &&
                            length(snow$maps$date) == 1L &&
                            !is.na(snow$maps$date))
                          paste0(" (", as.character(snow$maps$date), ")")
                        else "")
    if (is.list(snow$data) && is.data.frame(snow$data$summary) &&
        nrow(snow$data$summary) &&
        "processed_this_run" %in% names(snow$data$summary)) {
      snow_line <- paste0(snow_line, "; ",
                          snow$data$summary$processed_this_run[[1L]],
                          " daily grids processed")
    }
    lines <- c(lines, paste0(snow_line, "."))
  }
  if (is.list(stations) && length(stations$status) == 1L) {
    station_line <- paste0("Stations: ",
                           gsub("_", " ", tolower(stations$status)))
    if (length(stations$stations) == 1L && is.numeric(stations$stations) &&
        is.finite(stations$stations)) {
      station_line <- paste0(station_line, "; ", stations$stations,
                             " records",
                             if (length(stations$mapped) == 1L &&
                                 is.numeric(stations$mapped) &&
                                 is.finite(stations$mapped))
                               paste0(" (", stations$mapped, " mapped)") else "")
    }
    if (length(stations$pending) == 1L && is.numeric(stations$pending) &&
        is.finite(stations$pending) &&
        stations$pending > 0L)
      station_line <- paste0(station_line, "; ", stations$pending, " delayed")
    lines <- c(lines, paste0(station_line, "."))
  }
  if (is.list(validation) &&
      all(c("current_passed", "current_total", "archive_passed",
            "archive_total") %in% names(validation))) {
    lines <- c(lines, sprintf(
      "Validated maps: %d/%d current, %d/%d historic passed.",
      validation$current_passed, validation$current_total,
      validation$archive_passed, validation$archive_total))
  }
  if (!identical(destination, swc_daily_publish_live_destination())) {
    lines <- c(lines, paste0("S3 destination: ", destination))
  } else if (identical(record$status[[1L]], "PUBLISHED")) {
    lines <- c(lines, "https://cales.arizona.edu/climate/watch/")
  }
  lines
}

swc_daily_publish_site_fingerprint <- function(site_dir = "site") {
  if (!file.exists(file.path(site_dir, "_quarto.yml"))) {
    stop("The Quarto site source directory is missing.", call. = FALSE)
  }
  root <- normalizePath(site_dir, winslash = "/", mustWork = TRUE)
  files <- list.files(site_dir, recursive = TRUE, full.names = TRUE,
                      all.files = TRUE, include.dirs = FALSE, no.. = TRUE)
  files <- normalizePath(files, winslash = "/", mustWork = TRUE)
  relative <- substring(files, nchar(root) + 2L)
  keep <- !grepl("^(_site|\\.quarto|_freeze)(/|$)", relative)
  files <- files[keep]
  relative <- relative[keep]
  if (!length(files)) stop("No Quarto site source files found.", call. = FALSE)
  order <- order(relative)
  hashes <- unname(tools::md5sum(files[order]))
  if (anyNA(hashes)) stop("Could not hash all site source files.", call. = FALSE)
  digest::digest(paste(relative[order], hashes, sep = "=", collapse = "\n"),
                 algo = "sha256")
}

swc_daily_publish_read_marker <- function(path) {
  if (!file.exists(path)) return(NULL)
  row <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE),
                  error = function(error) NULL)
  if (is.null(row) || nrow(row) != 1L ||
      !"site_fingerprint" %in% names(row) ||
      is.na(row$site_fingerprint[[1L]]) ||
      !nzchar(row$site_fingerprint[[1L]])) return(NULL)
  row$site_fingerprint[[1L]]
}

swc_daily_publish_write_marker <- function(path, fingerprint) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  row <- data.frame(
    site_fingerprint = fingerprint,
    synced_utc = format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC", tz = "UTC"))
  temporary <- tempfile("daily-publish-", tmpdir = dirname(path),
                        fileext = ".csv")
  on.exit(unlink(temporary), add = TRUE)
  utils::write.csv(row, temporary, row.names = FALSE)
  if (!file.copy(temporary, path, overwrite = TRUE)) {
    stop("Could not save the successful site-sync marker.", call. = FALSE)
  }
  invisible(path)
}

swc_daily_publish_log <- function(row, path) {
  if (is.null(path)) return(invisible(NULL))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.table(row, path, sep = ",", row.names = FALSE,
                     col.names = !file.exists(path) || file.info(path)$size == 0,
                     append = file.exists(path) && file.info(path)$size > 0,
                     qmethod = "double")
  invisible(path)
}

swc_daily_publish_update_prism <- function() {
  variables <- c("SWC_UPDATE_PRISM", "SWC_FORCE_MAPS")
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
  Sys.setenv(SWC_UPDATE_PRISM = "true", SWC_FORCE_MAPS = "false")
  environment <- new.env(parent = .GlobalEnv)
  sys.source(file.path("R", "update-data.R"), envir = environment)
  result <- environment$swc_update_result
  if (!is.list(result) || !is.data.frame(result$summary) ||
      nrow(result$summary) != 1L) {
    stop("PRISM update did not return a valid summary.", call. = FALSE)
  }
  result
}

swc_daily_publish_update_snow <- function(today = Sys.Date()) {
  source(file.path("scripts", "load-snodas-current-site.R"))
  # Reset a prior water-year page before a network request can fail.
  update_snodas_current_site(data.frame(
    date = as.Date(character()), processed = logical()), today = today)
  data <- run_snodas_daily_update(today = today)
  maps <- update_snodas_current_site(data$plan, today = today)
  list(data = data, maps = maps)
}

swc_daily_publish_update_stations <- function(today = Sys.Date()) {
  context <- new.env(parent = .GlobalEnv)
  for (path in c("R/config.R", "R/acis-station-inventory.R",
                 "R/acis-station-daily-pilot.R", "R/map-southwest.R",
                 "R/acis-station-current-prototype.R",
                 "R/acis-station-explorer-prototype.R",
                 "R/acis-station-explorer-update-pilot.R",
                 "R/acis-station-publication-audit.R",
                 "R/acis-station-site.R"))
    sys.source(path, envir = context)
  context$run_swc_station_beta_update(today = today)
}

swc_daily_publish_validate_stations <- function(output_dir) {
  page <- file.path(output_dir, "pages", "station-conditions.html")
  station_dir <- file.path(output_dir, "stations")
  needed <- c(page, file.path(station_dir, c(
    "index.html", "explorer.js", "explorer.css", "leaflet.js",
    "leaflet.css", "station-explorer-data.csv")))
  if (!all(file.exists(needed)) || any(file.info(needed)$size <= 0))
    stop("Rendered station beta page or its resources are missing; S3 sync stopped.",
         call. = FALSE)
  html <- paste(readLines(page, warn = FALSE), collapse = "\n")
  if (!grepl("../stations/index.html?embedded=1", html, fixed = TRUE))
    stop("Rendered station beta page does not link its explorer; S3 sync stopped.",
         call. = FALSE)
  rows <- utils::read.csv(file.path(station_dir, "station-explorer-data.csv"),
                          stringsAsFactors = FALSE)
  if (!nrow(rows) || !all(c("uid", "as_of") %in% names(rows)) ||
      length(unique(rows$as_of)) != 1L ||
      is.na(as.Date(rows$as_of[[1L]])))
    stop("Rendered station data are invalid; S3 sync stopped.", call. = FALSE)
  details <- file.path(station_dir, "station-details",
                       paste0(unique(rows$uid), ".json"))
  if (!all(file.exists(details)) || any(file.info(details)$size <= 0))
    stop("Rendered station details are missing; S3 sync stopped.",
         call. = FALSE)
  invisible(TRUE)
}

swc_daily_publish_validate_snow <- function(
    output_dir,
    page_source = file.path("site", "pages", "current-snow.qmd")) {
  rendered <- file.path(output_dir, "pages", "current-snow.html")
  if (!file.exists(page_source) || !file.exists(rendered)) {
    stop("Rendered Current Snow page is missing; S3 sync stopped.",
         call. = FALSE)
  }
  source_text <- paste(readLines(page_source, warn = FALSE), collapse = "\n")
  html <- paste(readLines(rendered, warn = FALSE), collapse = "\n")
  filenames <- c("swe-observed.png", "swe-departure.png")
  references <- paste0("../maps/generated/snodas/current/", filenames)
  if (all(vapply(filenames, grepl, logical(1), x = source_text,
                 fixed = TRUE))) {
    paths <- file.path(output_dir, "maps", "generated", "snodas",
                       "current", filenames)
    if (!all(file.exists(paths)) || any(file.info(paths)$size <= 0) ||
        !all(vapply(paste0("](", references), grepl, logical(1),
                    x = source_text, fixed = TRUE)) ||
        !all(vapply(paste0('src="', references, '"'), grepl, logical(1),
                    x = html, fixed = TRUE)) ||
        !all(vapply(paste0('href="', references, '"'), grepl, logical(1),
                    x = html, fixed = TRUE))) {
      stop("Rendered Current Snow images are missing or unlinked; S3 sync stopped.",
           call. = FALSE)
    }
    date_line <- grep("Latest map date:",
                      readLines(page_source, warn = FALSE),
                      value = TRUE, fixed = TRUE)
    if (length(date_line) != 1L) {
      stop("Current Snow map date is missing; S3 sync stopped.",
           call. = FALSE)
    }
    date_label <- sub("^.*Latest map date: ([^*]+)\\*\\*.*$", "\\1",
                      date_line)
    if (!grepl(date_label, html, fixed = TRUE)) {
      stop("Rendered Current Snow date is stale; S3 sync stopped.",
           call. = FALSE)
    }
  } else if (!grepl("waiting for a listed", source_text, fixed = TRUE) ||
             !grepl("waiting for a listed", html, fixed = TRUE)) {
    stop("Current Snow page is neither a verified map nor a waiting page; S3 sync stopped.",
         call. = FALSE)
  }
  invisible(TRUE)
}

swc_daily_publish_sync <- function(
    dry_run = FALSE, destination = swc_daily_publish_destination()) {
  source(swc_daily_publish_deploy_script(), local = TRUE)
  deploy_swc_site(
    destination = swc_daily_publish_destination(destination),
    region = "us-west-2", dry_run = dry_run, delete = FALSE,
    render = TRUE, extra_validation = function(output_dir) {
      swc_daily_publish_validate_snow(output_dir)
      swc_daily_publish_validate_stations(output_dir)
    })
}

run_swc_daily_publish <- function(
    today = Sys.Date(), dry_run = TRUE, force_publish = FALSE,
    destination = swc_daily_publish_destination(),
    marker_path = swc_daily_publish_marker_path(destination),
    log_path = file.path("data", "diagnostics", "daily-publish",
                         "runs.csv"),
    prism_update = swc_daily_publish_update_prism,
    snow_update = swc_daily_publish_update_snow,
    station_update = swc_daily_publish_update_stations,
    site_fingerprint = swc_daily_publish_site_fingerprint,
    publish = NULL,
    notify = swc_ntfy_notify) {
  if (!is.logical(dry_run) || length(dry_run) != 1L || is.na(dry_run) ||
      !is.logical(force_publish) || length(force_publish) != 1L ||
      is.na(force_publish)) {
    stop("`dry_run` and `force_publish` must be TRUE or FALSE.", call. = FALSE)
  }
  destination <- swc_daily_publish_destination(destination)
  if (is.null(publish)) {
    publish <- function(dry_run) swc_daily_publish_sync(dry_run, destination)
  }
  today <- as.Date(today)
  if (length(today) != 1L || is.na(today)) {
    stop("Expected one run date.", call. = FALSE)
  }
  started <- Sys.time()
  record <- data.frame(
    run_id = paste0(format(started, "%Y%m%dT%H%M%SZ", tz = "UTC"),
                    "-", Sys.getpid()),
    run_date = as.character(today), status = "FAILED",
    prism_data_changed = NA, snow_status = NA_character_,
    snow_date = NA_character_, snow_error = NA_character_,
    site_changed = NA, published = FALSE, error = NA_character_,
    elapsed_seconds = NA_real_, stringsAsFactors = FALSE)
  on.exit({
    record$elapsed_seconds <- round(as.numeric(difftime(
      Sys.time(), started, units = "secs")), 3)
    swc_daily_publish_log(record, log_path)
  }, add = TRUE)
  send <- function(event, message) {
    if (!dry_run) swc_ntfy_send_safe(event, message, notify = notify)
    invisible(NULL)
  }
  prism <- snow <- stations <- publication <- NULL
  finish <- function(event, failed_stage = NULL) {
    record$elapsed_seconds <<- round(as.numeric(difftime(
      Sys.time(), started, units = "secs")), 3)
    lines <- swc_daily_publish_summary_lines(
      record, prism, snow, stations,
      if (is.list(publication)) publication$validation else NULL,
      failed_stage = failed_stage, destination = destination)
    message(paste(lines, collapse = "\n"))
    if (!is.null(event)) send(event, paste(lines, collapse = "\n"))
    lines
  }
  stage <- "PRISM update"
  tryCatch({
    send("started", paste0("Daily update started for ", today, ".",
                            if (!identical(destination,
                                           swc_daily_publish_live_destination()))
                              paste0(" Destination: ", destination) else ""))
    prism <- prism_update()
    if (!is.list(prism) || !is.data.frame(prism$summary) ||
        nrow(prism$summary) != 1L ||
        !"data_changed" %in% names(prism$summary)) {
      stop("PRISM update returned an invalid summary.", call. = FALSE)
    }
    record$prism_data_changed <- isTRUE(prism$summary$data_changed[[1L]])
    send("progress", paste0("PRISM update complete: ",
                            if (record$prism_data_changed) "new or revised data"
                            else "no data change", "."))
    stage <- "SNODAS update"
    snow <- tryCatch(snow_update(today), error = function(error) {
      list(maps = list(status = "ERROR"), error = conditionMessage(error))
    })
    if (!is.list(snow) || !is.list(snow$maps) ||
        length(snow$maps$status) != 1L) {
      stop("SNODAS update returned an invalid status.", call. = FALSE)
    }
    record$snow_status <- as.character(snow$maps$status)
    if (!is.null(snow$maps$date) && !is.na(snow$maps$date)) {
      record$snow_date <- as.character(snow$maps$date)
    }
    if (!is.null(snow$error)) record$snow_error <- snow$error
    if (identical(record$snow_status, "ERROR")) {
      warning("SNODAS update failed; retaining the last verified snow page: ",
              record$snow_error, call. = FALSE)
      send("warning", "SNODAS update failed. The last verified snow page will be retained.")
    } else if (identical(record$snow_status, "HELD")) {
      message("SNODAS quality gate held the new map; retaining the last verified snow page.")
      send("warning", "SNODAS quality gate held the new map. The last verified snow page will be retained.")
    }
    stage <- "station update"
    stations <- tryCatch(station_update(today), error = function(error)
      list(status = "ERROR", error = conditionMessage(error)))
    if (!is.list(stations) || length(stations$status) != 1L ||
        is.na(stations$status))
      stop("Station update returned an invalid status.", call. = FALSE)
    if (identical(stations$status, "ERROR")) {
      warning("Station update failed; retaining the last verified beta page: ",
              stations$error, call. = FALSE)
      send("warning", "Station update failed. The last verified station page will be retained.")
    } else if (identical(stations$status, "UPDATED_WITH_STALE_STATIONS")) {
      send("warning", paste0("Station page updated with ", stations$pending,
                             " delayed station caches; see beta-update-runs.csv."))
    }
    send("progress", paste0(
      "Data checks complete. PRISM: ",
      if (record$prism_data_changed) "changed" else "unchanged",
      "; SNODAS: ", record$snow_status,
      "; stations: ", stations$status, "."))
    stage <- "site publication"
    current <- site_fingerprint()
    previous <- swc_daily_publish_read_marker(marker_path)
    changed <- isTRUE(force_publish) || is.null(previous) ||
      !identical(current, previous)
    record$site_changed <- changed
    if (!changed) {
      record$status <- "SKIPPED_UNCHANGED"
      message("Site source is unchanged since the last successful sync; upload skipped.")
      lines <- finish("success")
      return(invisible(list(status = record$status, prism = prism,
                            snow = snow, stations = stations,
                            destination = destination,
                            published = FALSE,
                            elapsed_seconds = record$elapsed_seconds,
                            summary_lines = lines)))
    }
    send("progress", "Rendering and validating the site, then syncing it to S3.")
    publication <- publish(dry_run = dry_run)
    if (dry_run) {
      record$status <- "PREVIEW"
    } else {
      # Render may refresh generated source files, so store its final signature.
      swc_daily_publish_write_marker(marker_path, site_fingerprint())
      record$status <- "PUBLISHED"
      record$published <- TRUE
    }
    lines <- finish(if (dry_run) NULL else "success")
    invisible(list(status = record$status, prism = prism, snow = snow,
                   stations = stations,
                   destination = destination,
                   published = record$published,
                   validation = if (is.list(publication)) publication$validation
                   else NULL,
                   elapsed_seconds = record$elapsed_seconds,
                   summary_lines = lines))
  }, error = function(error) {
    record$error <- conditionMessage(error)
    finish("error", failed_stage = stage)
    stop(error)
  })
}
