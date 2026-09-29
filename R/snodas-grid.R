# Fixed post-2013 masked SNODAS grid for reproducible historical comparisons.
# Source config.R and snodas.R first. Native daily GeoTIFFs remain unchanged.

snodas_common_grid <- function(bbox = swc_region$bbox,
                               config = swc_snodas) {
  bbox <- as.numeric(bbox)
  if (length(bbox) != 4L || any(!is.finite(bbox)) ||
      bbox[1L] >= bbox[3L] || bbox[2L] >= bbox[4L]) {
    stop("SNODAS bbox must be west, south, east, north.", call. = FALSE)
  }
  origin <- config$common_grid_origin
  resolution <- config$common_grid_resolution
  if (length(origin) != 2L || any(!is.finite(origin)) ||
      length(resolution) != 1L || !is.finite(resolution) ||
      resolution <= 0) {
    stop("Invalid post-2013 SNODAS grid configuration.", call. = FALSE)
  }
  # Keep only cells whose centers fall inside the requested AOI. The usual
  # outward crop includes opposite one-cell fringes before versus after 2013,
  # which would otherwise create low-sample strips in a climatology.
  first_col <- ceiling((bbox[1L] - origin[["xmin"]]) / resolution + 0.5 - 1e-8)
  last_col <- floor((bbox[3L] - origin[["xmin"]]) / resolution + 0.5 + 1e-8)
  first_row <- ceiling((origin[["ymax"]] - bbox[4L]) / resolution + 0.5 - 1e-8)
  last_row <- floor((origin[["ymax"]] - bbox[2L]) / resolution + 0.5 + 1e-8)
  if (first_col > last_col || first_row > last_row) {
    stop("SNODAS common grid does not overlap the AOI.", call. = FALSE)
  }
  terra::rast(
    nrows = last_row - first_row + 1L,
    ncols = last_col - first_col + 1L,
    xmin = origin[["xmin"]] + (first_col - 1L) * resolution,
    xmax = origin[["xmin"]] + last_col * resolution,
    ymin = origin[["ymax"]] - last_row * resolution,
    ymax = origin[["ymax"]] - (first_row - 1L) * resolution,
    crs = "EPSG:4326"
  )
}

snodas_grid_era <- function(date) {
  if (snodas_date(date) < as.Date("2013-10-01")) "pre-2013" else "post-2013"
}

snodas_align_common_grid <- function(raster,
                                     template = snodas_common_grid()) {
  if (!inherits(raster, "SpatRaster") || terra::nlyr(raster) != 1L ||
      !inherits(template, "SpatRaster") || terra::nlyr(template) != 1L) {
    stop("Expected one-layer source and template rasters.", call. = FALSE)
  }
  if (!terra::same.crs(raster, template) ||
      any(abs(terra::res(raster) - terra::res(template)) > 1e-7)) {
    stop("SNODAS source has an unexpected CRS or cell resolution.", call. = FALSE)
  }
  if (terra::compareGeom(raster, template, stopOnError = FALSE)) {
    return(raster)
  }
  source_extent <- terra::ext(raster)
  target_extent <- terra::ext(template)
  shift_x <- (source_extent$xmin - target_extent$xmin) / terra::res(template)[1L]
  shift_y <- (source_extent$ymax - target_extent$ymax) / terra::res(template)[2L]
  fractional_shift <- abs(c(shift_x, shift_y) - round(c(shift_x, shift_y)))
  if (any(fractional_shift > 0.12) ||
      any(abs(c(shift_x, shift_y)) > 2)) {
    stop("SNODAS grid displacement exceeds the expected 2013 shift.",
         call. = FALSE)
  }
  aligned <- terra::resample(raster, template, method = "near")
  names(aligned) <- names(raster)
  source_time <- terra::time(raster)
  if (length(source_time) == 1L && !is.na(source_time)) {
    terra::time(aligned) <- source_time
  }
  aligned
}

snodas_alignment_metrics <- function(source, aligned,
                                     template = snodas_common_grid(),
                                     date) {
  date <- snodas_date(date)
  if (!terra::compareGeom(aligned, template, stopOnError = FALSE)) {
    stop("Aligned SNODAS raster does not match the common grid.", call. = FALSE)
  }
  original <- as.vector(terra::values(source))
  output <- as.vector(terra::values(aligned))
  roundtrip <- terra::resample(aligned, source, method = "near")
  recovered <- as.vector(terra::values(roundtrip))
  common <- is.finite(original) & is.finite(recovered)
  source_extent <- terra::ext(source)
  target_extent <- terra::ext(template)
  data.frame(
    date = as.character(date), era = snodas_grid_era(date),
    source_rows = terra::nrow(source), source_cols = terra::ncol(source),
    aligned_rows = terra::nrow(aligned), aligned_cols = terra::ncol(aligned),
    source_xmin = unname(source_extent$xmin),
    source_ymax = unname(source_extent$ymax),
    target_xmin = unname(target_extent$xmin),
    target_ymax = unname(target_extent$ymax),
    source_valid = sum(is.finite(original)),
    aligned_valid = sum(is.finite(output)),
    source_cells_lost_on_roundtrip = sum(is.finite(original) & !is.finite(recovered)),
    max_abs_roundtrip_difference_inches = if (any(common)) {
      max(abs(original[common] - recovered[common]))
    } else NA_real_,
    source_max_inches = if (any(is.finite(original))) {
      max(original, na.rm = TRUE)
    } else NA_real_,
    aligned_max_inches = if (any(is.finite(output))) {
      max(output, na.rm = TRUE)
    } else NA_real_,
    stringsAsFactors = FALSE
  )
}
