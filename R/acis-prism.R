# Download planning and transport for RCC-ACIS PRISM grids.

validate_prism_variables <- function(variables, config = swc_prism) {
  variables <- unique(as.character(variables))
  invalid <- setdiff(variables, config$variables)
  if (length(invalid) > 0L) {
    stop(
      "Unsupported PRISM variable(s): ", paste(invalid, collapse = ", "),
      ". Supported variables are: ", paste(config$variables, collapse = ", "),
      call. = FALSE
    )
  }
  variables
}

validate_prism_analysis_variables <- function(variables, config = swc_prism) {
  variables <- unique(as.character(variables))
  supported <- unique(c(config$variables, config$derived_variables))
  invalid <- setdiff(variables, supported)
  if (length(invalid) > 0L) {
    stop(
      "Unsupported PRISM analysis variable(s): ", paste(invalid, collapse = ", "),
      ". Supported variables are: ", paste(supported, collapse = ", "),
      call. = FALSE
    )
  }
  variables
}

validate_prism_temperature_variables <- function(variables, config = swc_prism) {
  variables <- validate_prism_analysis_variables(variables, config)
  invalid <- setdiff(variables, config$temperature_variables)
  if (length(invalid) > 0L) {
    stop(
      "Unsupported PRISM temperature variable(s): ", paste(invalid, collapse = ", "),
      ". Supported temperature variables are: ",
      paste(config$temperature_variables, collapse = ", "),
      call. = FALSE
    )
  }
  variables
}

normalize_prism_bbox <- function(bbox) {
  bbox <- as.numeric(bbox)
  if (length(bbox) != 4L || any(!is.finite(bbox))) {
    stop("`bbox` must contain four finite values: west, south, east, north.", call. = FALSE)
  }
  if (bbox[1L] >= bbox[3L] || bbox[2L] >= bbox[4L]) {
    stop("`bbox` must satisfy west < east and south < north.", call. = FALSE)
  }
  unname(bbox)
}

split_prism_date_range <- function(start, end, chunk = "month", chunk_days = NULL) {
  start <- as.Date(start)
  end <- as.Date(end)

  if (is.na(start) || is.na(end) || start > end) {
    stop("`start` and `end` must define a valid inclusive date range.", call. = FALSE)
  }

  if (!is.null(chunk_days)) {
    chunk_days <- as.integer(chunk_days)
    if (is.na(chunk_days) || chunk_days < 1L) {
      stop("`chunk_days` must be a positive integer.", call. = FALSE)
    }
    starts <- seq(start, end, by = chunk_days)
    return(data.frame(
      start_date = starts,
      end_date = pmin(starts + chunk_days - 1L, end),
      stringsAsFactors = FALSE
    ))
  }

  if (!identical(chunk, "month")) {
    stop("`chunk` must be 'month' when `chunk_days` is not supplied.", call. = FALSE)
  }
  first_month <- as.Date(format(start, "%Y-%m-01"))
  last_month <- as.Date(format(end, "%Y-%m-01"))
  starts <- seq(first_month, last_month, by = "month")
  month_ends <- seq(first_month, by = "month", length.out = length(starts) + 1L)[-1L] - 1L
  starts[1L] <- start
  month_ends[length(month_ends)] <- min(month_ends[length(month_ends)], end)
  data.frame(
    start_date = starts,
    end_date = month_ends,
    stringsAsFactors = FALSE
  )
}

prism_manifest_path <- function(raw_dir = swc_paths$raw) {
  file.path(raw_dir, "prism", "manifest.csv")
}

read_prism_manifest <- function(path = prism_manifest_path()) {
  if (!file.exists(path)) {
    return(data.frame())
  }

  manifest <- utils::read.csv(path, stringsAsFactors = FALSE)
  for (column in intersect(c("start_date", "end_date"), names(manifest))) {
    manifest[[column]] <- as.Date(manifest[[column]])
  }
  manifest
}

