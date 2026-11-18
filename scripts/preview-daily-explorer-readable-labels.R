# Review two compact, high-contrast label options; no active maps are replaced.
source("scripts/load-daily-explorer.R")
dates <- as.Date(c("2026-09-30", "2026-10-02"))
directory <- file.path("data", "diagnostics", "daily-explorer", "readable-label-pilot")
dir.create(directory, recursive = TRUE, showWarnings = FALSE)
index <- daily_explorer_index(min(dates), max(dates),
  read_prism_manifest(prism_processed_manifest_path()))
context <- daily_explorer_map_context()
styles <- list(
  halo = list(city_label_style = "text", city_label_halo = TRUE,
    city_label_halo_radius = 0.012, city_label_halo_colour = "#f6f5f0"),
  backing = list(city_label_style = "label", city_label_halo = FALSE)
)
for (i in seq_along(dates)) {
  date <- as.character(dates[[i]])
  row <- index[index$date == date & index$variable == "pcpn", , drop = FALSE]
  if (nrow(row) != 1L) stop("No unique cached precipitation grid for ", date)
  raster <- terra::rast(row$path)[[row$layer]]
  for (style in names(styles)) {
    do.call(daily_explorer_plot, c(list(raster = raster, variable = "pcpn",
      view = "observed", date = date, states = context$states, cities = context$cities,
      path = file.path(directory, paste0(date, "-", style, ".png")), context = context,
      city_label_size = 2.05, city_label_fontface = "bold", city_label_colour = "#202b30"),
      styles[[style]]))
  }
}
file.copy("scripts/daily-explorer-assets/readable-label-pilot.html",
  file.path(directory, "index.html"), overwrite = TRUE)
message("Readable-label options: http://127.0.0.1:8766/readable-label-pilot/")
