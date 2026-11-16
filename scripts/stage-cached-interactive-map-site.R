# VM staging preparation only. No climate downloads or S3 changes.
source("R/interactive-map-pilot.R")
source("scripts/load-daily-explorer.R")
source("R/interactive-map-daily.R")
source("R/interactive-map-current.R")
source("R/interactive-map-site.R")
source("R/interactive-map-staging.R")
interactive_staging <- stage_cached_interactive_map_site()
