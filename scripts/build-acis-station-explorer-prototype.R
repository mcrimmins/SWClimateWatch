# Build an unpublished interactive preview from existing daily station caches.
# No downloads, public-site changes, or remote publishing occur here.
source(file.path("R", "config.R"))
source(file.path("R", "acis-station-inventory.R"))
source(file.path("R", "acis-station-daily-pilot.R"))
source(file.path("R", "map-southwest.R"))
source(file.path("R", "acis-station-current-prototype.R"))
source(file.path("R", "acis-station-explorer-prototype.R"))

as_of_text <- Sys.getenv("SWC_ACIS_EXPLORER_AS_OF", "")
as_of <- if (nzchar(as_of_text)) as.Date(as_of_text) else NULL
if (!is.null(as_of) && is.na(as_of)) {
  stop("SWC_ACIS_EXPLORER_AS_OF must be YYYY-MM-DD.")
}
swc_station_explorer <- build_acis_station_explorer_prototype(as_of = as_of)
source(file.path("scripts", "audit-acis-station-publication.R"))
message("Unpublished station explorer ready: ", swc_station_explorer$page)
message(sprintf("%d station records; %d mapped fixed stations; as of %s.",
                length(unique(swc_station_explorer$rows$uid)),
                length(unique(swc_station_explorer$rows$uid[
                  swc_station_explorer$rows$role == "fixed"])),
                as.character(swc_station_explorer$as_of)))
