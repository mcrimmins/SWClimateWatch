# Explicit manual staging trial. Existing caches only; no network or upload.
source("scripts/load-station-custom-dates-pilot.R")
source("R/station-history-integration.R")
source("R/acis-station-cumulative-pilot.R")
source("R/acis-station-seasonal-pilot.R")
source("R/acis-station-site.R")
validate_station_history_integration()
station_history_stage <- swc_station_beta_stage(source_dir=station_history_integration_root())
message("Staged station history for ",station_history_stage$date,"; ",station_history_stage$stations," records. No upload performed.")
