# Convert raw RCC-ACIS GeoTIFFs into dated, analysis-ready PRISM rasters.
# Values remain in PRISM's native Fahrenheit and inch units.

prism_raster_dates <- function(path, raster = terra::rast(path)) {
  dates <- prism_geotiff_dates(path)
  if (length(dates) == terra::nlyr(raster) && all(!is.na(dates))) {
    return(dates)
  }

  raster_time <- terra::time(raster)
  if (length(raster_time) == terra::nlyr(raster) && all(!is.na(raster_time))) {
    return(as.Date(raster_time))
  }

  stop("Raster does not contain one valid date for every layer: ", path, call. = FALSE)
}

validate_prism_native_values <- function(raster, variable, config = swc_prism) {
  variable <- validate_prism_variables(variable, config)
  if (length(variable) != 1L) {
    stop("Exactly one PRISM variable is required for raster validation.", call. = FALSE)
  }

  limits <- config$plausible_ranges[[variable]]
  value_range <- terra::global(raster, c("min", "max"), na.rm = TRUE)
  observed <- range(as.matrix(value_range), na.rm = TRUE)

  if (length(observed) != 2L || any(!is.finite(observed))) {
    stop("Raster contains no finite PRISM values.", call. = FALSE)
  }
  if (observed[1L] < limits[1L] || observed[2L] > limits[2L]) {
    stop(
      sprintf(
        "%s values fall outside the plausible native-unit range [%s, %s]: [%s, %s].",
        variable, limits[1L], limits[2L], observed[1L], observed[2L]
      ),
      call. = FALSE
    )
  }

  invisible(observed)
}

read_prism_daily_raster <- function(path, variable, validate_values = TRUE) {
  if (!file.exists(path)) {
    stop("PRISM raster does not exist: ", path, call. = FALSE)
  }
  variable <- validate_prism_variables(variable)
  if (length(variable) != 1L) {
    stop("Exactly one PRISM variable is required.", call. = FALSE)
  }

  raster <- terra::rast(path)
  dates <- prism_raster_dates(path, raster)
  if (anyDuplicated(dates)) {
    stop("PRISM raster contains duplicate layer dates: ", path, call. = FALSE)
  }
  if (is.unsorted(dates)) {
    stop("PRISM raster layer dates are not chronological: ", path, call. = FALSE)
  }

  terra::time(raster) <- dates
  names(raster) <- paste(variable, format(dates, "%Y-%m-%d"), sep = "_")
  if (validate_values) {
    validate_prism_native_values(raster, variable)
  }
  raster
}

prism_processed_manifest_path <- function(processed_dir = swc_paths$processed) {
  file.path(processed_dir, "prism", "manifest.csv")
}

prism_processed_path <- function(
    raw_path,
    raw_dir = swc_paths$raw,
    processed_dir = swc_paths$processed) {
  raw_root <- normalizePath(raw_dir, winslash = "/", mustWork = FALSE)
  source <- normalizePath(raw_path, winslash = "/", mustWork = FALSE)
  prefix <- paste0(sub("/+$", "", raw_root), "/")

  if (!startsWith(tolower(source), tolower(prefix))) {
    stop("Raw PRISM file is outside `raw_dir`: ", raw_path, call. = FALSE)
  }
  relative <- substring(source, nchar(prefix) + 1L)
  components <- strsplit(relative, "/", fixed = TRUE)[[1L]]
  do.call(file.path, c(list(processed_dir), as.list(components)))
}

