# Sample original inputs once and independently check all 10 maps.
source("scripts/check-regional-climate-reference-pilot.R")
directory <- "data/diagnostics/regional-seasonal-reference-pilot"
inventory <- read.csv(file.path(directory, "source-inventory.csv"), stringsAsFactors = FALSE)
if (nrow(inventory) != 1080L || !identical(unname(tools::md5sum(inventory$path)), inventory$md5))
  stop("Seasonal inputs changed; rebuild the seasonal pilot.")
definitions <- list(winter = 1:3, spring = 4:6, summer = 7:9, fall = 10:12)
records <- list()
for (period in names(definitions)) {
  selected_days <- as.integer(format(dates, "%m")) %in% definitions[[period]]
  selected_months <- as.integer(substr(months, 6, 7)) %in% definitions[[period]]
  expected_t <- rowMeans(vapply(1991:2020, function(year)
    rowMeans(daily[, selected_days & format(dates, "%Y") == as.character(year), drop = FALSE]), numeric(nrow(points))))
  expected_p <- rowMeans(vapply(1991:2020, function(year)
    rowSums(monthly$pcpn[, selected_months & substr(months, 1, 4) == as.character(year), drop = FALSE]), numeric(nrow(points))))
  for (variable in c("precipitation", "temperature")) {
    expected <- if (variable == "precipitation") expected_p else expected_t
    value <- terra::extract(terra::rast(file.path(directory, period, paste0(variable, ".tif"))), points)
    actual <- as.numeric(value[[ncol(value)]])
    pass <- (is.na(expected) & is.na(actual)) | (is.finite(expected) & is.finite(actual) & abs(actual - expected) <= 1e-4)
    records[[length(records) + 1L]] <- data.frame(location = samples$location, period = period, variable = variable,
      expected = expected, actual = actual, difference = actual - expected, status = ifelse(pass, "PASS", "FAIL"))
  }
}
regional_seasonal_reference_check <- do.call(rbind, records)
write.csv(regional_seasonal_reference_check, file.path(directory, "independent-check.csv"), row.names = FALSE)
print(with(regional_seasonal_reference_check, table(period, status)))
if (any(regional_seasonal_reference_check$status != "PASS")) stop("Independent seasonal-reference comparisons failed.")
message("Reference check: PASS; 64 seasonal and 16 annual comparisons. No downloads.")