plan_prism_download <- function(
    mode = c("bootstrap", "catchup", "update"),
    variables = swc_prism$variables,
    start = NULL,
    end = NULL,
    bbox = swc_region$bbox,
    aoi_id = swc_prism$aoi_id,
    raw_dir = swc_paths$raw,
    chunk = swc_prism$bootstrap_chunk,
    chunk_days = NULL,
    today = Sys.Date(),
    revision_ages = swc_prism$revision_ages,
    manifest = read_prism_manifest(prism_manifest_path(raw_dir))) {
  mode <- match.arg(mode)
  variables <- validate_prism_variables(variables)
  bbox <- normalize_prism_bbox(bbox)
  if (!(is.character(aoi_id) && length(aoi_id) == 1L &&
        grepl("^[a-z0-9][a-z0-9-]*$", aoi_id))) {
    stop("`aoi_id` must contain only lowercase letters, numbers, and hyphens.", call. = FALSE)
  }
  today <- as.Date(today)

  if (mode == "bootstrap") {
    start <- as.Date(start %||% swc_prism$archive_start)
    end <- as.Date(end %||% swc_prism$archive_end)
    chunks <- split_prism_date_range(start, end, chunk = chunk, chunk_days = chunk_days)
    chunks$refresh <- FALSE
    subdirectory <- "archive"
  } else if (mode == "catchup") {
    # Catch up complete months with range requests. The current partial month is
    # left to update mode so its path does not change every day.
    current_month_start <- as.Date(format(today, "%Y-%m-01"))
    start <- as.Date(start %||% (swc_prism$archive_end + 1L))
    end <- as.Date(end %||% (current_month_start - 1L))
    if (start > end) {
      chunks <- data.frame(
        start_date = as.Date(character()),
        end_date = as.Date(character()),
        refresh = logical(),
        stringsAsFactors = FALSE
      )
    } else {
      chunks <- split_prism_date_range(start, end, chunk = "month")
      chunks$refresh <- FALSE
    }
    subdirectory <- "catchup"
  } else {
    target_dates <- sort(unique(today - as.integer(revision_ages)))
    target_dates <- target_dates[target_dates >= as.Date("1981-01-01") & target_dates < today]

    manifest_fields <- c("product", "aoi_id", "end_date")
    if (nrow(manifest) > 0L && all(manifest_fields %in% names(manifest))) {
      matching_aoi <- manifest$product == "daily" & manifest$aoi_id == aoi_id
      daily_dates <- manifest$end_date[matching_aoi]
      daily_dates <- daily_dates[!is.na(daily_dates)]
      if (length(daily_dates) > 0L) {
        newest_expected <- today - 2L
        if (max(daily_dates) < newest_expected) {
          missing_tail <- seq(max(daily_dates) + 1L, newest_expected, by = "day")
          target_dates <- sort(unique(c(target_dates, missing_tail)))
        }
      }
    }

    chunks <- data.frame(
      start_date = target_dates,
      end_date = target_dates,
      refresh = TRUE,
      stringsAsFactors = FALSE
    )
    subdirectory <- "recent"
  }

  if (nrow(chunks) == 0L) {
    return(data.frame())
  }

  plan <- merge(
    chunks,
    data.frame(variable = variables, stringsAsFactors = FALSE),
    by = NULL
  )
  plan <- plan[order(plan$start_date, plan$variable), , drop = FALSE]
  plan$product <- "daily"
  plan$aoi_id <- aoi_id
  plan$endpoint <- swc_prism$daily_endpoint
  plan$grid <- swc_prism$daily_grid
  plan$native_units <- unname(swc_prism$native_units[plan$variable])
  plan$bbox <- paste(bbox, collapse = ",")

  date_label <- ifelse(
    plan$start_date == plan$end_date,
    format(plan$start_date, "%Y-%m-%d"),
    paste(format(plan$start_date, "%Y-%m-%d"), format(plan$end_date, "%Y-%m-%d"), sep = "_")
  )
  plan$path <- file.path(
    raw_dir, "prism", aoi_id, "daily", subdirectory, plan$variable,
    paste0(date_label, ".tif")
  )
  rownames(plan) <- NULL
  plan
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

prism_daily_payload <- function(plan_row) {
  bbox <- as.numeric(strsplit(plan_row$bbox, ",", fixed = TRUE)[[1L]])
  list(
    grid = plan_row$grid,
    bbox = bbox,
    sdate = format(as.Date(plan_row$start_date), "%Y-%m-%d"),
    edate = format(as.Date(plan_row$end_date), "%Y-%m-%d"),
    elems = list(list(name = plan_row$variable)),
    output = "geotiff"
  )
}

prism_geotiff_dates <- function(path) {
  description <- terra::describe(path)
  date_lines <- grep("^[[:space:]]*Date=", description, value = TRUE)
  as.Date(sub("^[[:space:]]*Date=", "", date_lines))
}

validate_prism_geotiff <- function(path, plan_row) {
  if (!file.exists(path) || file.info(path)$size <= 0L) {
    stop("ACIS did not produce a non-empty GeoTIFF.", call. = FALSE)
  }

  raster <- terra::rast(path)
  expected_dates <- seq(as.Date(plan_row$start_date), as.Date(plan_row$end_date), by = "day")
  band_dates <- prism_geotiff_dates(path)
  resolution <- terra::res(raster)

  if (terra::nlyr(raster) != length(expected_dates)) {
    stop("GeoTIFF band count does not match the requested date range.", call. = FALSE)
  }
  dates_match <- length(band_dates) == length(expected_dates) &&
    all(!is.na(band_dates)) && all(band_dates == expected_dates)
  if (!dates_match) {
    stop("GeoTIFF Date metadata does not match the requested date range.", call. = FALSE)
  }
  if (!terra::is.lonlat(raster)) {
    stop("GeoTIFF is not in a longitude/latitude coordinate system.", call. = FALSE)
  }
  if (any(abs(resolution - (1 / 24)) > 1e-5)) {
    stop("GeoTIFF resolution is not the expected PRISM 4-km grid spacing.", call. = FALSE)
  }

  invisible(raster)
}

replace_file_atomically <- function(source, destination) {
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  backup <- paste0(destination, ".previous")

  if (file.exists(backup)) {
    unlink(backup)
  }
  if (file.exists(destination) && !file.rename(destination, backup)) {
    stop("Could not stage the existing file for replacement: ", destination, call. = FALSE)
  }

  installed <- file.rename(source, destination)
  if (!installed) {
    if (file.exists(backup)) {
      file.rename(backup, destination)
    }
    stop("Could not move the completed download into place: ", destination, call. = FALSE)
  }
  if (file.exists(backup)) {
    unlink(backup)
  }
  invisible(destination)
}

write_prism_manifest <- function(records, path = prism_manifest_path()) {
  existing <- read_prism_manifest(path)
  if (nrow(existing) == 0L) {
    combined <- records
  } else {
    columns <- union(names(existing), names(records))
    for (column in setdiff(columns, names(existing))) existing[[column]] <- NA
    for (column in setdiff(columns, names(records))) records[[column]] <- NA
    combined <- rbind(existing[columns], records[columns])
  }
  combined <- combined[!duplicated(combined$path, fromLast = TRUE), , drop = FALSE]
  combined <- combined[order(combined$start_date, combined$variable), , drop = FALSE]

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile("manifest-", tmpdir = dirname(path), fileext = ".csv")
  on.exit(unlink(temporary), add = TRUE)
  utils::write.csv(combined, temporary, row.names = FALSE, na = "")
  replace_file_atomically(temporary, path)
  invisible(combined)
}

prepare_prism_request_queue <- function(plan, force = FALSE, max_requests = 100L) {
  if (!is.data.frame(plan)) {
    stop("`plan` must be a data frame.", call. = FALSE)
  }
  valid_max <- is.numeric(max_requests) && length(max_requests) == 1L &&
    !is.na(max_requests) && max_requests >= 1 &&
    (is.infinite(max_requests) || max_requests == floor(max_requests))
  if (!valid_max) {
    stop("`max_requests` must be a positive whole number or `Inf`.", call. = FALSE)
  }

  if (nrow(plan) == 0L) {
    return(list(
      queue = plan,
      summary = c(total = 0L, already_complete = 0L, eligible = 0L, will_run = 0L, deferred = 0L)
    ))
  }

  required <- c("path", "refresh")
  missing <- setdiff(required, names(plan))
  if (length(missing) > 0L) {
    stop("Download plan is missing column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }

  existing <- file.exists(plan$path)
  pending <- !existing | isTRUE(force) | as.logical(plan$refresh)
  eligible <- plan[pending, , drop = FALSE]
  run_count <- min(nrow(eligible), max_requests)
  queue <- eligible[seq_len(run_count), , drop = FALSE]

  list(
    queue = queue,
    summary = c(
      total = nrow(plan),
      already_complete = sum(!pending),
      eligible = nrow(eligible),
      will_run = nrow(queue),
      deferred = nrow(eligible) - nrow(queue)
    )
  )
}

format_prism_plan_summary <- function(summary) {
  paste0(
    "PRISM request plan: ", summary[["total"]], " total; ",
    summary[["already_complete"]], " already complete; ",
    summary[["will_run"]], " scheduled this run; ",
    summary[["deferred"]], " deferred by the request cap."
  )
}

preview_prism_download <- function(plan, force = FALSE, max_requests = swc_prism$max_requests_per_run) {
  prepared <- prepare_prism_request_queue(plan, force = force, max_requests = max_requests)
  message(format_prism_plan_summary(prepared$summary))
  invisible(prepared$summary)
}

download_prism_plan <- function(
    plan,
    manifest_path = prism_manifest_path(),
    force = FALSE,
    timeout_seconds = swc_prism$request_timeout_seconds,
    max_requests = swc_prism$max_requests_per_run,
    delay_seconds = swc_prism$request_delay_seconds,
    jitter_seconds = swc_prism$request_jitter_seconds,
    quiet = FALSE) {
  if (nrow(plan) == 0L) {
    prepared <- prepare_prism_request_queue(plan, force = force, max_requests = max_requests)
    if (!quiet) message(format_prism_plan_summary(prepared$summary))
    return(invisible(data.frame()))
  }

  required <- c(
    "product", "aoi_id", "endpoint", "grid", "variable", "native_units", "bbox",
    "start_date", "end_date", "refresh", "path"
  )
  missing <- setdiff(required, names(plan))
  if (length(missing) > 0L) {
    stop("Download plan is missing column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (!(is.numeric(delay_seconds) && length(delay_seconds) == 1L &&
        !is.na(delay_seconds) && is.finite(delay_seconds) && delay_seconds >= 0)) {
    stop("`delay_seconds` must be a non-negative number.", call. = FALSE)
  }
  if (!(is.numeric(jitter_seconds) && length(jitter_seconds) == 1L &&
        !is.na(jitter_seconds) && is.finite(jitter_seconds) && jitter_seconds >= 0)) {
    stop("`jitter_seconds` must be a non-negative number.", call. = FALSE)
  }

  prepared <- prepare_prism_request_queue(plan, force = force, max_requests = max_requests)
  queue <- prepared$queue
  if (!quiet) message(format_prism_plan_summary(prepared$summary))
  if (nrow(queue) == 0L) {
    return(invisible(data.frame()))
  }

  completed <- vector("list", nrow(queue))
  completed_count <- 0L

  for (index in seq_len(nrow(queue))) {
    item <- queue[index, , drop = FALSE]
    dir.create(dirname(item$path), recursive = TRUE, showWarnings = FALSE)
    previous_md5 <- if (file.exists(item$path)) {
      unname(tools::md5sum(item$path))
    } else {
      NA_character_
    }
    temporary <- tempfile("acis-", tmpdir = dirname(item$path), fileext = ".tif")
    on.exit(unlink(temporary), add = TRUE)
    if (!quiet) {
      message(
        "[", index, "/", nrow(queue), "] Downloading ", item$variable, " ", item$start_date,
        if (item$end_date != item$start_date) paste0(" to ", item$end_date) else ""
      )
    }

    request <- httr2::request(item$endpoint) |>
      httr2::req_body_json(prism_daily_payload(item), auto_unbox = TRUE) |>
      httr2::req_timeout(timeout_seconds) |>
      httr2::req_retry(max_tries = 5L, retry_on_failure = TRUE)
    response <- httr2::req_perform(request, path = temporary)
    validate_prism_geotiff(temporary, item)
    replace_file_atomically(temporary, item$path)
    current_md5 <- unname(tools::md5sum(item$path))

    completed_count <- completed_count + 1L
    completed[[completed_count]] <- data.frame(
      product = item$product,
      aoi_id = item$aoi_id,
      grid = item$grid,
      variable = item$variable,
      native_units = item$native_units,
      bbox = item$bbox,
      start_date = as.Date(item$start_date),
      end_date = as.Date(item$end_date),
      downloaded_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
      bytes = file.info(item$path)$size,
      md5 = current_md5,
      previous_md5 = previous_md5,
      changed = is.na(previous_md5) || !identical(previous_md5, current_md5),
      path = item$path,
      stringsAsFactors = FALSE
    )
    write_prism_manifest(completed[[completed_count]], manifest_path)

    if (index < nrow(queue) && (delay_seconds > 0 || jitter_seconds > 0)) {
      pause <- delay_seconds + stats::runif(1L, min = 0, max = jitter_seconds)
      if (!quiet) message(sprintf("Pausing %.2f seconds before the next request.", pause))
      Sys.sleep(pause)
    }
  }

  invisible(do.call(rbind, completed))
}

sync_prism <- function(
    mode = c("bootstrap", "catchup", "update"), ...,
    force = FALSE,
    max_requests = swc_prism$max_requests_per_run,
    delay_seconds = swc_prism$request_delay_seconds,
    jitter_seconds = swc_prism$request_jitter_seconds,
    quiet = FALSE) {
  mode <- match.arg(mode)
  plan <- plan_prism_download(mode = mode, ...)
  download_prism_plan(
    plan,
    force = force,
    max_requests = max_requests,
    delay_seconds = delay_seconds,
    jitter_seconds = jitter_seconds,
    quiet = quiet
  )
}