plan_prism_daily_processing <- function(
    raw_manifest = read_prism_manifest(),
    aoi_id = swc_prism$aoi_id,
    variables = swc_prism$variables,
    raw_dir = swc_paths$raw,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir))) {
  variables <- validate_prism_variables(variables)
  required <- c(
    "product", "aoi_id", "variable", "native_units", "start_date", "end_date", "path"
  )
  missing <- setdiff(required, names(raw_manifest))
  if (length(missing) > 0L) {
    stop("Raw manifest is missing column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }

  selected <- raw_manifest[
    raw_manifest$product == "daily" &
      !is.na(raw_manifest$aoi_id) & raw_manifest$aoi_id == aoi_id &
      raw_manifest$variable %in% variables,
    , drop = FALSE
  ]
  if (nrow(selected) == 0L) {
    return(data.frame())
  }
  selected <- selected[!duplicated(selected$path, fromLast = TRUE), , drop = FALSE]
  missing_files <- selected$path[!file.exists(selected$path)]
  if (length(missing_files) > 0L) {
    stop("Raw manifest references missing file(s): ", paste(missing_files, collapse = ", "), call. = FALSE)
  }

  selected$source_path <- selected$path
  selected$source_md5 <- unname(tools::md5sum(selected$source_path))
  selected$path <- vapply(
    selected$source_path,
    prism_processed_path,
    character(1),
    raw_dir = raw_dir,
    processed_dir = processed_dir
  )

  current_source <- rep(NA_character_, nrow(selected))
  if (nrow(processed_manifest) > 0L &&
      all(c("path", "source_md5") %in% names(processed_manifest))) {
    match_index <- match(selected$path, processed_manifest$path)
    current_source <- processed_manifest$source_md5[match_index]
  }
  selected$refresh <- !file.exists(selected$path) |
    is.na(current_source) | current_source != selected$source_md5
  selected <- selected[order(selected$start_date, selected$variable), , drop = FALSE]
  rownames(selected) <- NULL
  selected
}

write_prism_processed_raster <- function(raster, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile("processed-", tmpdir = dirname(path), fileext = ".tif")
  on.exit(unlink(temporary), add = TRUE)

  terra::writeRaster(
    raster,
    temporary,
    overwrite = TRUE,
    datatype = "FLT4S",
    gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3", "TILED=YES")
  )
  written <- terra::rast(temporary)
  if (terra::nlyr(written) != terra::nlyr(raster) || !terra::compareGeom(written, raster)) {
    stop("Processed PRISM raster failed geometry validation: ", path, call. = FALSE)
  }
  written_dates <- prism_raster_dates(temporary, written)
  if (!all(written_dates == as.Date(terra::time(raster)))) {
    stop("Processed PRISM raster failed date validation: ", path, call. = FALSE)
  }

  replace_file_atomically(temporary, path)
  invisible(path)
}

process_prism_daily_plan <- function(
    plan,
    manifest_path = prism_processed_manifest_path(),
    force = FALSE,
    quiet = FALSE) {
  if (nrow(plan) == 0L) {
    if (!quiet) message("PRISM processing plan is empty.")
    return(invisible(data.frame()))
  }

  required <- c(
    "product", "aoi_id", "variable", "native_units", "start_date", "end_date",
    "source_path", "source_md5", "path", "refresh"
  )
  missing <- setdiff(required, names(plan))
  if (length(missing) > 0L) {
    stop("Processing plan is missing column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }

  pending <- isTRUE(force) | as.logical(plan$refresh)
  queue <- plan[pending, , drop = FALSE]
  if (!quiet) {
    message(
      "PRISM processing plan: ", nrow(plan), " total; ", nrow(plan) - nrow(queue),
      " current; ", nrow(queue), " scheduled."
    )
  }
  if (nrow(queue) == 0L) {
    return(invisible(data.frame()))
  }

  completed <- vector("list", nrow(queue))
  for (index in seq_len(nrow(queue))) {
    item <- queue[index, , drop = FALSE]
    if (!quiet) {
      message("[", index, "/", nrow(queue), "] Processing ", item$variable, " ", item$start_date)
    }
    raster <- read_prism_daily_raster(item$source_path, item$variable)
    expected_dates <- seq(as.Date(item$start_date), as.Date(item$end_date), by = "day")
    raster_dates <- as.Date(terra::time(raster))
    dates_match <- length(raster_dates) == length(expected_dates) &&
      all(raster_dates == expected_dates)
    if (!dates_match) {
      stop("Raw raster dates do not match its manifest record: ", item$source_path, call. = FALSE)
    }
    write_prism_processed_raster(raster, item$path)

    completed[[index]] <- data.frame(
      product = item$product,
      aoi_id = item$aoi_id,
      variable = item$variable,
      native_units = item$native_units,
      start_date = as.Date(item$start_date),
      end_date = as.Date(item$end_date),
      processed_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
      bytes = file.info(item$path)$size,
      md5 = unname(tools::md5sum(item$path)),
      source_path = item$source_path,
      source_md5 = item$source_md5,
      path = item$path,
      stringsAsFactors = FALSE
    )
    write_prism_manifest(completed[[index]], manifest_path)
  }

  invisible(do.call(rbind, completed))
}
