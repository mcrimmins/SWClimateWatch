# Independent scalar checks: expand monthly means onto an actual daily calendar.
# This validates local arithmetic and saved outputs, not the PRISM source itself.
prism_monthly_check_window <- function(monthly, end, duration = 12L) {
  last <- as.Date(paste0(end, "-01"), format = "%Y-%m-%d")
  # Calendar index arithmetic deliberately avoids the production window helper.
  index <- as.integer(format(last, "%Y")) * 12L + as.integer(format(last, "%m")) - 1L
  indices <- seq.int(index - duration + 1L, index)
  months <- sprintf("%04d-%02d", indices %/% 12L, indices %% 12L + 1L)
  rows <- match(months, monthly$month)
  if (anyNA(rows)) return(NA_real_)
  hi <- monthly$maxt[rows]; lo <- monthly$mint[rows]
  if (any(!is.finite(hi) | !is.finite(lo) | hi < lo)) return(NA_real_)
  next_index <- index + 1L
  following <- as.Date(sprintf("%04d-%02d-01", next_index %/% 12L, next_index %% 12L + 1L))
  days <- seq(as.Date(paste0(months[1], "-01")), following - 1L, by = "day")
  daily <- (hi + lo)[match(format(days, "%Y-%m"), months)] / 2
  mean(daily)
}

prism_monthly_check_statistics <- function(values, years, target_year,
    min_years = 30L, min_fraction = 0.9) {
  values <- unname(values)
  target <- values[match(target_year, years)]
  usable <- is.finite(values)
  n <- sum(usable)
  output <- c(mean_temperature_f = target, percentile = NA_real_, warm_rank = NA_real_,
    cold_rank = NA_real_, sample_years = n, normal_mean_f = NA_real_,
    departure_f = NA_real_, normal_years = sum(usable & years >= 1991 & years <= 2020))
  # Base-R ranks use eight decimal places to avoid insignificant daily-expansion
  # rounding noise. Differences near a production tie boundary are reported.
  if (is.finite(target) && n >= max(min_years, ceiling(min_fraction * length(years)))) {
    ranks <- rank(round(values[usable], 8), ties.method = "average")
    cold <- ranks[match(target_year, years[usable])]
    output[c("percentile", "warm_rank", "cold_rank")] <- c(100 * (cold - 0.5) / n, n + 1 - cold, cold)
  }
  if (output[["normal_years"]] >= 27L) {
    normal <- mean(values[usable & years >= 1991 & years <= 2020])
    output[c("normal_mean_f", "departure_f")] <- c(normal, target - normal)
  }
  output
}

prism_monthly_check_close <- function(expected, actual, tolerance = 1e-4) {
  (is.na(expected) & is.na(actual)) |
    (is.finite(expected) & is.finite(actual) & abs(expected - actual) <= tolerance)
}

