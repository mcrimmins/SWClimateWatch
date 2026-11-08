# Revision-aware local monthly workflow. No rendering of the website or S3 sync.
prism_monthly_update_save <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile("monthly-state-", tmpdir = dirname(path), fileext = ".rds")
  on.exit(unlink(temporary), add = TRUE)
  saveRDS(object, temporary)
  replace_file_atomically(temporary, path)
}

prism_monthly_update_read <- function(path) if (file.exists(path)) readRDS(path) else NULL

prism_monthly_update_remove <- function(path, root) {
  if (!dir.exists(path)) return(invisible(NULL))
  target <- normalizePath(path, winslash = "/", mustWork = TRUE)
  parent <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!startsWith(tolower(target), paste0(tolower(parent), "/"))) stop("Refusing cleanup outside monthly state directory.")
  unlink(target, recursive = TRUE)
}

prism_monthly_content_signature <- function(path, month) {
  r <- terra::rast(path); values <- as.numeric(terra::values(r, mat = FALSE))
  values[is.nan(values)] <- NA_real_; values[!is.na(values) & values == 0] <- 0
  digest::digest(list(month = month, dimensions = dim(r), extent = as.vector(terra::ext(r)),
    crs = terra::crs(r), values = values), algo = "sha256")
}

prism_monthly_update_artifacts_valid <- function(paths) {
  if (is.null(paths) || !length(paths)) return(FALSE)
  all(vapply(paths, function(path) {
    marker <- tryCatch(readRDS(path), error = function(e) NULL)
    !is.null(marker) && prism_monthly_ranking_complete(path, marker$signature)
  }, logical(1)))
}

prism_monthly_update_accepted_valid <- function(state) {
  rows <- state$accepted
  !is.null(rows) && nrow(rows) > 0 && all(file.exists(rows$path)) &&
    identical(unname(tools::md5sum(rows$path)), as.character(rows$md5))
}

plan_prism_monthly_update <- function(today = Sys.Date(), manual = FALSE, refresh_months = 8L,
    start = "1895-01", cache_dir = prism_monthly_cache_dir(),
    state_dir = file.path(cache_dir, "revision-state"), bbox = swc_region$bbox,
    refresh_again = FALSE) {
  today <- as.Date(today)
  if (length(today) != 1L || is.na(today) || length(refresh_months) != 1L ||
      !is.finite(refresh_months) || refresh_months < 1 || refresh_months != floor(refresh_months)) stop("Invalid monthly update date/window.")
  target <- prism_monthly_latest_complete(today); cycle <- format(today, "%Y-%m")
  folder <- file.path(state_dir, "cycles", cycle)
  state_path <- file.path(folder, "state.rds"); stage_dir <- file.path(folder, "staged")
  config <- digest::digest(list(policy = "revision-cycle-v1", target = target, start = start,
    months = refresh_months, cache_dir = cache_dir, bbox = normalize_prism_bbox(bbox)), algo = "sha256")
  state <- prism_monthly_update_read(state_path)
  if (!is.null(state) && !identical(state$config, config)) stop("Monthly cycle configuration changed; use a separate state_dir.")
  within <- as.integer(format(today, "%d")) %in% swc_monthly_prism$early_month_days
  manifest_path <- file.path(cache_dir, "manifest.csv")
  manifest_same <- !is.null(state) && file.exists(manifest_path) &&
    identical(unname(tools::md5sum(manifest_path)), state$manifest_md5)
  status <- "DOWNLOAD"
  if (!is.null(state) && state$phase == "INSTALLING") status <- "RECOVERY_REQUIRED"
  else if (!is.null(state) && state$phase == "DATA_READY" && prism_monthly_update_accepted_valid(state)) status <- "REBUILD_ONLY"
  else if (!is.null(state) && state$phase == "COMPLETE" && !refresh_again && prism_monthly_update_accepted_valid(state)) {
    status <- if (manifest_same && prism_monthly_update_artifacts_valid(state$artifacts)) "ALREADY_COMPLETE" else "REBUILD_ONLY"
  }
  else if (!within && !isTRUE(manual)) status <- "SKIPPED_OUTSIDE_WINDOW"
  if (refresh_again && !is.null(state) && state$phase != "COMPLETE") stop("Resume the unfinished cycle before starting another source refresh.")
  requests <- data.frame(); live <- stage <- NULL
  if (status == "DOWNLOAD") {
    live <- plan_prism_monthly_download(start = start, end = target, cache_dir = cache_dir,
      bbox = bbox, today = today, verify_grids = FALSE)
    recent <- format(prism_monthly_window(target, refresh_months), "%Y-%m")
    recent <- recent[recent >= start]
    required <- unique(c(recent, live$month[!live$complete]))
    live <- live[live$month %in% required, ]
    stage <- plan_prism_monthly_download(months = unique(live$month), cache_dir = stage_dir,
      bbox = bbox, today = today, verify_grids = FALSE)
    requests <- data.frame(month = live$month, variable = live$variable,
      reason = ifelse(live$month == target, "LATEST_MONTH", ifelse(live$month %in% recent, "REVISION_CHECK", "REPAIR_OR_CATCHUP")),
      accepted_cached = live$complete, staged_verified = stage$complete,
      age_months = as.integer(substr(cycle, 1, 4)) * 12 + as.integer(substr(cycle, 6, 7)) -
        (as.integer(substr(live$month, 1, 4)) * 12 + as.integer(substr(live$month, 6, 7))))
  }
  list(summary = data.frame(status = status, cycle = cycle, target_month = target,
      within_early_window = within, manual = manual, inputs = nrow(requests),
      pending_requests = if (nrow(requests)) sum(!requests$staged_verified) else 0L),
    requests = requests, live = live, stage = stage, state = state, state_path = state_path,
    stage_dir = stage_dir, folder = folder, config = config)
}

