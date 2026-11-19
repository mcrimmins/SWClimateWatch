source("scripts/load-prism-monthly.R")
source("R/historic-monthly-pilot.R")
root <- getOption("swc.historic.monthly.check_root", "data/diagnostics/historic-monthly-pilot")
if (!file.exists(file.path(root, "summary.csv")))
  stop("The pilot build is not complete. Run scripts/build-historic-monthly-pilot.R first.", call. = FALSE)
summary <- read.csv(file.path(root, "summary.csv"))
if (!identical(summary$status, "READY"))
  stop("The pilot is not ready; wait for a successful build before reviewing.", call. = FALSE)
x <- read.csv(file.path(root, "manifest.csv"), stringsAsFactors = FALSE)
stopifnot(summary$status == "READY", summary$requests == 0L,
  nrow(x) == historic_monthly_products_per_year() * summary$years, !anyDuplicated(x[c("water_year", "period", "metric")]),
  all(x$supported_cells > 0), all(file.exists(x$map)), all(file.exists(x$grid)))
expected_windows <- historic_monthly_windows(unique(x$water_year))
window_match <- match(paste(x$water_year, x$period), paste(expected_windows$water_year, expected_windows$period))
stopifnot(!anyNA(window_match), all(x$start == expected_windows$start[window_match]),
  all(x$end == expected_windows$end[window_match]), all(x$definition == expected_windows$definition[window_match]),
  all(x$period[x$metric == "spi12"] == "water-year"))
