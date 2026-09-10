# Shared configuration for Southwest Climate Watch analyses.

swc_packages <- c(
  "terra", "sf", "ggplot2", "dplyr", "lubridate", "maps",
  "httr2", "jsonlite", "digest"
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
  maps = file.path("maps", "generated"),
  pages = "pages",
  site = "_site"
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
  variables = c("maxt", "mint", "pcpn"),
  native_units = c(maxt = "degreeF", mint = "degreeF", pcpn = "inch"),
  plausible_ranges = list(
    maxt = c(-150, 150),
    mint = c(-150, 150),
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
  # PRISM normally revises daily grids after roughly 1 day, 5 days, and then
  # monthly through six months. These ages keep the local recent cache fresh.
  revision_ages = c(2L, 6L, 31L, 61L, 92L, 123L, 153L, 184L),
  bootstrap_chunk = "month",
  request_timeout_seconds = 180L,
  max_requests_per_run = 100L,
  request_delay_seconds = 1,
  request_jitter_seconds = 0.5
)

initialize_swc_directories <- function(paths = swc_paths) {
  directories <- unname(unlist(paths[c("raw", "processed", "maps")]))
  invisible(vapply(directories, dir.create, logical(1), recursive = TRUE, showWarnings = FALSE))
}
