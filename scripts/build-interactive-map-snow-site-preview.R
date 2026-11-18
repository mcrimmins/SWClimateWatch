# Combine verified cached PRISM modes and the reviewed Snow snapshots locally.
# No downloads, automatic Snow update integration, or S3 publication.
source("scripts/stage-cached-interactive-map-site.R")
source("scripts/build-interactive-map-snow-pilot.R")
source("R/interactive-map-site.R")
interactive_snow_site <- stage_interactive_map_site(
  pilot_dir = "data/diagnostics/interactive-map-snow-pilot")
message("Combined local Interactive Maps page is ready to render. Nothing published.")
