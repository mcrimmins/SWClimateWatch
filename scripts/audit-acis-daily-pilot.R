# Research-only daily station review; does not update or publish the site.
source(file.path("R", "config.R"))
source(file.path("R", "acis-station-inventory.R"))
source(file.path("R", "acis-station-daily-pilot.R"))

max_stations <- as.integer(Sys.getenv("SWC_ACIS_DAILY_PILOT_MAX", "2"))
if (is.na(max_stations) || max_stations < 0L) {
  stop("SWC_ACIS_DAILY_PILOT_MAX must be a nonnegative integer.", call. = FALSE)
}

swc_acis_daily_pilot_result <- run_acis_station_daily_pilot(max_stations)
message(sprintf("Daily pilot: %d audited; %d pending; %d failures.",
                swc_acis_daily_pilot_result$audited_this_run,
                swc_acis_daily_pilot_result$pending,
                length(swc_acis_daily_pilot_result$failures)))
message("Review: ", file.path(swc_acis_daily_pilot_result$directory, "summary.csv"))
