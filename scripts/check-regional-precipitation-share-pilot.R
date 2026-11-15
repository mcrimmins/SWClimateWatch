# Check against independently sampled monthly inputs, not just derived reference grids.
source("scripts/check-regional-seasonal-reference-pilot.R")
annual_expected <- regional_reference_check[regional_reference_check$variable == "precipitation", ]
share_checks <- lapply(names(definitions), function(period) {
  seasonal_expected <- regional_seasonal_reference_check[
    regional_seasonal_reference_check$period == period & regional_seasonal_reference_check$variable == "precipitation", ]
  denominator <- annual_expected$expected[match(seasonal_expected$location, annual_expected$location)]
  expected <- 100 * seasonal_expected$expected / denominator
  expected[!is.finite(denominator) | denominator <= 0] <- NA_real_
  value <- terra::extract(terra::rast(file.path("data/diagnostics/regional-precipitation-share-pilot",
    paste0(period, "-precipitation-share.tif"))), points)
  actual <- as.numeric(value[[ncol(value)]])
  pass <- (is.na(expected) & is.na(actual)) | (is.finite(expected) & is.finite(actual) & abs(actual-expected) <= 1e-4)
  data.frame(location = seasonal_expected$location, period = period, expected = expected, actual = actual,
    status = ifelse(pass, "PASS", "FAIL"))
})
regional_share_check <- do.call(rbind, share_checks)
write.csv(regional_share_check, "data/diagnostics/regional-precipitation-share-pilot/independent-check.csv", row.names = FALSE)
print(with(regional_share_check, table(period, status)))
stopifnot(all(regional_share_check$status == "PASS"))
message("Seasonal shares: PASS; 32 independent point comparisons. No downloads or publication.")
