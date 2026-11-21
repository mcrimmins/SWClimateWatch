# Simulations use copies of three representative caches/payloads, never live data.
source("scripts/load-station-custom-dates-pilot.R")
stations <- acis_reference_station_table()
catalog <- jsonlite::read_json(file.path(station_custom_pilot_root(), "catalog.json"), simplifyVector = TRUE)$stations
ordered <- catalog[order(catalog$years), ]
uids <- unique(ordered$uid[c(1L, ceiling(nrow(ordered)/2), nrow(ordered))])
stations <- stations[match(uids, stations$uid), ]
base <- "data/diagnostics/station-custom-dates-update-benchmark"
dir.create(base, recursive = TRUE, showWarnings = FALSE)
cache_dir <- file.path(base, "cache"); output <- file.path(base, "preview")
dir.create(cache_dir, showWarnings = FALSE); dir.create(output, showWarnings = FALSE)
for (uid in uids) {
  file.copy(acis_station_daily_cache_path(uid), acis_station_daily_cache_path(uid, cache_dir), overwrite = TRUE)
  from <- file.path(station_custom_pilot_root(), "history", uid)
  files <- c(list.files(from, pattern = "[.]json$", full.names = TRUE), file.path(from, "build.rds"))
  to <- file.path(output, "history", uid); dir.create(to, recursive = TRUE, showWarnings = FALSE)
  file.copy(files, to, overwrite = TRUE)
}
baseline <- build_station_custom_dates_pilot(stations, cache_dir, output)$summary
for (uid in uids) {
  path <- acis_station_daily_cache_path(uid, cache_dir); x <- readRDS(path)
  extra <- x$daily[x$daily$date == x$as_of, ]; extra <- extra[match(c("pcpn", "maxt", "mint"), extra$variable), ]
  extra$date <- x$as_of + 1; extra$numeric_value <- NA_real_; extra$observed <- FALSE
  extra$flag <- ""; extra$trace <- FALSE; extra$accumulated <- FALSE; extra$source <- "SIMULATED missing day"
  x$daily <- rbind(x$daily, extra); x$as_of <- x$as_of + 1; saveRDS(x, path)
}
append <- build_station_custom_dates_pilot(stations, cache_dir, output)$summary
stopifnot(append$built == length(uids))
for (uid in uids) {
  path <- acis_station_daily_cache_path(uid, cache_dir); x <- readRDS(path)
  eligible <- which(x$daily$variable == "pcpn" & x$daily$observed & is.finite(x$daily$numeric_value) &
    !x$daily$accumulated & x$daily$flag %in% c("", "T"))
  i <- eligible[1L]; stopifnot(length(i) == 1L, !is.na(i))
  x$daily$numeric_value[i] <- x$daily$numeric_value[i] + .01
  x$daily$trace[i] <- FALSE; x$daily$flag[i] <- ""; saveRDS(x, path)
}
revision <- build_station_custom_dates_pilot(stations, cache_dir, output)$summary
stopifnot(revision$built == length(uids))
report <- rbind(data.frame(run = "copied-cache baseline", baseline), data.frame(run = "simulated appended day", append),
  data.frame(run = "simulated early revision", revision))
write.csv(report, file.path(base, "summary.csv"), row.names = FALSE)
print(report[c("run", "stations", "years", "built", "reused", "seconds")], row.names = FALSE)
message("Only copied diagnostic caches changed. These sample timings are not a full-network new-date or VM benchmark.")