prism_monthly_install_file <- function(from, to) {
  dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile("monthly-install-", tmpdir = dirname(to))
  on.exit(unlink(temporary), add = TRUE)
  if (!file.copy(from, temporary, overwrite = TRUE)) stop("Could not stage monthly file replacement.")
  replace_file_atomically(temporary, to)
}

prism_monthly_update_rollback <- function(state, state_path) {
  tx <- state$transaction
  for (i in seq_len(nrow(tx$entries))) {
    row <- tx$entries[i, ]
    if (row$existed) {
      if (!identical(unname(tools::md5sum(row$backup)), row$md5)) stop("Monthly rollback backup failed checksum verification.")
      prism_monthly_install_file(row$backup, row$path)
    } else if (file.exists(row$path)) unlink(row$path)
  }
  state$phase <- "DOWNLOADING"; state$transaction <- NULL
  prism_monthly_update_save(state, state_path)
  invisible(state)
}

commit_prism_monthly_revision <- function(preview, today, state_dir,
    install = prism_monthly_install_file) {
  live <- preview$live; staged <- preview$stage
  # Recheck staging after downloads; never install a partial set.
  staged <- plan_prism_monthly_download(months = unique(staged$month),
    cache_dir = preview$stage_dir, bbox = as.numeric(strsplit(staged$bbox[1], ",", fixed = TRUE)[[1]]), today = today)
  if (!all(staged$complete)) stop("Staged monthly set is incomplete.")
  reference <- if (any(live$complete)) terra::rast(live$path[which(live$complete)[1]]) else terra::rast(staged$path[1])
  for (i in seq_len(nrow(staged))) validate_prism_monthly_grid(staged$path[i], staged[i, ], reference)
  for (month in unique(staged$month)) {
    hi <- terra::rast(staged$path[staged$month == month & staged$variable == "maxt"])
    lo <- terra::rast(staged$path[staged$month == month & staged$variable == "mint"])
    if (terra::global(hi < lo, "sum", na.rm = TRUE)[1, 1] > 0) stop("Staged maximum temperature falls below minimum for ", month)
  }
  previous <- vapply(seq_len(nrow(live)), function(i) {
    if (!live$complete[i]) return(NA_character_)
    prism_monthly_content_signature(live$path[i], live$month[i])
  }, character(1))
  incoming <- vapply(seq_len(nrow(staged)), function(i) prism_monthly_content_signature(staged$path[i], staged$month[i]), character(1))
  changed <- is.na(previous) | previous != incoming
  changes <- data.frame(month = live$month, variable = live$variable, changed = changed,
    previous_content = previous, accepted_content = incoming, path = live$path)
  manifest_path <- file.path(dirname(dirname(live$path[1])), "manifest.csv")
  rollback <- file.path(preview$folder, "rollback"); dir.create(rollback, recursive = TRUE, showWarnings = FALSE)
  paths <- c(live$path, manifest_path)
  entries <- data.frame(path = paths, existed = file.exists(paths),
    backup = file.path(rollback, sprintf("%05d.backup", seq_along(paths))),
    md5 = unname(tools::md5sum(paths)))
  for (i in which(entries$existed)) {
    if (!file.copy(entries$path[i], entries$backup[i], overwrite = TRUE) ||
        !identical(unname(tools::md5sum(entries$backup[i])), entries$md5[i])) stop("Could not verify a monthly rollback backup.")
  }
  state <- prism_monthly_update_read(preview$state_path)
  state$phase <- "INSTALLING"; state$transaction <- list(entries = entries)
  prism_monthly_update_save(state, preview$state_path)
  journal <- state
  committed <- FALSE
  on.exit(if (!committed) prism_monthly_update_rollback(journal, preview$state_path), add = TRUE)
  for (i in which(changed)) install(staged$path[i], live$path[i])
  records <- read.csv(file.path(preview$stage_dir, "manifest.csv"), stringsAsFactors = FALSE)
  records <- records[match(staged$path, records$path), ]
  records$path <- live$path
  records$md5 <- unname(tools::md5sum(live$path)); records$bytes <- file.info(live$path)$size
  records$content_signature <- incoming
  records$refresh_cycle <- format(today, "%Y-%m")
  ages <- preview$requests$age_months
  records$stability_age <- ifelse(ages <= 6, "PROVISIONAL_AGE", "STABLE_AGE_EXPECTED")
  records$source_final_confirmed <- NA
  write_prism_manifest(records, manifest_path)
  state$phase <- "DATA_READY"; state$transaction <- NULL; state$changes <- changes
  state$accepted <- records[, c("path", "md5")]
  state$manifest_md5 <- unname(tools::md5sum(manifest_path))
  prism_monthly_update_save(state, preview$state_path)
  committed <- TRUE
  prism_monthly_update_remove(rollback, state_dir)
  prism_monthly_update_remove(preview$stage_dir, state_dir)
  state
}

