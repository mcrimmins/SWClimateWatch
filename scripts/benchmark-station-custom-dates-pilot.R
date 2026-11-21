# Measure actual unchanged-build overhead; synthetic revision/append tests are
# separate and never modify operational station caches.
source("scripts/load-station-custom-dates-pilot.R")
root <- station_custom_pilot_root()
previous <- read.csv(file.path(root, "update-summary.csv"))
warm <- build_station_custom_dates_pilot()$summary
report <- rbind(data.frame(run = "previous build", previous), data.frame(run = "repeat build", warm))
write.csv(report, file.path(root, "build-benchmark.csv"), row.names = FALSE)
print(report[c("run", "stations", "years", "built", "reused", "payload_bytes", "catalog_bytes", "seconds")], row.names = FALSE)
message("Browser performance: open Performance review in the pilot and run its selected-station benchmark. These R timings do not measure browser/network speed.")
