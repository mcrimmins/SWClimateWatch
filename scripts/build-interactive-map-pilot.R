# Run from the project root. Cached monthly and recent daily products only.
source("R/interactive-map-pilot.R")
interactive_map_pilot <- build_interactive_map_pilot()
source("scripts/load-daily-explorer.R")
source("R/interactive-map-daily.R")
interactive_map_pilot <- add_interactive_daily_maps(interactive_map_pilot)
source("R/interactive-map-current.R")
interactive_map_pilot <- add_interactive_current_maps(interactive_map_pilot)
print(data.frame(monthly_bundles = sum(!grepl("^(daily|current)-", interactive_map_pilot$summary$layer)),
  daily_bundles = sum(grepl("^daily-", interactive_map_pilot$summary$layer)),
  current_bundles = sum(grepl("^current-", interactive_map_pilot$summary$layer)),
  built = sum(!interactive_map_pilot$summary$reused), reused = sum(interactive_map_pilot$summary$reused),
  daily_through = interactive_map_pilot$manifest$daily$latest_date), row.names = FALSE)
stopifnot(all(interactive_map_pilot$checks$passed))