check_prism_monthly_temperature_pilot <- function(
    pilot_dir = "data/diagnostics/prism-monthly-temperature-pilot",
    report_dir = "data/diagnostics/prism-monthly-temperature-check",
    cache_dir = prism_monthly_cache_dir(), start = "1895-01", historical_year = 1993L,
    points = data.frame(location = c("Phoenix", "Tucson", "Flagstaff", "Yuma",
      "Albuquerque", "Santa Fe", "Las Cruces", "Southern Colorado mountains"),
      longitude = c(-112.074, -110.975, -111.651, -114.624, -106.651, -105.938, -106.763, -106.8),
      latitude = c(33.448, 32.222, 35.198, 32.693, 35.084, 35.687, 32.32, 37.48)),
    bbox = swc_region$bbox, min_years = 30L, min_fraction = 0.9) {
  started <- proc.time()[["elapsed"]]
  summary_path <- file.path(pilot_dir, "summary.csv")
  if (!file.exists(summary_path)) stop("Build the monthly temperature pilot first.")
  pilot <- read.csv(summary_path, stringsAsFactors = FALSE)
  if (nrow(pilot) != 1L || pilot$status != "READY") stop("Expected one READY pilot summary.")
  end <- pilot$end_month; duration <- pilot$duration_months
  historical <- sprintf("%04d-%s", historical_year, substr(end, 6, 7))
  if (historical >= end || historical < start) stop("Historical end date must precede the pilot and follow the cache start.")
  if (!is.data.frame(points) || !nrow(points) || anyDuplicated(points$location) ||
      anyNA(points) || any(!is.finite(points$longitude) | !is.finite(points$latitude))) {
    stop("Supply uniquely named locations with finite longitude and latitude.")
  }
  message("Checking monthly temperature inputs and output provenance...")
  all_inputs <- plan_prism_monthly_download(start = start, end = end,
    cache_dir = cache_dir, bbox = bbox, verify_grids = FALSE)
  if (!all(all_inputs$complete)) stop("Input checksums or request identities do not match the cache manifest.")
  source <- terra::rast(all_inputs$path[1])
  geometry <- list(extent = as.vector(terra::ext(source)), resolution = terra::res(source),
    dimensions = dim(source), crs = terra::crs(source))
  recorded <- read.csv(file.path(pilot_dir, "source-audit-signatures.csv"), stringsAsFactors = FALSE)
  for (month in unique(all_inputs$month)) {
    signature <- prism_monthly_audit_signature(all_inputs[all_inputs$month == month, ], geometry)
    row <- match(month, recorded$month)
    if (is.na(row) || !identical(signature, recorded$signature[row])) {
      stop("Source inputs differ from the saved pilot. Rebuild the pilot before checking.")
    }
  }
  plan <- all_inputs[all_inputs$variable %in% c("maxt", "mint"), ]
  grid <- terra::rast(file.path(pilot_dir, "mean_temperature_f.tif"))
  cells <- terra::cellFromXY(grid, as.matrix(points[, c("longitude", "latitude")]))
  if (anyNA(cells)) stop("A requested check location is outside the pilot grid.")
  centers <- terra::xyFromCell(grid, cells)
  points$cell <- cells; points$grid_longitude <- centers[, 1]; points$grid_latitude <- centers[, 2]
  dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
  point_cache_path <- file.path(report_dir, "point-inputs.rds")
  source_signature <- digest::digest(list(plan = plan[, c("month", "variable", "request_signature")],
    md5 = unname(tools::md5sum(plan$path)), points = points), algo = "sha256")
  cached <- if (file.exists(point_cache_path)) tryCatch(readRDS(point_cache_path), error = function(e) NULL) else NULL
  reused <- !is.null(cached) && identical(cached$signature, source_signature)
  months <- unique(plan$month)
  if (reused) {
    inputs <- cached$inputs
    message("Reusing verified point inputs.")
  } else {
    inputs <- expand.grid(location = points$location, month = months, stringsAsFactors = FALSE)
    inputs$maxt <- inputs$mint <- NA_real_
    for (i in seq_len(nrow(plan))) {
      r <- terra::rast(plan$path[i])
      terra::compareGeom(grid, r, stopOnError = TRUE)
      extracted <- terra::extract(r, centers)
      input_rows <- which(inputs$month == plan$month[i])
      inputs[input_rows, plan$variable[i]] <- as.numeric(extracted[, ncol(extracted)])
      if (i %% 200L == 0L || i == nrow(plan)) message("Point inputs: ", i, "/", nrow(plan), " grids.")
    }
    saveRDS(list(signature = source_signature, inputs = inputs), point_cache_path)
  }
  periods <- c(latest = end, historical = historical)
  comparisons <- list(); samples <- list(); windows <- list()
  metrics <- c("mean_temperature_f", "percentile", "warm_rank", "cold_rank", "sample_years",
    "normal_mean_f", "departure_f", "normal_years")
  # Reject stale/foreign grids even if a few sampled values happen to coincide.
  outputs <- lapply(metrics, function(metric) {
    r <- terra::rast(file.path(pilot_dir, paste0(metric, ".tif")))
    terra::compareGeom(grid, r, stopOnError = TRUE)
    if (!identical(format(terra::time(r), "%Y-%m"), end)) stop("Pilot output month does not match summary.")
    x <- terra::extract(r, centers)
    as.numeric(x[, ncol(x)])
  })
  names(outputs) <- metrics
  for (period in names(periods)) {
    target <- periods[[period]]
    years <- seq.int(as.integer(substr(start, 1, 4)), as.integer(substr(target, 1, 4)))
    ends <- sprintf("%04d-%s", years, substr(target, 6, 7))
    # Use a calendar index to determine first complete reference window independently.
    first_index <- as.integer(substr(start, 1, 4)) * 12L + as.integer(substr(start, 6, 7)) - 1L
    last_indices <- years * 12L + as.integer(substr(target, 6, 7)) - 1L
    keep <- last_indices - duration + 1L >= first_index
    years <- years[keep]; ends <- ends[keep]
    if (!length(years)) stop("Historical check has no complete reference windows.")
    for (j in seq_len(nrow(points))) {
      monthly <- inputs[inputs$location == points$location[j], ]
      independent <- vapply(ends, function(e) prism_monthly_check_window(monthly, e, duration), numeric(1))
      weighted <- vapply(ends, function(e) {
        dates <- prism_monthly_window(e, duration)
        ii <- match(format(dates, "%Y-%m"), monthly$month)
        hi <- monthly$maxt[ii]; lo <- monthly$mint[ii]
        if (anyNA(ii) || any(!is.finite(hi) | !is.finite(lo) | hi < lo)) return(NA_real_)
        stats::weighted.mean((hi + lo) / 2, prism_monthly_day_weights(dates))
      }, numeric(1))
      independent_stats <- prism_monthly_check_statistics(independent, years,
        as.integer(substr(target, 1, 4)), min_years, min_fraction)
      pipeline_stats <- prism_monthly_temperature_statistics(matrix(weighted, nrow = 1), years,
        as.integer(substr(target, 1, 4)), min_years, min_fraction)[1, ]
      source <- if (period == "latest") "saved pilot GeoTIFF" else "historical scalar pipeline"
      actual <- if (period == "latest") vapply(outputs, function(x) x[j], numeric(1)) else pipeline_stats
      comparisons[[length(comparisons) + 1L]] <- data.frame(period = period, end_month = target,
        location = points$location[j], source = source, metric = metrics,
        expected = unname(independent_stats[metrics]), actual = unname(actual[metrics]),
        difference = unname(actual[metrics] - independent_stats[metrics]),
        status = ifelse(prism_monthly_check_close(independent_stats[metrics], actual[metrics]), "PASS", "FAIL"))
      windows[[length(windows) + 1L]] <- data.frame(period = period, location = points$location[j], ending_year = years,
        daily_calendar_mean_f = independent, weighted_mean_f = weighted,
        status = ifelse(prism_monthly_check_close(independent, weighted, 1e-8), "PASS", "FAIL"))
      samples[[length(samples) + 1L]] <- data.frame(period = period, end_month = target,
        location = points$location[j], mean_temperature_f = independent_stats[["mean_temperature_f"]],
        percentile = independent_stats[["percentile"]], warm_rank = independent_stats[["warm_rank"]],
        sample_years = independent_stats[["sample_years"]], departure_f = independent_stats[["departure_f"]])
    }
  }
  comparisons <- do.call(rbind, comparisons); windows <- do.call(rbind, windows); samples <- do.call(rbind, samples)
  failed <- sum(comparisons$status == "FAIL") + sum(windows$status == "FAIL")
  summary <- data.frame(status = if (failed) "FAIL" else "PASS", latest = end,
    historical = historical, locations = nrow(points), metric_checks = nrow(comparisons),
    window_checks = nrow(windows), failed_checks = failed, point_cache_reused = reused,
    elapsed_seconds = proc.time()[["elapsed"]] - started, source_signature = source_signature)
  for (name in c("summary", "comparisons", "windows", "samples", "points")) {
    write.csv(get(name), file.path(report_dir, paste0(name, ".csv")), row.names = FALSE, na = "")
  }
  writeLines(c("Independent arithmetic check using the same cached PRISM source grids, not external source validation.",
    "Point coordinates sample PRISM grid cells; these are not station observations.",
    "Independent means expand monthly means onto every calendar day, including leap days.",
    "Independent percentiles use base-R average ranks after rounding to eight decimal places.",
    "Latest metrics are compared with the actual saved GeoTIFF values (tolerance 0.0001).",
    "Historical metrics are compared with the scalar production rules, not a historical map.",
    "Historical comparisons stop at that year; no future years enter ranks or normals.",
    "A normal departure may be unavailable before enough 1991-2020 windows exist.",
    "All eligible window means are checked against day-weighted arithmetic (tolerance 1e-8).",
    "No downloads, map changes, site rendering or S3 publication."), file.path(report_dir, "methods.txt"))
  list(summary = summary, comparisons = comparisons, windows = windows, samples = samples, points = points)
}
