# Conservative, in-memory screening before SNODAS historical comparisons.
# Original processed SWE/depth GeoTIFFs and their manifests remain unchanged.

screen_snodas_analysis_pair <- function(swe, depth,
                                        tolerance_inches = 1e-6) {
  if (!inherits(swe, "SpatRaster") ||
      !inherits(depth, "SpatRaster") ||
      terra::nlyr(swe) != 1L || terra::nlyr(depth) != 1L ||
      !terra::compareGeom(swe, depth, stopOnError = FALSE)) {
    stop("SNODAS SWE and depth must be single layers on the same grid.",
         call. = FALSE)
  }
  swe_time <- terra::time(swe)
  depth_time <- terra::time(depth)
  if (length(swe_time) != 1L || length(depth_time) != 1L ||
      is.na(swe_time) || is.na(depth_time) ||
      as.Date(swe_time) != as.Date(depth_time)) {
    stop("SNODAS SWE and depth must have the same daily date.",
         call. = FALSE)
  }
  if (!is.numeric(tolerance_inches) || length(tolerance_inches) != 1L ||
      !is.finite(tolerance_inches) || tolerance_inches < 0) {
    stop("`tolerance_inches` must be a nonnegative finite number.",
         call. = FALSE)
  }
  swe_values <- as.vector(terra::values(swe))
  depth_values <- as.vector(terra::values(depth))
  swe_valid <- is.finite(swe_values)
  depth_valid <- is.finite(depth_values)
  one_sided_missing <- xor(swe_valid, depth_valid)
  both_valid <- swe_valid & depth_valid
  swe_exceeds_depth <- both_valid &
    swe_values > depth_values + tolerance_inches
  invalid_range <- (swe_valid &
    (swe_values < 0 | swe_values >= 32767 / 25.4)) |
    (depth_valid &
       (depth_values < 0 | depth_values >= 32767 / 25.4))
  exclude <- one_sided_missing | swe_exceeds_depth | invalid_range
  if (any(exclude)) {
    swe_values[exclude] <- NA_real_
    depth_values[exclude] <- NA_real_
    terra::values(swe) <- swe_values
    terra::values(depth) <- depth_values
  }
  list(
    swe = swe, depth = depth,
    summary = data.frame(
      date = as.character(as.Date(swe_time)),
      one_sided_missing_cells = sum(one_sided_missing),
      swe_exceeds_depth_cells = sum(swe_exceeds_depth),
      invalid_range_cells = sum(invalid_range),
      excluded_cells = sum(exclude)
    )
  )
}
