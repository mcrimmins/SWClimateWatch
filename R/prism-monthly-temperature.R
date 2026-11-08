# Calendar-matched monthly temperature pilot. Current year is included once.
prism_monthly_window <- function(end, duration = 12L) {
  if (length(duration) != 1L || !is.finite(duration) || duration < 1 || duration != floor(duration)) {
    stop("duration must be a positive whole number.", call. = FALSE)
  }
  end <- prism_monthly_month(end)
  if (length(end) != 1L) stop("Supply one ending month.", call. = FALSE)
  rev(seq(end, by = "-1 month", length.out = duration))
}

prism_monthly_day_weights <- function(months) {
  vapply(as.character(months), function(x) {
    d <- as.Date(x)
    as.numeric(seq(d, by = "month", length.out = 2L)[2] - d)
  }, numeric(1))
}

prism_monthly_temperature_window <- function(plan, end, duration = 12L) {
  months <- format(prism_monthly_window(end, duration), "%Y-%m")
  required <- expand.grid(variable = c("maxt", "mint"), month = months, stringsAsFactors = FALSE)
  indices <- match(paste(required$variable, required$month), paste(plan$variable, plan$month))
  if (anyNA(indices) || any(!plan$complete[indices])) stop("Temperature window has missing or unverified inputs.")
  reference <- terra::rast(plan$path[indices[1]])
  total <- rep(0, terra::ncell(reference)); usable <- rep(TRUE, length(total))
  weights <- prism_monthly_day_weights(prism_monthly_window(end, duration))
  for (i in seq_along(months)) {
    hi <- terra::rast(plan$path[indices[2L * i - 1L]])
    lo <- terra::rast(plan$path[indices[2L * i]])
    terra::compareGeom(reference, hi, lo, stopOnError = TRUE)
    hi <- terra::values(hi, mat = FALSE); lo <- terra::values(lo, mat = FALSE)
    good <- is.finite(hi) & is.finite(lo) & hi >= lo
    usable <- usable & good
    mean <- (hi + lo) / 2
    mean[!good] <- 0
    total <- total + mean * weights[i]
  }
  total <- total / sum(weights)
  total[!usable] <- NA_real_
  terra::setValues(reference, total)
}

prism_monthly_ranking_statistics <- function(values, years, target_year,
    min_years = 30L, min_fraction = 0.9, normal_years = 1991:2020,
    min_normal_years = 27L) {
  if (!is.matrix(values) || ncol(values) != length(years) || anyDuplicated(years) ||
      sum(years == target_year) != 1L) stop("Expected unique comparison years including the target once.")
  if (length(min_years) != 1L || !is.finite(min_years) || min_years < 1 || min_years != floor(min_years) ||
      length(min_fraction) != 1L || !is.finite(min_fraction) || min_fraction <= 0 || min_fraction > 1 ||
      length(min_normal_years) != 1L || !is.finite(min_normal_years) || min_normal_years < 1) {
    stop("Invalid historical support thresholds.")
  }
  current <- values[, match(target_year, years)]
  n <- rowSums(is.finite(values))
  # A small numerical tolerance prevents floating-point noise from breaking ties.
  lower <- rowSums(values < current - 1e-8, na.rm = TRUE)
  equal <- rowSums(abs(values - current) <= 1e-8, na.rm = TRUE)
  supported <- is.finite(current) & n >= max(min_years, ceiling(min_fraction * ncol(values)))
  cold_rank <- lower + (equal + 1) / 2
  warm_rank <- n - lower - equal + (equal + 1) / 2
  percentile <- 100 * (lower + equal / 2) / pmax(n, 1)
  normal <- values[, years %in% normal_years, drop = FALSE]
  normal_n <- rowSums(is.finite(normal))
  normal_mean <- rowMeans(normal, na.rm = TRUE)
  normal_mean[normal_n < min_normal_years] <- NA_real_
  result <- cbind(current = current, percentile = percentile,
    upper_rank = warm_rank, lower_rank = cold_rank, sample_years = n,
    normal_mean = normal_mean, departure = current - normal_mean, normal_years = normal_n)
  result[!supported, c("percentile", "upper_rank", "lower_rank")] <- NA_real_
  # Record highs need every eligible historical window, not just rank support.
  # At least one lower value excludes constant series (especially all-zero rain).
  complete <- supported & n == ncol(values)
  record_high <- ifelse(complete, as.numeric(lower + equal == n & lower > 0), NA_real_)
  record_high_tied <- ifelse(complete, as.numeric(record_high == 1 & equal > 1), NA_real_)
  record_low <- ifelse(complete, as.numeric(lower == 0 & equal < n), NA_real_)
  record_low_tied <- ifelse(complete, as.numeric(record_low == 1 & equal > 1), NA_real_)
  cbind(result, record_high = record_high, record_high_tied = record_high_tied,
    record_low = record_low, record_low_tied = record_low_tied)
}

