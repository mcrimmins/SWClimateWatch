# Refresh only the unpublished station explorer page and coverage audit from
# its existing station-summary CSV. No ACIS request or historical recalculation.
source(file.path("R", "config.R"))
source(file.path("R", "acis-station-inventory.R"))
source(file.path("R", "map-southwest.R"))
source(file.path("R", "acis-station-explorer-prototype.R"))

preview_dir <- file.path(swc_acis_station_dir, "station-explorer-prototype")
rows_path <- file.path(preview_dir, "station-explorer-data.csv")
if (!file.exists(rows_path)) {
  stop("Build the station explorer once before refreshing its preview.")
}
preview_rows <- read.csv(rows_path, stringsAsFactors = FALSE)
preview_page <- write_acis_station_explorer_prototype(
  preview_rows, output_dir = preview_dir)
source(file.path("scripts", "audit-acis-station-publication.R"))
message("Refreshed unpublished station explorer: ", preview_page)
