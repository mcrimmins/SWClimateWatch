# Build local, on-demand station detail files from existing daily caches.
# This does not request ACIS data, recalculate historical ranks, or publish.
source(file.path("R", "config.R"))
source(file.path("R", "acis-station-inventory.R"))
source(file.path("R", "acis-station-daily-pilot.R"))
source(file.path("R", "map-southwest.R"))
source(file.path("R", "acis-station-current-prototype.R"))
source(file.path("R", "acis-station-explorer-prototype.R"))

detail_preview_dir <- file.path(swc_acis_station_dir, "station-explorer-prototype")
detail_rows_path <- file.path(detail_preview_dir, "station-explorer-data.csv")
if (!file.exists(detail_rows_path)) {
  stop("Build the station explorer before generating its detail files.")
}
detail_rows <- read.csv(detail_rows_path, stringsAsFactors = FALSE)
detail_date <- unique(detail_rows$as_of)
if (length(detail_date) != 1L || is.na(as.Date(detail_date))) {
  stop("The station explorer has no single valid page date.")
}
detail_stations <- acis_reference_station_table()
detail_caches <- lapply(detail_stations$uid, function(uid) {
  acis_station_read_daily_cache(acis_station_daily_cache_path(uid), uid)
})
detail_paths <- write_acis_station_explorer_details(
  detail_stations, detail_caches, as.Date(detail_date), detail_preview_dir)
message(length(detail_paths), " unpublished station detail files ready for ",
        detail_date, ".")
