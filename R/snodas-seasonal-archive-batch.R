# Local-only, resumable batch runner for unpublished October-May SNODAS maps.
# Source snodas-seasonal-archive.R first.

validate_snodas_seasonal_archive_years <- function(years) {
  if (!is.numeric(years) || !length(years) || anyNA(years) ||
      any(!is.finite(years)) || any(years != floor(years)) ||
      any(years < 2005L | years > 2025L)) {
    stop("Choose one or more whole SNODAS water years from 2005-2025.",
         call. = FALSE)
  }
  sort(unique(as.integer(years)))
}

plan_snodas_seasonal_archive_batch <- function(
    years, output_root = file.path("data", "diagnostics",
                                   "snodas-seasonal-archive")) {
  years <- validate_snodas_seasonal_archive_years(years)
  paths <- file.path(output_root, sprintf("wy%04d", years))
  result <- data.frame(
    water_year = years,
    complete_marker = file.exists(file.path(paths, "complete.csv")),
    partial_grids = vapply(paths, function(path) {
      all(file.exists(file.path(path,
                                c("peak_swe.tif", "snow_days.tif",
                                  "coverage.tif"))))
    }, logical(1)),
    stringsAsFactors = FALSE
  )
  rownames(result) <- NULL
  result
}

append_snodas_seasonal_archive_batch_log <- function(row, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  old <- if (file.exists(path)) {
    utils::read.csv(path, stringsAsFactors = FALSE)
  } else row[FALSE, , drop = FALSE]
  if (!identical(names(old), names(row))) {
    stop("Unexpected SNODAS seasonal batch log columns: ", path,
         call. = FALSE)
  }
  temporary <- tempfile("snodas-seasonal-batch-", tmpdir = dirname(path),
                        fileext = ".csv")
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
  utils::write.csv(rbind(old, row), temporary, row.names = FALSE)
  if (!file.copy(temporary, path, overwrite = TRUE)) {
    stop("Could not checkpoint SNODAS seasonal batch log: ", path,
         call. = FALSE)
  }
  invisible(row)
}

run_snodas_seasonal_archive_batch <- function(
    years, max_new_years = Inf, dry_run = FALSE,
    continue_on_error = TRUE, render_maps = TRUE,
    output_root = file.path("data", "diagnostics",
                            "snodas-seasonal-archive"),
    log_path = file.path(output_root, "batch-log.csv"),
    build_year = build_snodas_seasonal_archive_year) {
  years <- validate_snodas_seasonal_archive_years(years)
  if (!is.numeric(max_new_years) || length(max_new_years) != 1L ||
      is.na(max_new_years) || max_new_years < 1L ||
      max_new_years != floor(max_new_years)) {
    stop("`max_new_years` must be a positive whole number or Inf.",
         call. = FALSE)
  }
  for (name in c("dry_run", "continue_on_error", "render_maps")) {
    value <- get(name)
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      stop("`", name, "` must be TRUE or FALSE.", call. = FALSE)
    }
  }
  if (!is.function(build_year)) {
    stop("`build_year` must be a function.", call. = FALSE)
  }
  preview <- plan_snodas_seasonal_archive_batch(years, output_root)
  print(preview, row.names = FALSE)
  message("Complete markers are only provisional in this preview; the ",
          "builder verifies source and output checksums when run.")
  if (dry_run) {
    message("SNODAS seasonal archive preview only; no maps built.")
    return(list(preview = preview, results = NULL,
                limit_reached = FALSE, log_path = log_path))
  }
  run_id <- paste0(format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"),
                   "-", Sys.getpid())
  results <- list()
  attempted_new <- 0L
  limit_reached <- FALSE
  for (index in seq_along(years)) {
    if (attempted_new >= max_new_years) {
      limit_reached <- TRUE
      break
    }
    year <- years[index]
    output_dir <- file.path(output_root, sprintf("wy%04d", year))
    resume_partial <- !preview$complete_marker[index] &&
      preview$partial_grids[index]
    message(sprintf("SNODAS seasonal archive %d/%d: WY%d%s",
                    index, length(years), year,
                    if (resume_partial) " (verifying partial grids)" else ""))
    started <- Sys.time()
    outcome <- tryCatch(build_year(
      water_year = year, output_dir = output_dir,
      render_maps = render_maps, resume_partial = resume_partial
    ), error = identity)
    elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
    if (!inherits(outcome, "error") &&
        (!is.list(outcome) ||
         !is.logical(outcome$refreshed) ||
         length(outcome$refreshed) != 1L ||
         is.na(outcome$refreshed) ||
         !is.data.frame(outcome$quality) ||
         nrow(outcome$quality) != 1L ||
         !all(c("status", "peak_max_inches",
                "peak_cells_for_review") %in% names(outcome$quality)) ||
         length(outcome$quality$status) != 1L ||
         is.na(outcome$quality$status) ||
         !outcome$quality$status %in% c("PASS", "REVIEW", "FAIL"))) {
      outcome <- simpleError(paste0("WY", year,
                                    " builder returned an invalid result."))
    }
    if (inherits(outcome, "error")) {
      attempted_new <- attempted_new + 1L
      event <- "ERROR"
      quality_status <- NA_character_
      peak_max <- NA_real_
      high_cells <- NA_integer_
      note <- conditionMessage(outcome)
      message("WY", year, " failed: ", note)
    } else {
      if (outcome$refreshed) attempted_new <- attempted_new + 1L
      quality_status <- as.character(outcome$quality$status[[1L]])
      peak_max <- as.numeric(outcome$quality$peak_max_inches[[1L]])
      high_cells <- as.integer(outcome$quality$peak_cells_for_review[[1L]])
      event <- if (!outcome$refreshed) "SKIPPED_CURRENT" else {
        paste0("BUILT_", quality_status)
      }
      note <- ""
      message("WY", year, ": ", event, " (", round(elapsed, 1), "s).")
    }
    row <- data.frame(
      run_id = run_id,
      time_utc = format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC", tz = "UTC"),
      water_year = year, event = event,
      elapsed_seconds = round(elapsed, 3),
      quality_status = quality_status,
      peak_max_inches = peak_max,
      peak_cells_for_review = high_cells,
      note = note, stringsAsFactors = FALSE
    )
    append_snodas_seasonal_archive_batch_log(row, log_path)
    results[[length(results) + 1L]] <- row
    if (event == "ERROR" && !continue_on_error) {
      stop("SNODAS seasonal archive stopped at WY", year, ": ", note,
           call. = FALSE)
    }
  }
  result_table <- if (length(results)) do.call(rbind, results) else NULL
  if (limit_reached) {
    message("Batch limit reached; rerun the same call to continue with ",
            "the next unfinished water years.")
  }
  list(preview = preview, results = result_table,
       limit_reached = limit_reached, log_path = log_path)
}
