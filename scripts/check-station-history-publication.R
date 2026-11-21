# Verify both the staged and rendered viewer before/after a staging publication.
source("R/station-history-integration.R")
source("R/site-cache.R")
for (directory in c("site/stations","site/_site/stations")) {
  print(validate_station_history_integration(directory),row.names=FALSE)
  swc_cache_validate_app(directory)
  swc_cache_validate_app(file.path(directory,"custom-history"))
  message("PASS: historical station data, linked tables and versioned assets: ",directory)
}
