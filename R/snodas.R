# Capped single-day SNODAS downloads and local masked-grid processing.
# Source R/config.R first. This module is not part of the daily site update yet.

snodas_date <- function(date) {
  value <- as.Date(date)
  if (length(value) != 1L || is.na(value)) {
    stop("Expected one valid SNODAS date.", call. = FALSE)
  }
  value
}

snodas_archive_url <- function(date, config = swc_snodas) {
  date <- snodas_date(date)
  if (date < config$first_date) stop("Date precedes SNODAS coverage.", call. = FALSE)
  paste0(
    config$base_url, "/", format(date, "%Y"), "/",
    format(date, "%m"), "_", month.abb[as.integer(format(date, "%m"))], "/",
    "SNODAS_", format(date, "%Y%m%d"), ".tar"
  )
}

snodas_archive_path <- function(date, raw_dir = swc_paths$raw) {
  date <- snodas_date(date)
  file.path(raw_dir, "snodas", "masked", format(date, "%Y"),
            format(date, "%m"), paste0("SNODAS_", format(date, "%Y%m%d"), ".tar"))
}

snodas_processed_path <- function(date, variable = "swe",
                                  processed_dir = swc_paths$processed,
                                  aoi_id = swc_snodas$aoi_id) {
  date <- snodas_date(date)
  if (length(variable) != 1L || !variable %in% swc_snodas$variables) {
    stop("SNODAS variable must be 'swe' or 'depth'.", call. = FALSE)
  }
  file.path(processed_dir, "snodas", aoi_id, "daily", variable,
            paste0(date, ".tif"))
}

snodas_manifest_path <- function(kind = c("raw", "processed"),
                                 root = NULL) {
  kind <- match.arg(kind)
  if (is.null(root)) root <- swc_paths[[kind]]
  file.path(root, "snodas", "manifest.csv")
}

read_snodas_manifest <- function(path) {
  if (!file.exists(path)) return(data.frame())
  utils::read.csv(path, stringsAsFactors = FALSE)
}