plan_prism_monthly_rebuilds <- function(target, changes, start = "1895-01",
    ranking_dir = "data/diagnostics/prism-monthly-ranking-pilots",
    spi_dir = "data/diagnostics/prism-monthly-spi-pilots", all_retained = FALSE) {
  retained <- function(root) {
    if (!dir.exists(root)) return(character())
    x <- basename(list.dirs(root, recursive = FALSE))
    x[grepl("^[0-9]{4}-[0-9]{2}$", x) & x <= target]
  }
  ends <- sort(unique(c(target, retained(ranking_dir), retained(spi_dir))))
  changed <- changes[changes$changed, , drop = FALSE]
  jobs <- list()
  for (end in ends) for (duration in c(1L, 3L, 6L, 12L)) for (family in c("temperature", "precipitation", "spi")) {
    root <- if (family == "spi") spi_dir else ranking_dir
    folder <- if (family == "spi") file.path(root, end, sprintf("%02dmonth", duration)) else
      file.path(root, end, family, sprintf("%02dmonth", duration))
    exists <- file.exists(file.path(folder, "summary.csv")) || file.exists(file.path(folder, "complete.rds"))
    if (end != target && !exists) next
    variables <- if (family == "temperature") c("maxt", "mint") else "pcpn"
    affected <- FALSE
    if (end != target && !all_retained && any(changed$variable %in% variables)) {
      dependencies <- if (family == "spi") prism_monthly_spi_dependencies(start, end, duration) else
        prism_monthly_ranking_dependencies(start, end, duration)
      affected <- any(changed$variable %in% variables & changed$month %in% dependencies)
    }
    if (end == target || affected || all_retained) jobs[[length(jobs) + 1L]] <- data.frame(
      end_month = end, family = family, duration_months = duration,
      reason = if (end == target) "ENSURE_LATEST" else if (affected) "REVISED_INPUT" else "VERIFY_RETAINED")
  }
  do.call(rbind, jobs)
}