prism_monthly_temperature_statistics <- function(values, years, target_year,
    min_years = 30L, min_fraction = 0.9, normal_years = 1991:2020,
    min_normal_years = 27L) {
  result <- prism_monthly_ranking_statistics(values, years, target_year,
    min_years, min_fraction, normal_years, min_normal_years)
  colnames(result) <- c("mean_temperature_f", "percentile", "warm_rank", "cold_rank",
    "sample_years", "normal_mean_f", "departure_f", "normal_years", "record_high", "record_high_tied",
    "record_low", "record_low_tied")
  result
}

prism_monthly_record_display <- function(percentile, record_high, record_low = rep(0, length(percentile))) {
  if (length(percentile) != length(record_high) || length(percentile) != length(record_low)) stop("Display inputs have different lengths.")
  if (any(record_high == 1 & record_low == 1, na.rm = TRUE)) stop("A cell cannot be both a record high and low.")
  result <- percentile
  # -1 and 101 are internal category codes, never scientific percentiles.
  result[which(record_high == 1 & is.finite(percentile))] <- 101
  result[which(record_low == 1 & is.finite(percentile))] <- -1
  result
}

prism_monthly_comparison_windows <- function(start, end, duration) {
  target <- prism_monthly_month(end)
  years <- seq(as.integer(substr(start, 1, 4)), as.integer(format(target, "%Y")))
  endings <- paste0(years, "-", format(target, "%m"))
  starts <- vapply(endings, function(e) format(min(prism_monthly_window(e, duration)), "%Y-%m"), character(1))
  eligible <- starts >= start
  windows <- data.frame(ending_year = years[eligible], ending_month = endings[eligible], start_month = starts[eligible])
  if (!nrow(windows) || !end %in% windows$ending_month) stop("No complete target comparison window.")
  windows
}

prism_monthly_ranking_dependencies <- function(start, end, duration) {
  windows <- prism_monthly_comparison_windows(start, end, duration)
  unique(unlist(lapply(windows$ending_month,
    function(e) format(prism_monthly_window(e, duration), "%Y-%m"))))
}

# A batch can share its freshly computed audit across products. Standalone calls
# always perform their own audit. This avoids rescanning 4,746 files per map.
prism_monthly_pilot_audit <- function(start, end, cache_dir, audit_dir, bbox, audit = NULL) {
  if (is.null(audit)) audit <- audit_prism_monthly_cache(start, end, cache_dir, audit_dir, bbox)
  if (!is.list(audit) || !is.data.frame(audit$summary) || nrow(audit$summary) != 1L ||
      !audit$summary$status %in% c("PASS", "WARN") ||
      audit$summary$start_month != start || audit$summary$end_month != end ||
      !all(audit$plan$complete) ||
      !all(audit$plan$bbox == paste(normalize_prism_bbox(bbox), collapse = ",")) ||
      !identical(attr(audit$plan, "manifest_path"), file.path(cache_dir, "manifest.csv"))) {
    stop("Monthly cache audit failed or does not match this pilot request; inspect audit reports.")
  }
  audit
}

