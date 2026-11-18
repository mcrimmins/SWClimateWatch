# Small visual trial only: two precipitation dates, before/after labels.
# No downloads, summary updates, publication, or full explorer rebuild.
source("scripts/load-daily-explorer.R")
dates <- as.Date(c("2026-09-30", "2026-10-02"))
directory <- file.path("data", "diagnostics", "daily-explorer", "label-pilot")
dir.create(directory, recursive = TRUE, showWarnings = FALSE)
index <- daily_explorer_index(min(dates), max(dates),
  read_prism_manifest(prism_processed_manifest_path()))
context <- daily_explorer_map_context()
for (i in seq_along(dates)) {
  date <- as.character(dates[[i]])
  row <- index[index$date == date & index$variable == "pcpn", , drop = FALSE]
  if (nrow(row) != 1L) stop("No unique cached precipitation grid for ", date)
  raster <- terra::rast(row$path)[[row$layer]]
  for (halo in c(FALSE, TRUE)) {
    filename <- paste0(date, if (halo) "-halo.png" else "-plain.png")
    daily_explorer_plot(raster, "pcpn", "observed", date,
      context$states, context$cities, file.path(directory, filename),
      context = context, city_label_halo = halo)
  }
  # Also show the trial on these two dates in the existing explorer.
  file.copy(file.path(directory, paste0(date, "-halo.png")),
    file.path(dirname(directory), "maps", paste0(date, "-pcpn-observed.png")),
    overwrite = TRUE)
}
file.copy("scripts/daily-explorer-assets/label-pilot.html",
  file.path(directory, "index.html"), overwrite = TRUE)
message("Label trial: http://127.0.0.1:8766/label-pilot/ (start the existing preview server if needed).")
