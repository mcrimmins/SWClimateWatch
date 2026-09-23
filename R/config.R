# Shared configuration for Southwest Climate Watch analyses.

swc_packages <- c(
  "terra", "sf", "ggplot2", "ggrepel", "magick", "dplyr", "lubridate", "maps",
  "httr2", "jsonlite", "digest", "yaml"
)

check_swc_packages <- function(packages = swc_packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0L) {
    stop(
      "Install required R packages before running the workflow: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# All paths are resolved from the repository root. Run scripts from that root.
swc_paths <- list(
  raw = file.path("data", "raw"),
  processed = file.path("data", "processed"),
  maps = file.path("site", "maps", "generated"),
  pages = file.path("site", "pages"),
  site_source = "site",
  site = file.path("site", "_site")
)

swc_region <- list(
  states = c("Arizona", "New Mexico"),
  abbreviations = c("AZ", "NM"),
  # This fixed box extends 0.5 degrees beyond the AZ-NM analysis footprint on
  # every side. The downloaded rectangle is cropped or masked during processing.
  bbox = c(west = -115.6, south = 30.75, east = -102.45, north = 37.6),
  geographic_crs = "EPSG:4326",
  map_crs = "EPSG:5070"
)

swc_prism <- list(
  aoi_id = "az-nm-pad050",
  daily_endpoint = "https://grid2.rcc-acis.org/GridData",
  monthly_endpoint = "https://data.rcc-acis.org/GridData",
  daily_grid = "prism",
  monthly_grid = "21",
  # `variables` are requested from RCC-ACIS. `tmean` is derived locally from
  # maxt and mint so it never adds API traffic.
  variables = c("maxt", "mint", "pcpn"),
  derived_variables = "tmean",
  temperature_variables = c("maxt", "mint", "tmean"),
  native_units = c(
    maxt = "degreeF", mint = "degreeF", tmean = "degreeF", pcpn = "inch"
  ),
  plausible_ranges = list(
    maxt = c(-150, 150),
    mint = c(-150, 150),
    tmean = c(-150, 150),
    pcpn = c(0, 100)
  ),
  archive_start = as.Date("1981-01-01"),
  archive_end = as.Date("2025-12-31"),
  normal_start = as.Date("1991-01-01"),
  normal_end = as.Date("2020-12-31"),
  percentile_start = as.Date("1991-01-01"),
  percentile_end = as.Date("2020-12-31"),
  long_percentile_start = as.Date("1981-01-01"),
  long_percentile_end = as.Date("2020-12-31"),
  centered_window_days = 5L,
  quantile_type = 8L,
  wet_day_threshold_inches = 0.04,
  # Allows values stored as float32 just below an exact decimal threshold to
  # retain their intended wet/dry classification.
  wet_day_storage_tolerance_inches = 1e-7,
  percent_normal_minimum_inches = 0.10,
  # PRISM normally revises daily grids after roughly 1 day, 5 days, and then
  # monthly through six months. The 215-day check follows the approximate
  # six-month window so a late final batch is not missed by the 184-day check.
  revision_ages = c(2L, 6L, 31L, 61L, 92L, 123L, 153L, 184L, 215L),
  bootstrap_chunk = "month",
  request_timeout_seconds = 180L,
  max_requests_per_run = 100L,
  request_delay_seconds = 1,
  request_jitter_seconds = 0.5
)

prism_is_wet_day <- function(
    values,
    threshold = swc_prism$wet_day_threshold_inches,
    tolerance = swc_prism$wet_day_storage_tolerance_inches) {
  values >= (threshold - tolerance)
}

initialize_swc_directories <- function(paths = swc_paths) {
  directories <- unname(unlist(paths[c("raw", "processed", "maps")]))
  invisible(vapply(directories, dir.create, logical(1), recursive = TRUE, showWarnings = FALSE))
}
