# Local station explorer refresh pilot. No public-site render or upload.
# By default, preview only: set SWC_ACIS_EXPLORER_MAX_REQUESTS to opt in
# to RCC-ACIS requests (up to 62 for the full current network).
source(file.path("R", "config.R"))
source(file.path("R", "acis-station-inventory.R"))
source(file.path("R", "acis-station-daily-pilot.R"))
source(file.path("R", "map-southwest.R"))
source(file.path("R", "acis-station-current-prototype.R"))
source(file.path("R", "acis-station-explorer-prototype.R"))
source(file.path("R", "acis-station-explorer-update-pilot.R"))

as_of_text <- Sys.getenv("SWC_ACIS_EXPLORER_AS_OF",
                         as.character(Sys.Date() - 1L))
max_text <- Sys.getenv("SWC_ACIS_EXPLORER_MAX_REQUESTS", "0")
refresh_text <- Sys.getenv("SWC_ACIS_EXPLORER_REFRESH_DAYS", "45")
build_text <- tolower(Sys.getenv("SWC_ACIS_EXPLORER_BUILD", "true"))
if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", as_of_text) ||
    !grepl("^[0-9]+$", max_text) ||
    !grepl("^[0-9]+$", refresh_text) ||
    !build_text %in% c("true", "false")) {
  stop("Invalid station explorer pilot environment options.")
}
swc_station_explorer_pilot <- run_acis_station_explorer_update_pilot(
  as_of = as.Date(as_of_text), max_requests = as.integer(max_text),
  refresh_days = as.integer(refresh_text),
  build_page = identical(build_text, "true"))
if (!is.na(swc_station_explorer_pilot$page))
  source(file.path("scripts", "audit-acis-station-publication.R"))
if (as.integer(max_text) == 0L) {
  message("Preview only; no ACIS requests or files changed.")
} else {
  message(sprintf("ACIS explorer pilot: %d pending after refresh; %d failures.",
                  sum(swc_station_explorer_pilot$after$pending),
                  length(swc_station_explorer_pilot$failures)))
}
