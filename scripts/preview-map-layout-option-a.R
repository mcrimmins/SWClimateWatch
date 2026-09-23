# Render two layout samples from existing processed grids. No data downloads or
# published map files are changed.
source(file.path("R", "config.R"))
source(file.path("R", "acis-prism.R"))
source(file.path("R", "process-prism.R"))
source(file.path("R", "map-reference-layers.R"))
source(file.path("R", "map-product-scales.R"))
source(file.path("R", "map-product-site.R"))
source(file.path("R", "map-southwest.R"))
source(file.path("R", "build-current-prism-maps.R"))
source(file.path("R", "build-current-prism-precipitation-maps.R"))
source(file.path("R", "prism-rolling-temperature-percentile.R"))

output_dir <- file.path("data", "diagnostics", "map-layout-option-a")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

render_sample <- function(plot, path, footer) {
  save_southwest_map(
    plot,
    path,
    logo_path = southwest_brand_logo_path(),
    footer_text = footer
  )
  message("Wrote layout sample: ", path)
}

temperature_date <- latest_common_prism_date("tmean")
temperature_path <- prism_rolling_temperature_percentile_output_path(
  7L, temperature_date, swc_prism$aoi_id, swc_paths$processed
)
if (!file.exists(temperature_path)) {
  stop("Missing 7-day mean-temperature rank grid: ", temperature_path)
}
temperature_plot <- build_prism_rolling_temperature_percentile_map(
  terra::rast(temperature_path), 7L, temperature_date
)
render_sample(
  temperature_plot,
  file.path(output_dir, "temperature-percentile-7day-option-a.png"),
  prism_map_footer_text()
)

precipitation_date <- latest_common_prism_date("pcpn")
precipitation_path <- prism_accumulation_output_path(
  30L, precipitation_date, swc_prism$aoi_id, swc_paths$processed
)
if (!file.exists(precipitation_path)) {
  stop("Missing 30-day precipitation total grid: ", precipitation_path)
}
precipitation_plot <- build_prism_accumulation_map(
  terra::rast(precipitation_path), 30L, precipitation_date
)
render_sample(
  precipitation_plot,
  file.path(output_dir, "precipitation-total-30day-option-a.png"),
  prism_precipitation_footer_text(precipitation_date - 29L, precipitation_date)
)
