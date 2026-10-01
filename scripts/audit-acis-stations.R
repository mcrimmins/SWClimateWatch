# Run from the project root. This is a research inventory, not a site update.
source(file.path("R", "config.R"))
source(file.path("R", "acis-station-inventory.R"))

max_stations <- as.integer(Sys.getenv("SWC_ACIS_MAX_STATIONS", "5"))
if (is.na(max_stations) || max_stations < 0L) {
  stop("SWC_ACIS_MAX_STATIONS must be a nonnegative integer.", call. = FALSE)
}
refresh_metadata <- tolower(Sys.getenv("SWC_ACIS_REFRESH_METADATA", "false")) == "true"

swc_acis_inventory_result <- run_acis_station_inventory(
  max_stations = max_stations,
  refresh_metadata = refresh_metadata
)

message(sprintf("ACIS station audit: %d audited; %d pending; %d failures.",
                swc_acis_inventory_result$audited_this_run,
                swc_acis_inventory_result$pending,
                length(swc_acis_inventory_result$failures)))
message("Shortlist: ", file.path(swc_acis_inventory_result$directory,
                                      "station-shortlist.csv"))
