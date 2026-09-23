# Compare scale-aware tribal-area boundary treatments on one existing map.

source(file.path("R", "config.R"))
source(file.path("R", "acis-prism.R"))
source(file.path("R", "process-prism.R"))
source(file.path("R", "build-prism-climatology.R"))
source(file.path("R", "prism-percentile-rank.R"))
source(file.path("R", "map-reference-layers.R"))
source(file.path("R", "map-product-scales.R"))
source(file.path("R", "map-southwest.R"))
source(file.path("R", "build-current-prism-maps.R"))
source(file.path("R", "build-current-prism-precipitation-maps.R"))
source(file.path("R", "prism-water-year-cache.R"))
source(file.path("R", "build-current-prism-water-year-maps.R"))

count_polygon_components <- function(x) {
  nrow(suppressWarnings(sf::st_cast(sf::st_make_valid(x), "POLYGON")))
}

total_dir <- file.path(
  swc_paths$processed, "prism", swc_prism$aoi_id,
  "daily", "water-year", "pcpn", "total"
)
total_paths <- list.files(
  total_dir,
  pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}\\.tif$",
  full.names = TRUE
)
if (length(total_paths) == 0L) {
  stop("No processed water-year total raster is available.", call. = FALSE)
}
dates <- as.Date(tools::file_path_sans_ext(basename(total_paths)))
date <- max(dates)
raster <- terra::rast(total_paths[[which.max(dates)]])
terra::time(raster) <- date

tribal_full <- sf::st_read(
  file.path(
    southwest_reference_directory(),
    "tribal-areas-census-2025-full.gpkg"
  ),
  quiet = TRUE
)
tribal_10 <- generalize_southwest_tribal_boundaries(tribal_full, 10)
tribal_25 <- generalize_southwest_tribal_boundaries(tribal_full, 25)
variants <- list(
  `full-detail` = tribal_full,
  `10-km2` = tribal_10,
  `25-km2` = tribal_25
)
descriptions <- c(
  `full-detail` = "Full Census component detail",
  `10-km2` = "Largest component per entity + components at least 10 km2",
  `25-km2` = "Largest component per entity + components at least 25 km2"
)

states <- southwest_state_boundaries()
counties <- southwest_county_boundaries()
countries <- southwest_country_boundaries()
rivers <- southwest_major_rivers(required = TRUE)
cities <- southwest_reference_cities()
scale <- prism_water_year_total_scale()
water_year <- prism_water_year(date)
period <- format_prism_map_period(prism_water_year_start(date), date)
output_dir <- file.path(swc_paths$maps, "design-comparisons", "tribal-boundaries")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

records <- vector("list", length(variants))
for (index in seq_along(variants)) {
  variant <- names(variants)[[index]]
  tribal <- variants[[variant]]
  plot <- southwest_raster_map(
    raster = raster,
    states = states,
    title = paste0("Water year ", water_year, " precipitation to date"),
    subtitle = paste0(period, " | ", descriptions[[variant]]),
    caption = NULL,
    fill_label = "Precipitation (inches)",
    palette = scale$palette,
    palette_values = scale$values,
    limits = scale$limits,
    breaks = scale$breaks,
    labels = scale$labels,
    counties = counties,
    countries = countries,
    tribal_areas = tribal,
    rivers = rivers,
    cities = cities,
    mask_to_states = FALSE,
    county_colour = "#34434b",
    county_linewidth = 0.14,
    county_alpha = 0.3,
    county_linetype = "solid",
    tribal_colour = "#684b70",
    tribal_linewidth = 0.38,
    tribal_alpha = 0.72,
    tribal_linetype = "longdash"
  )
  output_path <- file.path(
    output_dir,
    paste0("tribal-boundaries-", variant, ".png")
  )
  save_southwest_map(
    plot,
    output_path,
    logo_path = southwest_brand_logo_path(),
    footer_text = prism_precipitation_footer_text(
      prism_water_year_start(date), date
    )
  )
  records[[index]] <- data.frame(
    variant = variant,
    tribal_entities = length(unique(tribal[["NAME"]])),
    polygon_parts = count_polygon_components(tribal),
    path = output_path,
    stringsAsFactors = FALSE
  )
}

comparison <- do.call(rbind, records)
print(comparison, row.names = FALSE)

comparison_sheet <- magick::image_read(comparison[["path"]])
comparison_sheet <- magick::image_resize(comparison_sheet, "900x")
comparison_sheet <- magick::image_append(comparison_sheet, stack = FALSE)
comparison_sheet_path <- file.path(output_dir, "tribal-boundary-comparison.png")
magick::image_write(comparison_sheet, comparison_sheet_path, format = "png")
message("Wrote comparison sheet: ", comparison_sheet_path)
