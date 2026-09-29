# Render standalone SNODAS pilot maps without changing the site catalog.
# Run from the project root: source("scripts/preview-snodas-pilot.R")

source("scripts/pilot-snodas.R")
source("R/map-reference-layers.R")
source("R/map-southwest.R")

preview_dir <- file.path("data", "diagnostics", "snodas-pilot")
dir.create(preview_dir, recursive = TRUE, showWarnings = FALSE)

preview_date <- as.Date("2025-02-15")
preview_swe_1km <- snodas_pilot_raster(preview_date, "swe")$raster
preview_depth_1km <- snodas_pilot_raster(preview_date, "depth")$raster
preview_swe_2023 <- snodas_pilot_raster(as.Date("2023-03-01"), "swe")$raster
preview_prism_template <- terra::rast(prism_pilot_path)[[1L]]
preview_swe_4km <- terra::resample(
  preview_swe_1km, preview_prism_template, method = "average"
)

preview_states <- southwest_state_boundaries()
preview_counties <- southwest_county_boundaries()
preview_countries <- southwest_country_boundaries()
preview_cities <- southwest_reference_cities()
preview_logo <- southwest_brand_logo_path()

preview_snow_map <- function(raster, title, subtitle, breaks, limits,
                             cities = preview_cities,
                             city_label_fill_alpha = 0.60,
                             tucson_label_southwest = TRUE) {
  southwest_raster_map(
    raster = raster,
    states = preview_states,
    counties = preview_counties,
    countries = preview_countries,
    cities = cities,
    city_label_fill_alpha = city_label_fill_alpha,
    tucson_label_southwest = tucson_label_southwest,
    title = title,
    subtitle = subtitle,
    caption = NULL,
    fill_label = "inches",
    palette = c(
      "#ffffff", "#e3f3f8", "#b4dce9", "#79b9d5", "#3c83b5",
      "#205785", "#122f57"
    ),
    palette_values = c(0, 0.02, 0.07, 0.17, 0.35, 0.65, 1) * diff(limits) + limits[1L],
    limits = limits,
    breaks = breaks,
    labels = as.character(breaks),
    mask_to_states = FALSE,
    scale_type = "continuous"
  )
}

preview_specs <- list(
  list(
    raster = preview_swe_2023,
    file = "snodas-swe-2023-03-01-1km.png",
    title = "Snow water equivalent",
    subtitle = "March 1, 2023 | 06:00 UTC snapshot | 1-km source grid",
    breaks = c(0, 2, 5, 10, 20, 40), limits = c(0, 40),
    legacy_label = TRUE
  ),
  list(
    raster = preview_swe_2023,
    file = "snodas-swe-2023-03-01-tucson-label-test.png",
    title = "Snow water equivalent",
    subtitle = "March 1, 2023 | city-label placement preview",
    breaks = c(0, 2, 5, 10, 20, 40), limits = c(0, 40),
    tucson_label_test = TRUE
  ),
  list(
    raster = preview_swe_1km,
    file = "snodas-swe-2025-02-15-1km.png",
    title = "Snow water equivalent",
    subtitle = "February 15, 2025 | 06:00 UTC snapshot | 1-km source grid",
    breaks = c(0, 1, 2, 4, 8, 12, 20), limits = c(0, 20)
  ),
  list(
    raster = preview_swe_4km,
    file = "snodas-swe-2025-02-15-prism-grid.png",
    title = "Snow water equivalent",
    subtitle = "February 15, 2025 | aggregated to the PRISM grid for comparison",
    breaks = c(0, 1, 2, 4, 8, 12, 20), limits = c(0, 20)
  ),
  list(
    raster = preview_depth_1km,
    file = "snodas-depth-2025-02-15-1km.png",
    title = "Snow depth",
    subtitle = "February 15, 2025 | 06:00 UTC snapshot | 1-km source grid",
    breaks = c(0, 2, 6, 12, 24, 36, 60), limits = c(0, 60)
  )
)

preview_paths <- vapply(preview_specs, function(spec) {
  legacy_label <- isTRUE(spec$legacy_label)
  plot <- preview_snow_map(
    spec$raster, spec$title, spec$subtitle, spec$breaks, spec$limits,
    city_label_fill_alpha = if (legacy_label) 0.76 else 0.60,
    tucson_label_southwest = !legacy_label
  )
  path <- file.path(preview_dir, spec$file)
  save_southwest_map(
    plot, path,
    logo_path = preview_logo,
    footer_text = "Data source: NOAA NOHRSC SNODAS via NSIDC\nPilot map - not a published product"
  )
  message("Wrote ", path)
  path
}, character(1))

invisible(preview_paths)