build_prism_monthly_update_products <- function(queue, cache_dir, start, bbox, ranking_dir, spi_dir, audit_dir) {
  source("R/map-reference-layers.R"); source("R/map-product-scales.R"); source("R/map-southwest.R")
  audit <- audit_prism_monthly_cache(start, max(queue$end_month), cache_dir, audit_dir, bbox)
  if (audit$summary$status == "FAIL") stop("Accepted monthly cache failed the full audit.")
  products <- list(); artifacts <- character()
  for (end in sort(unique(queue$end_month))) {
    selected <- queue[queue$end_month == end, ]; sliced <- prism_monthly_slice_audit(audit, end)
    rankings <- selected[selected$family != "spi", ]
    if (nrow(rankings)) {
      r <- build_prism_monthly_ranking_pilots(end = end,
        temperature_durations = rankings$duration_months[rankings$family == "temperature"],
        precipitation_durations = rankings$duration_months[rankings$family == "precipitation"],
        start = start, cache_dir = cache_dir, output_dir = ranking_dir, audit_dir = audit_dir, bbox = bbox, .audit = sliced)
      products[[length(products) + 1L]] <- data.frame(end_month = end, family = r$results$variable,
        duration_months = r$results$duration_months, status = r$results$status, event = r$results$event, note = r$results$note)
      artifacts <- c(artifacts, file.path(ranking_dir, end, rankings$family,
        sprintf("%02dmonth", rankings$duration_months), "complete.rds"))
    }
    spi <- selected[selected$family == "spi", ]
    if (nrow(spi)) {
      r <- build_prism_monthly_spi_pilots(end = end, durations = spi$duration_months, start = start,
        cache_dir = cache_dir, output_dir = spi_dir, audit_dir = audit_dir, bbox = bbox, .audit = sliced)
      products[[length(products) + 1L]] <- data.frame(end_month = end, family = "spi", duration_months = r$results$duration_months,
        status = r$results$status, event = r$results$event, note = r$results$note)
      artifacts <- c(artifacts, file.path(spi_dir, end, sprintf("%02dmonth", spi$duration_months), "complete.rds"))
    }
  }
  list(products = do.call(rbind, products), artifacts = unique(artifacts))
}

