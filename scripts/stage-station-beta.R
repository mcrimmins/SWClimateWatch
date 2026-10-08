# Stage the already screened local explorer for Quarto, without ACIS requests
# or remote publishing. Run from the project root.
source(file.path("R", "config.R"))
source(file.path("R", "acis-station-inventory.R"))
source(file.path("R", "acis-station-explorer-prototype.R"))
source(file.path("R", "acis-station-site.R"))
station_beta <- swc_station_beta_stage()
message(sprintf("Staged station page for %s: %d stations, %d mapped.",
                station_beta$date, station_beta$stations, station_beta$mapped))