build_prism_monthly_temperature_pilot <- function(end = prism_monthly_latest_complete(),
    duration = 12L, start = "1895-01", cache_dir = prism_monthly_cache_dir(),
    output_dir = "data/diagnostics/prism-monthly-temperature-pilot",
    audit_dir = "data/diagnostics/prism-monthly-cache-audit", bbox = swc_region$bbox,
    min_years = 30L, min_fraction = 0.9, make_map = TRUE, .audit = NULL) {
  started <- proc.time()[["elapsed"]]
  audit <- prism_monthly_pilot_audit(start, end, cache_dir, audit_dir, bbox, .audit)
  target <- prism_monthly_month(end)
  windows <- prism_monthly_comparison_windows(start, end, duration)
  years <- windows$ending_year; endings <- windows$ending_month
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  reference <- terra::rast(audit$plan$path[1])
  values <- matrix(NA_real_, nrow = terra::ncell(reference), ncol = length(years))
  for (i in seq_along(years)) {
    values[, i] <- terra::values(prism_monthly_temperature_window(audit$plan, endings[i], duration), mat = FALSE)
    if (i %% 10L == 0L || i == length(years)) message("Monthly temperature: ", i, "/", length(years), " comparison windows.")
  }
  stats <- prism_monthly_temperature_statistics(values, years, as.integer(format(target, "%Y")), min_years, min_fraction)
  paths <- setNames(file.path(output_dir, paste0(colnames(stats), ".tif")), colnames(stats))
  for (name in colnames(stats)) {
    r <- terra::setValues(reference, stats[, name])
    names(r) <- name; terra::time(r) <- target
    terra::writeRaster(r, paths[[name]], overwrite = TRUE, datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
  }
  paths <- c(paths, display_class = file.path(output_dir, "display_class.tif"))
  display <- terra::setValues(reference, prism_monthly_record_display(stats[, "percentile"], stats[, "record_high"], stats[, "record_low"]))
  names(display) <- "display_class"; terra::time(display) <- target
  terra::writeRaster(display, paths[["display_class"]], overwrite = TRUE, datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
  write.csv(windows, file.path(output_dir, "comparison-windows.csv"), row.names = FALSE)
  write.csv(audit$months[, c("month", "signature", "status")],
    file.path(output_dir, "source-audit-signatures.csv"), row.names = FALSE)
  supported <- is.finite(stats[, "percentile"])
  summary <- data.frame(status = if (any(supported)) "READY" else "NO_SUPPORTED_CELLS",
    start_month = tail(windows$start_month, 1), end_month = end, duration_months = duration,
    comparison_first_year = min(years), comparison_last_year = max(years), comparison_windows = length(years),
    minimum_years = max(min_years, ceiling(min_fraction * length(years))),
    source_signature = prism_monthly_source_signature(audit),
    supported_cells = sum(supported), current_valid_cells = sum(is.finite(stats[, "mean_temperature_f"])),
    below_33_cells = sum(stats[, "percentile"] < 33, na.rm = TRUE),
    above_67_cells = sum(stats[, "percentile"] > 67, na.rm = TRUE),
    record_high_cells = sum(stats[, "record_high"] == 1, na.rm = TRUE),
    tied_record_high_cells = sum(stats[, "record_high_tied"] == 1, na.rm = TRUE),
    record_low_cells = sum(stats[, "record_low"] == 1, na.rm = TRUE),
    tied_record_low_cells = sum(stats[, "record_low_tied"] == 1, na.rm = TRUE))
  if (!any(supported)) {
    write.csv(summary, file.path(output_dir, "summary.csv"), row.names = FALSE)
    stop("No cells meet historical support requirements; see summary.csv.")
  }
  if (make_map) {
    period <- if (duration == 1L) format(target, "%B %Y") else paste0(
      format(min(prism_monthly_window(end, duration)), "%B %Y"), "-", format(target, "%B %Y"))
    plot <- southwest_raster_map(terra::rast(paths[["display_class"]]),
      states = southwest_state_boundaries(), counties = southwest_county_boundaries(),
      countries = southwest_country_boundaries(), cities = southwest_reference_cities(),
      title = paste0(duration, "-month mean-temperature ranking"),
      subtitle = paste0(period, " | matching windows ending ", min(years), "-", max(years)),
      caption = NULL, fill_label = "Historical percentile / record",
      palette = c("#081d58", "#313695", "#4575b4", "#91bfdb", "#f7f7f7", "#fdae61", "#d73027", "#7f0000", "#542788"),
      palette_values = c(-0.5, 1, 6, 21.5, 50, 78.5, 94, 99, 100.5), limits = c(-1, 101),
      breaks = c(-1, 0, 2, 10, 33, 67, 90, 98, 100, 101), product_id = "monthly_temperature_record_percentile",
      scale_type = "categorical")
    paths <- c(paths, map = file.path(output_dir, "temperature-ranking.png"))
    save_southwest_map(plot, paths[["map"]], logo_path = southwest_brand_logo_path(),
      footer_text = paste0("Data: PRISM Climate Group via RCC-ACIS\nFull-record midrank percentile; current year included once\n",
        "Ranks: >=", summary$minimum_years, " years | *Records include ties; require all ", length(years), " windows"))
  }
  summary$elapsed_seconds <- proc.time()[["elapsed"]] - started
  write.csv(summary, file.path(output_dir, "summary.csv"), row.names = FALSE)
  writeLines(c("Monthly mean temperature = (monthly mean maximum + monthly mean minimum) / 2.",
    "Multi-month means are weighted by actual days in each month, including leap days.",
    "Each historical window requires every paired monthly input at each cell; no gap filling.",
    "Current window included once. Percentile = 100 * (count lower + 0.5 * count tied) / n.",
    "Ranks are average ranks for ties. Warm rank 1 = warmest; cold rank 1 = coldest.",
    "Record warm includes tied maxima and requires every eligible window, a valid current value, and at least one lower historical value.",
    "Record cold includes tied minima with every eligible window and at least one higher historical value.",
    "Constant series are not highlighted as record highs. Missing-history cells retain their supported percentile category.",
    "record_high and record_high_tied are separate flags; percentile.tif remains a true 0-100 percentile.",
    "record_low and record_low_tied store cold-record flags. display_class.tif uses -1 and 101 as record category codes, not percentiles.",
    "Historical ranks need 30 years and 90% of eligible windows by default.",
    "Departures use the mean of matching 1991-2020 windows, requiring at least 27 years.",
    "This full-record percentile differs from daily-map fixed-reference percentile calculations.",
    "This is a local pilot; no site files, publication, or scheduled updates changed."), file.path(output_dir, "methods.txt"))
  list(summary = summary, paths = paths, windows = windows)
}
