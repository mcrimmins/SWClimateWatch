# Open the unpublished station explorer over localhost so browser basemap
# requests carry a page Referer. Run after building the prototype.
directory <- file.path("data", "diagnostics", "acis-stations",
                       "station-explorer-prototype")
if (!file.exists(file.path(directory, "index.html"))) {
  stop("Build the station explorer prototype before serving it.")
}
if (!requireNamespace("servr", quietly = TRUE)) {
  stop("Install the R servr package to view the local basemap preview.")
}
swc_station_explorer_server <- servr::httd(
  dir = directory, host = "127.0.0.1", port = 8765L,
  browser = TRUE, daemon = TRUE)
