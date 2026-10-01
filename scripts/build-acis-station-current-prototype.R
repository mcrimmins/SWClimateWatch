# Research-only station prototype. Run from the project root. Nothing is
# added to the public site or daily publishing pipeline.
source(file.path("R", "config.R"))
source(file.path("R", "acis-station-inventory.R"))
source(file.path("R", "acis-station-daily-pilot.R"))
source(file.path("R", "map-southwest.R"))
source(file.path("R", "acis-station-current-prototype.R"))

max_stations <- as.integer(Sys.getenv("SWC_ACIS_STATION_MAX", "5"))
as_of_text <- Sys.getenv("SWC_ACIS_STATION_AS_OF", as.character(Sys.Date() - 1L))
as_of <- as.Date(as_of_text)
if (is.na(max_stations) || max_stations < 0L || is.na(as_of)) {
  stop("Set a nonnegative SWC_ACIS_STATION_MAX and YYYY-MM-DD SWC_ACIS_STATION_AS_OF.")
}
swc_acis_station_prototype <- run_acis_station_current_prototype(
  max_stations = max_stations, as_of = as_of)
if (!is.na(swc_acis_station_prototype$page)) {
  message("Station prototype ready: ", swc_acis_station_prototype$page)
}
