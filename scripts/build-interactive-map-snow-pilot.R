source("scripts/load-snodas-current-site.R")
source("R/interactive-map-pilot.R")
source("R/interactive-map-snow-pilot.R")
interactive_snow_pilot <- build_interactive_map_snow_pilot(
  dates = getOption("swc.interactive.snow.dates", NULL))
print(interactive_snow_pilot$assessment, row.names = FALSE)
message("Snow viewer pilot built locally. No downloads, site staging or publication.")