write_snodas_manifest_row <- function(row, path, key_columns) {
  old <- read_snodas_manifest(path)
  if (nrow(old)) {
    for (column in setdiff(names(row), names(old))) old[[column]] <- NA
    for (column in setdiff(names(old), names(row))) row[[column]] <- NA
    old <- old[, names(row), drop = FALSE]
    same <- rep(TRUE, nrow(old))
    for (key in key_columns) same <- same & old[[key]] == row[[key]][1L]
    old <- old[!same, , drop = FALSE]
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile("manifest-", tmpdir = dirname(path), fileext = ".csv")
  on.exit(unlink(temporary), add = TRUE)
  utils::write.csv(rbind(old, row), temporary, row.names = FALSE, na = "")
  if (!file.copy(temporary, path, overwrite = TRUE)) {
    stop("Could not write SNODAS manifest: ", path, call. = FALSE)
  }
  invisible(row)
}

plan_snodas_download <- function(dates, refresh = FALSE,
                                 raw_dir = swc_paths$raw) {
  dates <- sort(unique(as.Date(dates)))
  if (anyNA(dates) || any(dates < swc_snodas$first_date)) {
    stop("SNODAS dates must be valid and within dataset coverage.", call. = FALSE)
  }
  if (!is.logical(refresh) || length(refresh) != 1L || is.na(refresh)) {
    stop("`refresh` must be TRUE or FALSE.", call. = FALSE)
  }
  paths <- vapply(dates, snodas_archive_path, character(1), raw_dir = raw_dir)
  existing <- file.exists(paths)
  existing[existing] <- file.info(paths[existing])$size > 0
  data.frame(
    date = dates,
    url = vapply(dates, snodas_archive_url, character(1)),
    path = paths,
    complete = existing & !refresh,
    stringsAsFactors = FALSE
  )
}

preview_snodas_download <- function(plan,
                                    max_requests = swc_snodas$max_requests_per_run) {
  if (!is.data.frame(plan) || !all(c("date", "url", "path", "complete") %in% names(plan))) {
    stop("Invalid SNODAS download plan.", call. = FALSE)
  }
  if (length(max_requests) != 1L || !is.numeric(max_requests) ||
      !is.finite(max_requests) || max_requests < 0 ||
      max_requests != floor(max_requests) ||
      max_requests > swc_snodas$max_requests_per_run) {
    stop("`max_requests` must be between 0 and the configured SNODAS cap.", call. = FALSE)
  }
  pending <- sum(!plan$complete)
  scheduled <- min(pending, max_requests)
  summary <- data.frame(total = nrow(plan), complete = sum(plan$complete),
                        scheduled = scheduled, deferred = pending - scheduled)
  message(sprintf("SNODAS plan: %d dates; %d complete; %d scheduled; %d deferred.",
                  summary$total, summary$complete, summary$scheduled,
                  summary$deferred))
  summary
}

snodas_archive_members <- function(archive, date, variable = "swe") {
  date <- snodas_date(date)
  if (!file.exists(archive) || file.info(archive)$size <= 0) {
    stop("Missing or empty SNODAS archive: ", archive, call. = FALSE)
  }
  code <- switch(variable, swe = "11034", depth = "11036",
                 stop("SNODAS variable must be 'swe' or 'depth'.", call. = FALSE))
  members <- utils::untar(archive, list = TRUE)
  pattern <- paste0("^([.]/)?us_ssmv", code, ".*", format(date, "%Y%m%d"),
                    ".*[.](dat|txt)[.]gz$")
  selected <- grep(pattern, members, value = TRUE)
  if (length(selected) != 2L ||
      sum(grepl("[.]dat[.]gz$", selected)) != 1L ||
      sum(grepl("[.]txt[.]gz$", selected)) != 1L ||
      any(gsub("^[.]/", "", selected) !=
          basename(gsub("^[.]/", "", selected)))) {
    stop("SNODAS archive lacks a safe data/header pair for ", variable,
         " on ", date, call. = FALSE)
  }
  selected
}

download_snodas_plan <- function(plan,
                                 max_requests = swc_snodas$max_requests_per_run,
                                 delay_seconds = swc_snodas$request_delay_seconds,
                                 jitter_seconds = swc_snodas$request_jitter_seconds,
                                 fetch = function(url, destination) {
                                   utils::download.file(url, destination,
                                                        mode = "wb", quiet = TRUE,
                                                        method = "libcurl")
                                 },
                                 raw_dir = swc_paths$raw) {
  preview_snodas_download(plan, max_requests)
  if (!is.numeric(delay_seconds) || length(delay_seconds) != 1L ||
      !is.finite(delay_seconds) || delay_seconds < 0 ||
      !is.numeric(jitter_seconds) || length(jitter_seconds) != 1L ||
      !is.finite(jitter_seconds) || jitter_seconds < 0) {
    stop("Request delays must be nonnegative finite numbers.", call. = FALSE)
  }
  selected <- head(which(!plan$complete), max_requests)
  if (!length(selected)) return(data.frame())
  old_timeout <- getOption("timeout")
  options(timeout = max(old_timeout, swc_snodas$request_timeout_seconds))
  on.exit(options(timeout = old_timeout), add = TRUE)
  result <- vector("list", length(selected))
  for (index in seq_along(selected)) {
    row <- plan[selected[index], , drop = FALSE]
    if (index > 1L) Sys.sleep(delay_seconds + stats::runif(1L, 0, jitter_seconds))
    dir.create(dirname(row$path), recursive = TRUE, showWarnings = FALSE)
    temporary <- tempfile("snodas-download-", tmpdir = dirname(row$path),
                          fileext = ".tar")
    tryCatch({
      status <- fetch(row$url, temporary)
      if (!is.null(status) && !identical(as.integer(status), 0L)) {
        stop("Download returned status ", status)
      }
      snodas_archive_members(temporary, row$date, "swe")
      backup <- tempfile("snodas-previous-", tmpdir = dirname(row$path),
                         fileext = ".tar")
      had_previous <- file.exists(row$path)
      if (had_previous && !file.rename(row$path, backup)) {
        stop("Could not safeguard previous SNODAS archive: ", row$path)
      }
      if (!file.rename(temporary, row$path)) {
        if (had_previous) file.rename(backup, row$path)
        stop("Could not move SNODAS archive into place: ", row$path)
      }
      if (had_previous) unlink(backup)
      info <- file.info(row$path)
      record <- data.frame(
        date = as.character(row$date), source_url = row$url,
        path = row$path, bytes = info$size,
        md5 = unname(tools::md5sum(row$path)),
        downloaded_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
      )
      write_snodas_manifest_row(
        record, snodas_manifest_path("raw", raw_dir), "date"
      )
      result[[index]] <- record
      message(sprintf("[%d/%d] Downloaded SNODAS %s", index,
                      length(selected), row$date))
    }, finally = {
      if (file.exists(temporary)) unlink(temporary)
    })
  }
  do.call(rbind, result)
}

snodas_read_header <- function(path) {
  connection <- gzfile(path, open = "rt")
  on.exit(close(connection), add = TRUE)
  lines <- readLines(connection, warn = FALSE)
  keys <- trimws(sub(":.*$", "", lines))
  values <- trimws(sub("^[^:]*:", "", lines))
  stats::setNames(values, keys)
}

snodas_raster_from_archive <- function(archive, date, variable = "swe",
                                       bbox = swc_region$bbox) {
  date <- snodas_date(date)
  selected <- snodas_archive_members(archive, date, variable)
  extracted <- tempfile("snodas-extract-")
  dir.create(extracted)
  on.exit(unlink(extracted, recursive = TRUE), add = TRUE)
  utils::untar(archive, files = selected, exdir = extracted)
  data_path <- file.path(extracted, grep("[.]dat[.]gz$", selected, value = TRUE))
  header_path <- file.path(extracted, grep("[.]txt[.]gz$", selected, value = TRUE))
  if (!file.exists(data_path) || !file.exists(header_path)) {
    stop("SNODAS archive extraction failed: ", archive, call. = FALSE)
  }
  header <- snodas_read_header(header_path)
  field <- function(key) as.numeric(header[[key]])
  ncol <- as.integer(field("Number of columns"))
  nrow <- as.integer(field("Number of rows"))
  xmin <- field("Minimum x-axis coordinate")
  ymax <- field("Maximum y-axis coordinate")
  xres <- field("X-axis resolution")
  yres <- field("Y-axis resolution")
  nodata <- as.integer(field("No data value"))
  valid_utc <- sprintf("%04d-%02d-%02d %02d:%02d UTC",
                       as.integer(field("Start year")),
                       as.integer(field("Start month")),
                       as.integer(field("Start day")),
                       as.integer(field("Start hour")),
                       as.integer(field("Start minute")))
  metadata <- c(ncol, nrow, xmin, ymax, xres, yres, nodata)
  if (anyNA(metadata) || !all(is.finite(metadata)) ||
      ncol < 1L || nrow < 1L || xres <= 0 || yres <= 0 ||
      ncol * nrow > 1e8 ||
      !identical(substr(valid_utc, 1L, 10L), as.character(date)) ||
      !identical(header[["Data units"]], "Meters / 1000.000000") ||
      !identical(header[["Data bytes per pixel"]], "2")) {
    stop("Unexpected SNODAS header metadata: ", header_path, call. = FALSE)
  }
  bbox <- as.numeric(bbox)
  if (length(bbox) != 4L || any(!is.finite(bbox)) ||
      bbox[1L] >= bbox[3L] || bbox[2L] >= bbox[4L]) {
    stop("SNODAS bbox must be west, south, east, north.", call. = FALSE)
  }
  connection <- gzfile(data_path, open = "rb")
  on.exit(close(connection), add = TRUE)
  values <- readBin(connection, what = integer(), n = ncol * nrow,
                    size = 2L, signed = TRUE, endian = "big")
  if (length(values) != ncol * nrow) {
    stop("SNODAS grid has an unexpected cell count: ", data_path,
         call. = FALSE)
  }
  first_col <- max(1L, floor((bbox[1L] - xmin) / xres) + 1L)
  last_col <- min(ncol, ceiling((bbox[3L] - xmin) / xres))
  first_row <- max(1L, floor((ymax - bbox[4L]) / yres) + 1L)
  last_row <- min(nrow, ceiling((ymax - bbox[2L]) / yres))
  if (first_col > last_col || first_row > last_row) {
    stop("SNODAS grid does not overlap the configured AOI.", call. = FALSE)
  }
  columns <- seq.int(first_col, last_col)
  rows <- seq.int(first_row, last_row)
  tile <- t(matrix(values, nrow = ncol, ncol = nrow)[columns, rows,
                                                    drop = FALSE])
  tile[tile == nodata] <- NA_integer_
  raster <- terra::rast(
    nrows = length(rows), ncols = length(columns),
    xmin = xmin + (first_col - 1L) * xres,
    xmax = xmin + last_col * xres,
    ymin = ymax - last_row * yres,
    ymax = ymax - (first_row - 1L) * yres,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- as.vector(t(tile)) / 25.4
  terra::time(raster) <- date
  names(raster) <- paste0("snodas_", variable, "_", date)
  list(raster = raster, valid_utc = valid_utc,
       valid_fraction = mean(!is.na(tile)))
}

snodas_repair_period <- function(date) {
  date <- snodas_date(date)
  date >= as.Date("2014-10-09") && date <= as.Date("2019-10-10")
}

snodas_apply_zero_repair <- function(raster, date, repair_mask_path) {
  if (!snodas_repair_period(date)) {
    return(list(raster = raster, mask_md5 = NA_character_,
                repaired_cells = 0L, repaired_zero_cells = 0L))
  }
  if (!file.exists(repair_mask_path)) {
    stop("SNODAS zero-repair mask is required for 2014-10-09 through ",
         "2019-10-10: ", repair_mask_path, call. = FALSE)
  }
  mask <- terra::resample(terra::rast(repair_mask_path), raster,
                          method = "near")
  affected <- as.vector(terra::values(mask)) == 1
  affected[is.na(affected)] <- FALSE
  values <- as.vector(terra::values(raster))
  repaired_zero_cells <- sum(affected & !is.na(values) & values == 0)
  values[affected] <- NA_real_
  terra::values(raster) <- values
  list(raster = raster,
       mask_md5 = unname(tools::md5sum(repair_mask_path)),
       repaired_cells = sum(affected),
       repaired_zero_cells = repaired_zero_cells)
}

process_snodas_date <- function(date, variables = "swe",
                                archive = snodas_archive_path(date),
                                bbox = swc_region$bbox,
                                processed_dir = swc_paths$processed,
                                repair_mask_path = file.path(
                                  swc_paths$raw, "snodas", "reference",
                                  "SNODAS_Zero_Repair_Mask.tif"
                                ),
                                overwrite = FALSE) {
  date <- snodas_date(date)
  variables <- unique(as.character(variables))
  if (!length(variables) || any(!variables %in% swc_snodas$variables)) {
    stop("SNODAS variables must be 'swe' and/or 'depth'.", call. = FALSE)
  }
  if (!file.exists(archive)) stop("Missing SNODAS archive: ", archive, call. = FALSE)
  source_md5 <- unname(tools::md5sum(archive))
  repair_period <- snodas_repair_period(date)
  if (repair_period && !file.exists(repair_mask_path)) {
    stop("SNODAS zero-repair mask is required for this date: ",
         repair_mask_path, call. = FALSE)
  }
  repair_mask_md5 <- if (repair_period) {
    unname(tools::md5sum(repair_mask_path))
  } else NA_character_
  manifest_path <- snodas_manifest_path("processed", processed_dir)
  manifest <- read_snodas_manifest(manifest_path)
  output <- lapply(variables, function(variable) {
    path <- snodas_processed_path(date, variable, processed_dir)
    matching <- if (nrow(manifest) && all(c("date", "variable", "source_md5") %in% names(manifest))) {
      manifest$date == as.character(date) & manifest$variable == variable &
        manifest$source_md5 == source_md5
    } else logical()
    if (repair_period) {
      matching <- matching & if ("repair_mask_md5" %in% names(manifest)) {
        manifest$repair_mask_md5 == repair_mask_md5
      } else FALSE
    }
    if (!overwrite && file.exists(path) && any(matching, na.rm = TRUE)) {
      return(data.frame(date = as.character(date), variable = variable,
                        path = path, refreshed = FALSE))
    }
    parsed <- snodas_raster_from_archive(archive, date, variable, bbox)
    repaired <- snodas_apply_zero_repair(parsed$raster, date, repair_mask_path)
    output_valid_fraction <- mean(!is.na(terra::values(repaired$raster)))
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    temporary <- tempfile("snodas-grid-", tmpdir = dirname(path), fileext = ".tif")
    on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
    terra::writeRaster(repaired$raster, temporary, overwrite = TRUE,
                       datatype = "FLT4S", gdal = c("COMPRESS=DEFLATE"))
    if (!file.copy(temporary, path, overwrite = TRUE)) {
      stop("Could not write SNODAS raster: ", path, call. = FALSE)
    }
    record <- data.frame(
      date = as.character(date), variable = variable,
      aoi_id = swc_snodas$aoi_id, units = "inch",
      valid_utc = parsed$valid_utc,
      source_valid_fraction = parsed$valid_fraction,
      valid_fraction = output_valid_fraction,
      source_path = archive, source_md5 = source_md5,
      repair_mask_md5 = repaired$mask_md5,
      repaired_cells = repaired$repaired_cells,
      repaired_zero_cells = repaired$repaired_zero_cells,
      path = path, bytes = file.info(path)$size,
      md5 = unname(tools::md5sum(path)),
      processed_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
    )
    write_snodas_manifest_row(record, manifest_path, c("date", "variable"))
    data.frame(date = as.character(date), variable = variable,
               path = path, refreshed = TRUE)
  })
  do.call(rbind, output)
}
