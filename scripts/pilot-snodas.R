# Small, read-only pilot of two locally downloaded SNODAS daily archives.
# Run from the project root: source("scripts/pilot-snodas.R")
# Daily tar files belong in data/raw/snodas/pilot/ and are not part of the site.

source("R/config.R")
stopifnot(requireNamespace("terra", quietly = TRUE))

snodas_pilot_dir <- file.path(swc_paths$raw, "snodas", "pilot")
snodas_pilot_dates <- as.Date(c("2023-03-01", "2025-02-15", "2026-09-22"))

snodas_header <- function(path) {
  lines <- readLines(gzfile(path), warn = FALSE)
  keys <- trimws(sub(":.*$", "", lines))
  values <- trimws(sub("^[^:]*:", "", lines))
  stats::setNames(values, keys)
}

snodas_pilot_raster <- function(date, variable = c("swe", "depth"),
                                bbox = swc_region$bbox) {
  variable <- match.arg(variable)
  date <- as.Date(date)
  stamp <- format(date, "%Y%m%d")
  directory <- file.path(snodas_pilot_dir, stamp)
  archive <- file.path(snodas_pilot_dir, paste0("SNODAS_", stamp, ".tar"))
  code <- if (variable == "swe") "11034" else "11036"

  if (!file.exists(archive)) {
    stop("Missing SNODAS pilot archive: ", archive, call. = FALSE)
  }
  if (!dir.exists(directory)) dir.create(directory, recursive = TRUE)
  members <- utils::untar(archive, list = TRUE)
  selected <- grep(paste0("ssmv", code, ".*[.](dat|txt)[.]gz$"),
                   members, value = TRUE)
  if (length(selected) != 2L) {
    stop("Expected one data file and one header for ", variable, " on ", date,
         call. = FALSE)
  }
  if (!all(file.exists(file.path(directory, selected)))) {
    utils::untar(archive, files = selected, exdir = directory)
  }
  data_path <- file.path(directory, grep("[.]dat[.]gz$", selected, value = TRUE))
  header_path <- file.path(directory, grep("[.]txt[.]gz$", selected, value = TRUE))
  header <- snodas_header(header_path)

  ncol <- as.integer(header[["Number of columns"]])
  nrow <- as.integer(header[["Number of rows"]])
  xmin <- as.numeric(header[["Minimum x-axis coordinate"]])
  ymax <- as.numeric(header[["Maximum y-axis coordinate"]])
  xres <- as.numeric(header[["X-axis resolution"]])
  yres <- as.numeric(header[["Y-axis resolution"]])
  nodata <- as.integer(as.numeric(header[["No data value"]]))
  valid_utc <- sprintf(
    "%04d-%02d-%02d %02d:%02d UTC",
    as.integer(header[["Start year"]]), as.integer(header[["Start month"]]),
    as.integer(header[["Start day"]]), as.integer(header[["Start hour"]]),
    as.integer(header[["Start minute"]])
  )
  if (!identical(substr(valid_utc, 1L, 10L), as.character(date)) ||
      !identical(header[["Data units"]], "Meters / 1000.000000") ||
      ncol < 1L || nrow < 1L || xres <= 0 || yres <= 0) {
    stop("Unexpected SNODAS header metadata in ", header_path, call. = FALSE)
  }

  connection <- gzfile(data_path, open = "rb")
  on.exit(close(connection), add = TRUE)
  values <- readBin(connection, what = integer(), n = ncol * nrow,
                    size = 2L, signed = TRUE, endian = "big")
  if (length(values) != ncol * nrow) {
    stop("SNODAS grid has an unexpected cell count: ", data_path, call. = FALSE)
  }

  # SNODAS stores a north-to-south, row-major grid. Extract only this site's
  # small AOI before creating a terra raster. Integer values are millimeters.
  first_col <- max(1L, floor((bbox[["west"]] - xmin) / xres) + 1L)
  last_col <- min(ncol, ceiling((bbox[["east"]] - xmin) / xres))
  first_row <- max(1L, floor((ymax - bbox[["north"]]) / yres) + 1L)
  last_row <- min(nrow, ceiling((ymax - bbox[["south"]]) / yres))
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
  names(raster) <- paste0("snodas_", variable, "_", date)

  list(raster = raster, valid_utc = valid_utc, raw_values = tile,
       compressed_bytes = file.info(archive)$size)
}

snodas_pilot_rows <- lapply(snodas_pilot_dates, function(date) {
  lapply(c("swe", "depth"), function(variable) {
    result <- snodas_pilot_raster(date, variable)
    values <- as.vector(result$raw_values)
    valid <- !is.na(values)
    data.frame(
      date = as.character(date), variable = variable,
      valid_utc = result$valid_utc,
      tar_mb = round(result$compressed_bytes / 1024^2, 2),
      columns = terra::ncol(result$raster), rows = terra::nrow(result$raster),
      resolution_degrees = terra::res(result$raster)[[1L]],
      valid_fraction = mean(valid),
      snow_fraction_of_valid = mean(values[valid] > 0L),
      max_inches = if (any(valid)) max(values[valid]) / 25.4 else NA_real_,
      high_outlier_cells = sum(values[valid] >= 32767L),
      stringsAsFactors = FALSE
    )
  })
})
snodas_pilot_summary <- do.call(rbind, unlist(snodas_pilot_rows, recursive = FALSE))
print(snodas_pilot_summary, row.names = FALSE)

prism_pilot_path <- file.path(
  swc_paths$processed, "prism", swc_prism$aoi_id, "daily", "recent",
  "pcpn", "2026-09-22.tif"
)
if (file.exists(prism_pilot_path)) {
  prism_pilot_raster <- terra::rast(prism_pilot_path)
  snodas_pilot_swe <- snodas_pilot_raster(as.Date("2026-09-22"), "swe")$raster
  cat("PRISM resolution (degrees):", paste(terra::res(prism_pilot_raster), collapse = ", "), "\n")
  cat("SNODAS resolution (degrees):", paste(terra::res(snodas_pilot_swe), collapse = ", "), "\n")
  cat("Both grids use geographic coordinates; resampling is needed before pixelwise comparison.\n")
}