run_prism_monthly_update <- function(today = Sys.Date(), manual = FALSE, dry_run = FALSE,
    refresh_months = 8L, max_requests = 24L, refresh_again = FALSE,
    start = "1895-01", cache_dir = prism_monthly_cache_dir(),
    state_dir = file.path(cache_dir, "revision-state"), report_dir = "data/diagnostics/prism-monthly-update",
    ranking_dir = "data/diagnostics/prism-monthly-ranking-pilots", spi_dir = "data/diagnostics/prism-monthly-spi-pilots",
    audit_dir = "data/diagnostics/prism-monthly-cache-audit", bbox = swc_region$bbox,
    .fetch = NULL, .build = build_prism_monthly_update_products, .install = prism_monthly_install_file,
    delay_seconds = 1) {
  started <- proc.time()[["elapsed"]]
  args <- list(today = today, manual = manual, refresh_months = refresh_months, start = start,
    cache_dir = cache_dir, state_dir = state_dir, bbox = bbox, refresh_again = refresh_again)
  if (dry_run) return(do.call(plan_prism_monthly_update, args))
  if (!requireNamespace("filelock", quietly = TRUE)) stop("Install filelock with install.packages('filelock') before running the monthly updater.")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  lock <- filelock::lock(file.path(cache_dir, "monthly-revision.lock"), timeout = 0)
  if (is.null(lock)) stop("Another monthly revision updater is running.")
  on.exit(filelock::unlock(lock), add = TRUE)
  cycle <- format(as.Date(today), "%Y-%m")
  state_path <- file.path(state_dir, "cycles", cycle, "state.rds")
  # A process can stop at a month boundary. Recover any earlier journal before
  # inspecting the shared accepted cache for this cycle.
  journals <- list.files(file.path(state_dir, "cycles"), pattern = "^state\\.rds$",
    recursive = TRUE, full.names = TRUE)
  for (journal_path in journals) {
    state <- prism_monthly_update_read(journal_path)
    if (!is.null(state) && state$phase == "INSTALLING") prism_monthly_update_rollback(state, journal_path)
  }
  preview <- do.call(plan_prism_monthly_update, args)
  downloads <- changes <- products <- data.frame(); note <- ""
  status <- preview$summary$status
  dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
  if (status %in% c("DOWNLOAD", "REBUILD_ONLY")) {
    outcome <- tryCatch({
      state <- preview$state
      if (status == "DOWNLOAD") {
        if (is.null(state) || state$phase == "COMPLETE") {
          verify_retained <- !is.null(state) && !refresh_again
          if (!is.null(state) && refresh_again) prism_monthly_update_remove(preview$stage_dir, state_dir)
          state <- list(config = preview$config, cycle = cycle, phase = "DOWNLOADING", verify_all_retained = verify_retained)
          prism_monthly_update_save(state, state_path)
        } else if (state$phase != "DOWNLOADING") {
          state$phase <- "DOWNLOADING"; state$verify_all_retained <- TRUE
          prism_monthly_update_save(state, state_path)
        }
        downloads <- download_prism_monthly_plan(preview$stage, max_requests = max_requests,
          delay_seconds = delay_seconds, fetch = .fetch)
        if (nrow(downloads)) {
          downloads$run_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
          events <- file.path(preview$folder, "download-events.csv")
          old <- if (file.exists(events)) read.csv(events, stringsAsFactors = FALSE) else downloads[FALSE, ]
          write_prism_monthly_audit_report(rbind(old, downloads), events)
        }
        stage <- plan_prism_monthly_download(months = unique(preview$stage$month), cache_dir = preview$stage_dir,
          bbox = bbox, today = as.Date(today), verify_grids = FALSE)
        if (!all(stage$complete)) {
          status <- "PENDING_DOWNLOAD"
          if (as.integer(format(as.Date(today), "%d")) >= max(swc_monthly_prism$early_month_days)) {
            note <- "Refresh incomplete; automatic source retry window has ended. Resume manually."
          } else note <- "Refresh incomplete; previous accepted inputs and maps retained. Rerun to resume."
        } else {
          preview$stage <- stage
          state <- commit_prism_monthly_revision(preview, as.Date(today), state_dir, .install)
          changes <- state$changes
          write_prism_monthly_audit_report(changes, file.path(preview$folder, "changes.csv"))
          status <- "REBUILD_ONLY"
        }
      }
      if (status == "REBUILD_ONLY") {
        state <- prism_monthly_update_read(state_path)
        all_retained <- state$phase == "COMPLETE" || isTRUE(state$verify_all_retained) ||
          !identical(state$manifest_md5, unname(tools::md5sum(file.path(cache_dir, "manifest.csv"))))
        state$phase <- "DATA_READY"
        prism_monthly_update_save(state, state_path)
        changes <- state$changes
        queue <- plan_prism_monthly_rebuilds(preview$summary$target_month, changes, start, ranking_dir, spi_dir, all_retained)
        write_prism_monthly_audit_report(queue, file.path(report_dir, "rebuild-plan.csv"))
        write_prism_monthly_audit_report(queue, file.path(preview$folder, "rebuild-plan.csv"))
        built <- .build(queue, cache_dir, start, bbox, ranking_dir, spi_dir, audit_dir)
        products <- built$products
        write_prism_monthly_audit_report(products, file.path(preview$folder, "products.csv"))
        if (any(products$status != "READY") || !prism_monthly_update_artifacts_valid(built$artifacts)) {
          status <- "PENDING_PRODUCTS"; note <- "Accepted data retained; rerun to resume map generation without new downloads."
        } else {
          state$phase <- "COMPLETE"; state$artifacts <- built$artifacts
          state$manifest_md5 <- unname(tools::md5sum(file.path(cache_dir, "manifest.csv")))
          state$completed_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
          prism_monthly_update_save(state, state_path)
          status <- "COMPLETE"
        }
      }
      TRUE
    }, error = function(e) { note <<- conditionMessage(e); FALSE })
    if (!outcome) status <- "FAILED"
  }
  summary <- data.frame(status = status, cycle = cycle, target_month = preview$summary$target_month,
    requests_attempted = nrow(downloads), failed_requests = if (nrow(downloads)) sum(downloads$status == "FAILED") else 0L,
    inputs_accepted = nrow(changes), changed_inputs = if (nrow(changes)) sum(changes$changed) else 0L,
    products_built = if (nrow(products)) sum(products$event == "BUILT") else 0L,
    products_reused = if (nrow(products)) sum(products$event == "REUSED") else 0L,
    elapsed_seconds = proc.time()[["elapsed"]] - started, note = note)
  for (name in c("summary", "downloads", "changes", "products")) {
    write_prism_monthly_audit_report(get(name), file.path(report_dir, paste0(name, ".csv")))
  }
  if (status == "COMPLETE") write_prism_monthly_audit_report(summary, file.path(preview$folder, "success-summary.csv"))
  message("Monthly PRISM update: ", status, "; ", summary$requests_attempted, " requests; ", summary$changed_inputs,
    " changed inputs; ", summary$products_built, " built, ", summary$products_reused, " reused; ", round(summary$elapsed_seconds, 1), " seconds.")
  list(summary = summary, downloads = downloads, changes = changes, products = products,
    ranking_gallery = file.path(ranking_dir, "index.html"), spi_gallery = file.path(spi_dir, "index.html"))
}
