# Build verified cached payloads and embed them in the local website only.
source("scripts/build-interactive-map-pilot.R")
source("R/interactive-map-site.R")
interactive_map_site <- stage_interactive_map_site()