for (year in unique(x$water_year)) for (period in historic_monthly_periods()$id) {
  expected_metrics <- names(historic_monthly_metrics())[1:5]
  if (period == "water-year") expected_metrics <- c(expected_metrics, "spi12")
  stopifnot(setequal(x$metric[x$water_year == year & x$period == period], expected_metrics))
}
for (folder in unique(dirname(x$grid))) {
  marker <- readRDS(file.path(folder, "complete.rds"))
  stopifnot(prism_monthly_ranking_complete(file.path(folder, "complete.rds"), marker$signature))
}
for (period in unique(x$period)) {
  ref <- readRDS(file.path(root, "reference", period, "windows.rds"))
  reference_marker <- readRDS(file.path(root, "reference", period, "complete.rds"))
  stopifnot(prism_monthly_ranking_complete(file.path(root, "reference", period, "complete.rds"), reference_marker$signature))
  check_code <- unname(tools::md5sum("scripts/check-historic-monthly-pilot.R"))
  dir.create(file.path(root, "numeric-checks"), showWarnings = FALSE)
  for (year in unique(x$water_year)) {
    rows <- x[x$period == period & x$water_year == year & x$metric != "spi12", ]
    check_signature <- digest::digest(list(check_code, year, period, reference_marker$signature,
      reference_marker$md5, unname(tools::md5sum(unique(rows$grid))),
      if (period == "water-year") unname(tools::md5sum(c(file.path(root, "reference/spi-fit.rds"),
        x$grid[x$water_year == year & x$metric == "spi12"]))), prism_monthly_spi_policy()), algo = "sha256")
    checkpoint <- file.path(root, "numeric-checks", paste0("wy", year, "-", period, ".rds"))
    previous <- if (file.exists(checkpoint)) tryCatch(readRDS(checkpoint), error = function(e) NULL) else NULL
    if (is.list(previous) && identical(previous$signature, check_signature)) {
      message("REUSED numeric check: WY", year, " ", period)
      next
    }
    message("Checking numeric maps: WY", year, " ", period)
    grid <- terra::rast(rows$grid[1]); index <- match(year, ref$years)
    for (variable in c("precipitation", "temperature")) {
      values <- ref[[variable]]; target <- values[, index]
      n <- rowSums(is.finite(values))
      expected <- 100 * (rowSums(values < target - 1e-8, na.rm = TRUE) +
        .5 * rowSums(abs(values - target) <= 1e-8, na.rm = TRUE)) / pmax(n, 1)
      expected[!is.finite(target) | n < max(30L, ceiling(.9 * ncol(values)))] <- NA_real_
      actual <- terra::values(grid[[paste0(variable, "_rank")]], mat = FALSE)
      stopifnot(identical(is.finite(actual), is.finite(expected)), all(abs(actual - expected) < 1e-4, na.rm = TRUE))
    }
    t <- ref$temperature[, ref$years %in% 1991:2020, drop = FALSE]
    normal <- rowMeans(t, na.rm = TRUE); normal[rowSums(is.finite(t)) < 27L] <- NA_real_
    expected <- ref$temperature[, index] - normal
    actual <- terra::values(grid[["temperature_departure"]], mat = FALSE)
    stopifnot(identical(is.finite(actual), is.finite(expected)), all(abs(actual - expected) < 1e-4, na.rm = TRUE))
    if (period == "water-year") {
      fit <- readRDS(file.path(root, "reference", "spi-fit.rds"))
      policy <- prism_monthly_spi_policy(); current <- ref$precipitation[, index]
      good <- fit$fit_status == 0L & is.finite(current) & current >= 0
      expected_spi <- rep(NA_real_, length(current))
      probability <- fit$zero_fraction[good] + (1 - fit$zero_fraction[good]) *
        stats::pgamma(current[good], shape = fit$shape[good], scale = fit$scale_inches[good])
      expected_spi[good] <- stats::qnorm(pmax(policy$probability_epsilon, pmin(1 - policy$probability_epsilon, probability)))
      spi_row <- x[x$water_year == year & x$metric == "spi12", ]
      actual_spi <- terra::values(terra::rast(spi_row$grid)[["spi"]], mat = FALSE)
      stopifnot(identical(is.finite(actual_spi), is.finite(expected_spi)),
        all(abs(actual_spi - expected_spi) < 1e-4, na.rm = TRUE))
    }
    saveRDS(list(signature = check_signature, status = "PASS"), checkpoint)
  }
}
for (year in unique(x$water_year)) {
  windows <- historic_monthly_windows(year)
  seasonal_p <- seasonal_t <- NULL; total_days <- 0
  for (period in c("cool-season", "spring", "monsoon")) {
    window <- windows[windows$period == period, ]
    days <- sum(prism_monthly_day_weights(prism_monthly_window(window$end, window$duration)))
    row <- x[x$water_year == year & x$period == period & x$metric == "precipitation_total", ]
    grid <- terra::rast(row$grid)
    p <- terra::values(grid[["precipitation_total"]], mat = FALSE)
    t <- terra::values(grid[["temperature_mean"]], mat = FALSE)
    seasonal_p <- if (is.null(seasonal_p)) p else seasonal_p + p
    seasonal_t <- if (is.null(seasonal_t)) t * days else seasonal_t + t * days
    total_days <- total_days + days
  }
  water <- terra::rast(x$grid[x$water_year == year & x$period == "water-year" & x$metric == "precipitation_total"])
  water_p <- terra::values(water[["precipitation_total"]], mat = FALSE)
  water_t <- terra::values(water[["temperature_mean"]], mat = FALSE)
  stopifnot(identical(is.finite(water_p), is.finite(seasonal_p)),
    identical(is.finite(water_t), is.finite(seasonal_t)),
    all(abs(water_p - seasonal_p) < 1e-4, na.rm = TRUE),
    all(abs(water_t - seasonal_t / total_days) < 1e-4, na.rm = TRUE))
}
gallery <- paste(readLines(file.path(root, "index.html"), warn = FALSE), collapse = "\n")
stopifnot(length(gregexpr('<article data-year=', gallery, fixed = TRUE)[[1L]]) == nrow(x),
  grepl('Spring (April-June)', gallery, fixed = TRUE),
  grepl('Monsoon (July-September)', gallery, fixed = TRUE),
  !grepl('monsoon: June-September', gallery, fixed = TRUE))
inventory <- read.csv(file.path(root, "source-inventory.csv"), stringsAsFactors = FALSE)
stopifnot(identical(unname(tools::md5sum(inventory$path)), inventory$md5))
message("PASS: ", summary$years, " years, ", nrow(x), " maps; seasonal partition, saved ranks, normal departures, SPI, masks, gallery, source and output checksums verified. No publication.")
