# Refresh only cumulative plots at the existing station page date, from caches.
# No station requests, summary/rank rebuild, Quarto render, or publication.
source(file.path("R", "config.R"))
source(file.path("R", "acis-station-inventory.R"))
source(file.path("R", "acis-station-current-prototype.R"))
source(file.path("R", "acis-station-cumulative-pilot.R"))

cumulative_preview_dir <- file.path(swc_acis_station_dir, "station-explorer-prototype")
cumulative_rows <- read.csv(file.path(cumulative_preview_dir, "station-explorer-data.csv"))
cumulative_date <- unique(cumulative_rows$as_of)
if (length(cumulative_date) != 1L || is.na(as.Date(cumulative_date))) stop("Invalid station page date.")
cumulative_stations <- acis_reference_station_table()
cumulative_caches <- lapply(cumulative_stations$uid, function(uid)
  acis_station_read_daily_cache(acis_station_daily_cache_path(uid), uid))
swc_station_cumulative <- write_acis_station_cumulative_site(
  cumulative_stations, cumulative_caches, as.Date(cumulative_date), cumulative_preview_dir)
validate_acis_station_cumulative_site(file.path(cumulative_preview_dir, "cumulative"),
  unique(cumulative_rows$uid), cumulative_date)
