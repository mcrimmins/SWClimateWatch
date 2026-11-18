# Read-only upstream audit: temporary grids never enter operational manifests.
audit_prism_availability <- function(
    today = as.Date(format(Sys.time(), tz = "America/Phoenix", format = "%Y-%m-%d")),
    directory = "data/diagnostics/prism-availability",
    timeout_seconds = 45L) {
  today <- as.Date(today)
  stopifnot(length(today) == 1L, !is.na(today))
  started <- Sys.time()
  temporary <- tempfile("prism-availability-")
  dir.create(temporary)
  on.exit(unlink(temporary, recursive = TRUE), add = TRUE)
  # Oldest first: three days ago is the footprint control for each variable.
  plan <- plan_prism_download("bootstrap", start = today - 3L, end = today - 1L,
                              chunk_days = 1L, raw_dir = temporary)
  controls <- list()
  rows <- vector("list", nrow(plan))
  for (i in seq_len(nrow(plan))) {
    item <- plan[i, , drop = FALSE]
    tick <- proc.time()[["elapsed"]]
    row <- data.frame(
      checked_utc = format(Sys.time(), tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ"),
      checked_phoenix = format(Sys.time(), tz = "America/Phoenix", usetz = TRUE),
      date = as.character(item$start_date), lag_days = as.integer(today - item$start_date),
      variable = item$variable, status = "ERROR", valid_cells = NA_integer_,
      total_cells = NA_integer_, control_coverage = NA_real_, invalid_cells = NA_integer_,
      minimum = NA_real_, maximum = NA_real_, bytes = 0, elapsed_seconds = 0,
      note = "", stringsAsFactors = FALSE
    )
    tryCatch({
      path <- file.path(temporary, paste0(i, ".tif"))
      request <- httr2::request(item$endpoint) |>
        httr2::req_body_json(prism_daily_payload(item), auto_unbox = TRUE) |>
        httr2::req_timeout(timeout_seconds)
      httr2::req_perform(request, path = path)
      row$bytes <- file.info(path)$size
      raster <- validate_prism_geotiff(path, item)
      values <- terra::values(raster, mat = FALSE)
      if (item$start_date == today - 3L) {
        controls[[item$variable]] <- list(raster = raster, values = values)
      }
      control <- controls[[item$variable]]
      if (is.null(control)) {
        control_values <- rep(NA_real_, length(values))
      } else {
        if (!terra::compareGeom(raster, control$raster, stopOnError = FALSE)) {
          stop("Grid geometry differs from the three-day-old control.")
        }
        control_values <- control$values
      }
      metrics <- prism_availability_metrics(
        values, control_values, swc_prism$plausible_ranges[[item$variable]])
      for (name in names(metrics)) row[[name]] <- metrics[[name]]
    }, error = function(e) { row$note <<- conditionMessage(e) })
    row$elapsed_seconds <- round(proc.time()[["elapsed"]] - tick, 3)
    rows[[i]] <- row
    message(item$start_date, " ", item$variable, ": ", row$status,
            if (nzchar(row$note)) paste0(" — ", row$note) else "")
    if (i < nrow(plan)) Sys.sleep(swc_prism$request_delay_seconds)
  }
  fields <- do.call(rbind, rows)
  dates <- do.call(rbind, lapply(unique(fields$date), function(date) {
    x <- fields[fields$date == date, ]
    data.frame(date = date, lag_days = x$lag_days[1L],
      ready = all(x$status == "AVAILABLE") &&
        setequal(x$variable, swc_prism$variables),
      fields_available = sum(x$status == "AVAILABLE"),
      fields_expected = length(swc_prism$variables),
      checked_phoenix = fields$checked_phoenix[1L])
  }))
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  stamp <- paste0(format(started, tz = "UTC", format = "%Y%m%dT%H%M%SZ"), "-", Sys.getpid())
  utils::write.csv(fields, file.path(directory, paste0(stamp, "-fields.csv")), row.names = FALSE)
  utils::write.csv(fields, file.path(directory, "latest-fields.csv"), row.names = FALSE)
  utils::write.csv(dates, file.path(directory, "latest-dates.csv"), row.names = FALSE)
  print(dates, row.names = FALSE)
  message("Availability audit only: no operational grids, manifests, maps or S3 objects changed. ",
          "Elapsed: ", round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1), " seconds.")
  invisible(list(fields = fields, dates = dates))
}
