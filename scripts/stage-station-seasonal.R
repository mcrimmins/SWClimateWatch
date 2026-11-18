# Explicit seasonal staging test; no downloads or publication.
source("scripts/build-station-seasonal-integration.R")
source("R/acis-station-explorer-prototype.R")
source("R/acis-station-site.R")
seasonal_stage <- swc_station_beta_stage(
  source_dir="data/diagnostics/station-seasonal-integration")
message("Staged seasonal Station Conditions for ",seasonal_stage$date,
        ": ",seasonal_stage$stations," station records.")
