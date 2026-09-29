# Resumable, paced, year-by-year SNODAS October-May bootstrap.
# Source the SNODAS core, inventory, bootstrap, and season-audit modules first.

validate_snodas_baseline_years <- function(years) {
  if (!is.numeric(years) || !length(years) || anyNA(years) ||
      any(!is.finite(years)) || any(years != floor(years)) ||
      any(years < 2005L | years > 2025L)) {
    stop("Choose one or more whole SNODAS water years from 2005-2025.",
         call. = FALSE)
  }
  sort(unique(as.integer(years)))
}

plan_snodas_baseline <- function(
    years,
    inventory_path = file.path("data", "diagnostics", "snodas-audit",
                               "monthly-directory-inventory.csv"),
    raw_dir = swc_paths$raw,
    processed_dir = swc_paths$processed,
    errata = read_snodas_missing_days(file.path(
      raw_dir, "snodas", "reference", "G02158_missing_files.txt"
    ))) {
  years <- validate_snodas_baseline_years(years)
  rows <- lapply(years, function(year) {
    snodas_cool_season_status(
      plan_snodas_cool_season(year, inventory_path, raw_dir, errata),
      processed_dir
    )
  })
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}

snodas_baseline_log_row <- function(year, event, before = NA_integer_,
                                    after = NA_integer_, note = "") {
  data.frame(
    time_utc = format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC", tz = "UTC"),
    water_year = as.integer(year), event = as.character(event),
    processing_pending_before = as.integer(before),
    processing_pending_after = as.integer(after),
    note = as.character(note), stringsAsFactors = FALSE
  )
}

append_snodas_baseline_log <- function(
    row, path = file.path("data", "diagnostics", "snodas-baseline",
                          "overnight-log.csv")) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  old <- if (file.exists(path)) {
    utils::read.csv(path, stringsAsFactors = FALSE)
  } else row[FALSE, , drop = FALSE]
  if (!identical(names(old), names(row))) {
    stop("Unexpected SNODAS overnight-log columns: ", path,
         call. = FALSE)
  }
  temporary <- tempfile("snodas-overnight-log-", tmpdir = dirname(path),
                        fileext = ".csv")
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
  utils::write.csv(rbind(old, row), temporary, row.names = FALSE)
  if (!file.copy(temporary, path, overwrite = TRUE)) {
    stop("Could not checkpoint SNODAS overnight log: ", path,
         call. = FALSE)
  }
  invisible(row)
}

