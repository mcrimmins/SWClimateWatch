# Orchestrate one local PRISM update with skip logic and stage timings.

swc_env_flag <- function(name, default = FALSE) {
  value <- tolower(trimws(Sys.getenv(name, if (default) "true" else "false")))
  value %in% c("1", "true", "yes", "on")
}

swc_call_supported <- function(fun, args = list()) {
  formal_names <- names(formals(fun))
  if (!"..." %in% formal_names) args <- args[names(args) %in% formal_names]
  do.call(fun, args)
}

swc_safe_product_dates <- function(date_function) {
  tryCatch(date_function(), error = function(error) NULL)
}

swc_format_product_dates <- function(dates) {
  if (is.null(dates) || length(dates) == 0L) return(NA_character_)
  paste(paste0(names(dates), "=", as.character(dates)), collapse = ";")
}

swc_downloads_changed <- function(downloads) {
  if (!is.data.frame(downloads) || nrow(downloads) == 0L) return(logical())
  if (!"changed" %in% names(downloads)) return(rep(TRUE, nrow(downloads)))
  changed <- as.logical(downloads$changed)
  changed[is.na(changed)] <- TRUE
  changed
}

swc_append_timing_report <- function(rows, path) {
  if (is.null(path)) return(invisible(NULL))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  append <- file.exists(path) && file.info(path)$size > 0
  utils::write.table(
    rows,
    path,
    sep = ",",
    row.names = FALSE,
    col.names = !append,
    append = append,
    qmethod = "double"
  )
  invisible(path)
}

run_swc_daily_update <- function(
    update_prism = swc_env_flag("SWC_UPDATE_PRISM"),
    force_maps = swc_env_flag("SWC_FORCE_MAPS"),
    quiet = FALSE,
    timing_path = file.path("data", "diagnostics", "daily-update-timings.csv"),
    sync_function = sync_prism,
    processing_plan_function = plan_prism_daily_processing,
    processing_function = process_prism_daily_plan,
    map_function = update_enabled_prism_maps,
    overview_function = build_overview_map,
    site_function = build_map_product_site,
    date_function = map_product_expected_data_dates) {
  run_started_utc <- Sys.time()
  run_id <- paste0(format(run_started_utc, "%Y%m%dT%H%M%SZ", tz = "UTC"), "-", Sys.getpid())
  timing_rows <- list()
  add_timing <- function(stage, status, started, elapsed, items = NA_integer_) {
    timing_rows[[length(timing_rows) + 1L]] <<- data.frame(
      run_id = run_id,
      stage = stage,
      status = status,
      started_utc = format(started, tz = "UTC", usetz = TRUE),
      elapsed_seconds = round(elapsed, 3),
      items = as.integer(items),
      stringsAsFactors = FALSE
    )
  }
  run_stage <- function(stage, fun, items = function(value) {
    if (is.data.frame(value)) nrow(value) else length(value)
  }) {
    started_utc <- Sys.time()
    started <- proc.time()[["elapsed"]]
    value <- fun()
    elapsed <- proc.time()[["elapsed"]] - started
    item_count <- items(value)
    add_timing(stage, "COMPLETE", started_utc, elapsed, item_count)
    if (!quiet) {
      message("Update stage `", stage, "` completed in ", format_map_update_elapsed(elapsed), ".")
    }
    value
  }
  skip_stage <- function(stage) {
    add_timing(stage, "SKIPPED", Sys.time(), 0, 0L)
    invisible(NULL)
  }

  before_dates <- swc_safe_product_dates(date_function)
  downloads <- processed <- data.frame()
  changed_downloads <- logical()
  if (isTRUE(update_prism)) {
    downloads <- run_stage("download", function() {
      swc_call_supported(sync_function, list(mode = "update", quiet = quiet))
    })
    changed_downloads <- swc_downloads_changed(downloads)
    processing_plan <- run_stage("processing_plan", function() {
      swc_call_supported(
        processing_plan_function,
        list(verify_source_md5 = FALSE)
      )
    })
    processed <- run_stage("processing", function() {
      swc_call_supported(
        processing_function,
        list(plan = processing_plan, quiet = quiet)
      )
    })
  } else {
    if (!quiet) message("PRISM update skipped; set SWC_UPDATE_PRISM=true to enable it.")
    skip_stage("download")
    skip_stage("processing_plan")
    skip_stage("processing")
  }

  after_dates <- swc_safe_product_dates(date_function)
  data_changed <- any(changed_downloads) || nrow(processed) > 0L
  rebuild_maps <- data_changed || isTRUE(force_maps)
  if (rebuild_maps) {
    run_stage("map_products", function() {
      swc_call_supported(map_function, list(quiet = quiet))
    }, items = function(value) length(value))
  } else {
    if (isTRUE(update_prism) && !quiet) {
      message(
        "No new or changed PRISM files were found; skipping map-product and overview-map rebuilding."
      )
    }
    skip_stage("map_products")
  }

  rebuild_overview <- !isTRUE(update_prism) || rebuild_maps
  if (rebuild_overview) {
    run_stage("overview_map", function() swc_call_supported(overview_function))
  } else {
    skip_stage("overview_map")
  }
  run_stage("site_catalog", function() {
    swc_call_supported(
      site_function,
      list(expected_data_dates = after_dates)
    )
  }, items = function(value) {
    if (is.data.frame(value)) sum(value$enabled) else length(value)
  })

  total_elapsed <- as.numeric(difftime(Sys.time(), run_started_utc, units = "secs"))
  add_timing("total", "COMPLETE", run_started_utc, total_elapsed, NA_integer_)
  timings <- do.call(rbind, timing_rows)
  timings$update_prism <- isTRUE(update_prism)
  timings$force_maps <- isTRUE(force_maps)
  timings$data_changed <- data_changed
  timings$before_dates <- swc_format_product_dates(before_dates)
  timings$after_dates <- swc_format_product_dates(after_dates)
  swc_append_timing_report(timings, timing_path)

  summary <- data.frame(
    downloaded = nrow(downloads),
    downloaded_changed = sum(changed_downloads),
    processed = nrow(processed),
    data_changed = data_changed,
    maps_rebuilt = rebuild_maps,
    before_dates = swc_format_product_dates(before_dates),
    after_dates = swc_format_product_dates(after_dates),
    elapsed_seconds = round(total_elapsed, 3),
    stringsAsFactors = FALSE
  )
  if (!quiet) {
    message(
      "Daily update complete in ", format_map_update_elapsed(total_elapsed),
      ": ", nrow(downloads), " downloaded (", sum(changed_downloads),
      " changed); ", nrow(processed),
      " processed; maps ", if (rebuild_maps) "rebuilt" else "skipped", "."
    )
  }
  invisible(list(
    summary = summary,
    timings = timings,
    downloads = downloads,
    processed = processed
  ))
}
