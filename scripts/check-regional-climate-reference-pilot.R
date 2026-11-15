# Independent point checks: expand monthly temperatures to actual calendar days.
# Does not call the production annual-window/statistics functions or download data.
directory <- "data/diagnostics/regional-climate-reference-pilot"
inventory <- read.csv(file.path(directory, "source-inventory.csv"), stringsAsFactors = FALSE)
samples <- read.csv(file.path(directory, "samples.csv"), stringsAsFactors = FALSE)
months <- format(seq(as.Date("1991-01-01"), as.Date("2020-12-01"), by = "month"), "%Y-%m")
if (nrow(inventory) != 1080L || !all(file.exists(inventory$path)) ||
    !identical(unname(tools::md5sum(inventory$path)), inventory$md5))
  stop("Reference input inventory is incomplete or changed; rebuild the pilot.")
points <- as.matrix(samples[c("longitude", "latitude")])
monthly <- list()
for (variable in c("maxt", "mint", "pcpn")) {
  rows <- inventory[inventory$variable == variable, ]
  indices <- match(months, rows$month)
  if (anyNA(indices) || anyDuplicated(rows$month)) stop("Missing or duplicate reference months.")
  monthly[[variable]] <- vapply(rows$path[indices], function(path) {
    x <- terra::extract(terra::rast(path), points)
    as.numeric(x[[ncol(x)]])
  }, numeric(nrow(points)))
  message("Reference point check: ", variable, "; 360 months sampled.")
}
dates <- seq(as.Date("1991-01-01"), as.Date("2020-12-31"), by = "day")
mean_monthly <- (monthly$maxt + monthly$mint) / 2
mean_monthly[!is.finite(monthly$maxt) | !is.finite(monthly$mint) | monthly$maxt < monthly$mint] <- NA_real_
daily <- mean_monthly[, match(format(dates, "%Y-%m"), months), drop = FALSE]
annual_t <- vapply(1991:2020, function(year)
  rowMeans(daily[, format(dates, "%Y") == as.character(year), drop = FALSE]), numeric(nrow(points)))
annual_p <- vapply(1991:2020, function(year)
  rowSums(monthly$pcpn[, substr(months, 1, 4) == as.character(year), drop = FALSE]), numeric(nrow(points)))
expected <- list(precipitation = rowMeans(annual_p), temperature = rowMeans(annual_t))
records <- lapply(names(expected), function(variable) {
  path <- file.path(directory, if (variable == "precipitation") "annual-precipitation.tif" else "annual-mean-temperature.tif")
  actual <- terra::extract(terra::rast(path), points)
  actual <- as.numeric(actual[[ncol(actual)]])
  difference <- actual - expected[[variable]]
  pass <- (is.na(actual) & is.na(expected[[variable]])) |
    (is.finite(actual) & is.finite(expected[[variable]]) & abs(difference) <= 1e-4)
  data.frame(location = samples$location, variable = variable, expected = expected[[variable]],
    actual = actual, difference = difference, status = ifelse(pass, "PASS", "FAIL"))
})
regional_reference_check <- do.call(rbind, records)
write.csv(regional_reference_check, file.path(directory, "independent-check.csv"), row.names = FALSE)
print(regional_reference_check, row.names = FALSE)
if (any(regional_reference_check$status != "PASS")) stop("Independent annual-reference checks failed.")
message("Annual reference independent check: PASS; 8 locations, 16 comparisons. No downloads.")