run_snodas_baseline <- function(
    years,
    inventory_path = file.path("data", "diagnostics", "snodas-audit",
                               "monthly-directory-inventory.csv"),
    raw_dir = swc_paths$raw,
    processed_dir = swc_paths$processed,
    log_path = file.path("data", "diagnostics", "snodas-baseline",
                         "overnight-log.csv"),
    max_stages = Inf,
    stage_pause_seconds = 30,
    retry_limit = 2L,
    audit_completed_years = TRUE,
    stop_on_audit_flags = TRUE,
    dry_run = FALSE) {
  years <- validate_snodas_baseline_years(years)
  if (!is.numeric(max_stages) || length(max_stages) != 1L ||
      is.na(max_stages) || max_stages < 1L ||
      max_stages != floor(max_stages)) {
    stop("`max_stages` must be a positive whole number or Inf.",
         call. = FALSE)
  }
  if (!is.numeric(stage_pause_seconds) ||
      length(stage_pause_seconds) != 1L ||
      !is.finite(stage_pause_seconds) || stage_pause_seconds < 0) {
    stop("`stage_pause_seconds` must be nonnegative and finite.",
         call. = FALSE)
  }
  if (!is.numeric(retry_limit) || length(retry_limit) != 1L ||
      is.na(retry_limit) || retry_limit != floor(retry_limit) ||
      retry_limit < 0L || retry_limit > 2L) {
    stop("`retry_limit` must be 0, 1, or 2.", call. = FALSE)
  }
  for (name in c("audit_completed_years", "stop_on_audit_flags", "dry_run")) {
    value <- get(name)
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      stop("`", name, "` must be TRUE or FALSE.", call. = FALSE)
    }
  }
  initial <- plan_snodas_baseline(years, inventory_path, raw_dir,
                                  processed_dir)
  print(initial[, c("water_year", "listed_dates", "known_missing_dates",
                    "paired_processed", "processing_pending")],
        row.names = FALSE)
  if (dry_run) {
    message("SNODAS baseline preview only: no downloads or audits started.")
    return(list(initial = initial, final = initial, stages_attempted = 0L,
                stage_limit_reached = FALSE, log_path = log_path))
  }
  repair_needed <- vapply(years, function(year) {
    as.Date(sprintf("%d-10-01", year - 1L)) <= as.Date("2019-10-10") &&
      as.Date(sprintf("%d-05-31", year)) >= as.Date("2014-10-09")
  }, logical(1))
  repair_mask <- file.path(raw_dir, "snodas", "reference",
                           "SNODAS_Zero_Repair_Mask.tif")
  if (any(repair_needed) && !file.exists(repair_mask)) {
    stop("Historical SNODAS repair mask is required before downloading: ",
         repair_mask, call. = FALSE)
  }
  stages_attempted <- 0L
  limit_reached <- FALSE
  for (year in years) {
    status <- snodas_cool_season_status(
      plan_snodas_cool_season(year, inventory_path, raw_dir),
      processed_dir
    )
    if (status$processing_pending == 0L) {
      message("WY", year, " already processed; skipping downloads.")
      append_snodas_baseline_log(snodas_baseline_log_row(
        year, "SKIPPED_COMPLETE", 0L, 0L
      ), log_path)
    }
    while (status$processing_pending > 0L) {
      if (stages_attempted >= max_stages) {
        limit_reached <- TRUE
        append_snodas_baseline_log(snodas_baseline_log_row(
          year, "STAGE_LIMIT", status$processing_pending,
          status$processing_pending
        ), log_path)
        break
      }
      if (stages_attempted > 0L) {
        Sys.sleep(max(stage_pause_seconds,
                      swc_snodas$request_delay_seconds))
      }
      before <- status$processing_pending
      for (attempt in seq_len(retry_limit + 1L)) {
        if (stages_attempted >= max_stages) {
          limit_reached <- TRUE
          break
        }
        stages_attempted <- stages_attempted + 1L
        message(sprintf("WY%d stage attempt %d, %d dates pending.",
                        year, stages_attempted, before))
        outcome <- tryCatch(
          run_snodas_cool_season_stage(
            year, inventory_path = inventory_path,
            raw_dir = raw_dir, processed_dir = processed_dir,
            retain_raw = FALSE
          ), error = identity
        )
        if (!inherits(outcome, "error")) break
        append_snodas_baseline_log(snodas_baseline_log_row(
          year, "STAGE_ERROR", before, NA_integer_,
          conditionMessage(outcome)
        ), log_path)
        if (attempt > retry_limit || stages_attempted >= max_stages) {
          stop("SNODAS WY", year, " stopped after stage error: ",
               conditionMessage(outcome), call. = FALSE)
        }
        Sys.sleep(60 * attempt)
      }
      if (limit_reached) break
      status <- outcome
      append_snodas_baseline_log(snodas_baseline_log_row(
        year, "STAGE_COMPLETE", before, status$processing_pending,
        paste0("processed_mb=", status$processed_mb)
      ), log_path)
      if (status$processing_pending >= before) {
        stop("SNODAS WY", year, " made no processing progress.",
             call. = FALSE)
      }
    }
    if (limit_reached) break
    if (audit_completed_years) {
      quality <- audit_snodas_cool_season(
        year, inventory_path = inventory_path, raw_dir = raw_dir,
        processed_dir = processed_dir
      )
      summary <- quality$summary
      append_snodas_baseline_log(snodas_baseline_log_row(
        year, "AUDIT_COMPLETE", 0L, summary$pending_dates,
        paste0("flags=", summary$flagged_dates,
               ";geometry_variants=", summary$geometry_variants)
      ), log_path)
      if (summary$pending_dates != 0L || summary$geometry_variants != 1L ||
          (stop_on_audit_flags && summary$flagged_dates > 0L)) {
        stop("SNODAS WY", year, " quality audit needs review: ",
             "pending=", summary$pending_dates,
             ", flags=", summary$flagged_dates,
             ", geometry variants=", summary$geometry_variants,
             call. = FALSE)
      }
    }
  }
  final <- plan_snodas_baseline(years, inventory_path, raw_dir,
                                processed_dir)
  list(initial = initial, final = final,
       stages_attempted = stages_attempted,
       stage_limit_reached = limit_reached, log_path = log_path)
}
