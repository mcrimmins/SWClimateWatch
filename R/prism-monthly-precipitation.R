# Empirical precipitation rankings, not SPI. No distribution fitting is used.
prism_monthly_precipitation_footer <- function(summary) {
  paste0("Data: PRISM Climate Group via RCC-ACIS\n",
    "Ranks: >=", summary$minimum_years, " years | *Records include ties; all ", summary$comparison_windows, " windows\n",
    "Zero-total dry records require <=2% historical zeros | Not SPI")
}

prism_monthly_precipitation_window <- function(plan, end, duration = 12L) {
  months <- format(prism_monthly_window(end, duration), "%Y-%m")
  indices <- match(paste("pcpn", months), paste(plan$variable, plan$month))
  if (anyNA(indices) || any(!plan$complete[indices])) stop("Precipitation window has missing or unverified inputs.")
  reference <- terra::rast(plan$path[indices[1]])
  total <- rep(0, terra::ncell(reference)); usable <- rep(TRUE, length(total))
  for (i in indices) {
    r <- terra::rast(plan$path[i])
    terra::compareGeom(reference, r, stopOnError = TRUE)
    value <- terra::values(r, mat = FALSE)
    good <- is.finite(value) & value >= 0
    usable <- usable & good
    value[!good] <- 0
    total <- total + value
  }
  total[!usable] <- NA_real_
  terra::setValues(reference, total)
}

prism_monthly_precipitation_statistics <- function(values, years, target_year,
    min_years = 30L, min_fraction = 0.9, normal_years = 1991:2020,
    min_normal_years = 27L, max_record_zero_fraction = 0.02) {
  if (length(max_record_zero_fraction) != 1L || !is.finite(max_record_zero_fraction) ||
      max_record_zero_fraction < 0 || max_record_zero_fraction > 1) stop("Invalid zero-frequency threshold.")
  if (any(values < 0, na.rm = TRUE)) stop("Precipitation totals cannot be negative.")
  result <- prism_monthly_ranking_statistics(values, years, target_year,
    min_years, min_fraction, normal_years, min_normal_years)
  colnames(result) <- c("total_precipitation_inches", "percentile", "wet_rank", "dry_rank",
    "sample_years", "normal_mean_inches", "departure_inches", "normal_years", "record_high", "record_high_tied",
    "record_low", "record_low_tied")
  zero_fraction <- rowSums(is.finite(values) & values <= 1e-8) / pmax(result[, "sample_years"], 1)
  zero_fraction[result[, "sample_years"] == 0] <- NA_real_
  withheld <- result[, "record_low"] == 1 & result[, "total_precipitation_inches"] <= 1e-8 &
    zero_fraction > max_record_zero_fraction
  result[which(withheld), c("record_low", "record_low_tied")] <- 0
  cbind(result, zero_fraction = zero_fraction, record_low_zero_withheld = as.numeric(withheld))
}

build_prism_monthly_precipitation_pilot <- function(end = prism_monthly_latest_complete(),
    duration = 12L, start = "1895-01", cache_dir = prism_monthly_cache_dir(),
    output_dir = "data/diagnostics/prism-monthly-precipitation-pilot",
    audit_dir = "data/diagnostics/prism-monthly-cache-audit", bbox = swc_region$bbox,
    min_years = 30L, min_fraction = 0.9, make_map = TRUE, .audit = NULL) {
  started <- proc.time()[["elapsed"]]
  audit <- prism_monthly_pilot_audit(start, end, cache_dir, audit_dir, bbox, .audit)
  target <- prism_monthly_month(end)
  windows <- prism_monthly_comparison_windows(start, end, duration)
  years <- windows$ending_year
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  reference <- terra::rast(audit$plan$path[1])
  values <- matrix(NA_real_, nrow = terra::ncell(reference), ncol = length(years))
  for (i in seq_along(years)) {
    values[, i] <- terra::values(prism_monthly_precipitation_window(audit$plan,
      windows$ending_month[i], duration), mat = FALSE)
    if (i %% 10L == 0L || i == length(years)) message("Monthly precipitation: ", i, "/", length(years), " comparison windows.")
  }
  stats <- prism_monthly_precipitation_statistics(values, years,
    as.integer(format(target, "%Y")), min_years, min_fraction)
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
    supported_cells = sum(supported), current_valid_cells = sum(is.finite(stats[, "total_precipitation_inches"])),
    below_33_cells = sum(stats[, "percentile"] < 33, na.rm = TRUE),
    above_67_cells = sum(stats[, "percentile"] > 67, na.rm = TRUE),
    zero_current_cells = sum(stats[, "total_precipitation_inches"] <= 1e-8, na.rm = TRUE),
    record_high_cells = sum(stats[, "record_high"] == 1, na.rm = TRUE),
    tied_record_high_cells = sum(stats[, "record_high_tied"] == 1, na.rm = TRUE),
    record_low_cells = sum(stats[, "record_low"] == 1, na.rm = TRUE),
    tied_record_low_cells = sum(stats[, "record_low_tied"] == 1, na.rm = TRUE),
    record_low_zero_withheld_cells = sum(stats[, "record_low_zero_withheld"] == 1, na.rm = TRUE),
    max_record_zero_fraction = 0.02)
  if (!any(supported)) {
    write.csv(summary, file.path(output_dir, "summary.csv"), row.names = FALSE)
    stop("No precipitation cells meet historical support requirements; see summary.csv.")
  }
  if (make_map) {
    period <- if (duration == 1L) format(target, "%B %Y") else paste0(
      format(min(prism_monthly_window(end, duration)), "%B %Y"), "-", format(target, "%B %Y"))
    plot <- southwest_raster_map(terra::rast(paths[["display_class"]]),
      states = southwest_state_boundaries(), counties = southwest_county_boundaries(),
      countries = southwest_country_boundaries(), cities = southwest_reference_cities(),
      title = paste0(duration, "-month precipitation ranking"),
      subtitle = paste0(period, " | matching windows ending ", min(years), "-", max(years)),
      caption = NULL, fill_label = "Historical percentile / record",
      palette = c("#543005", "#8c510a", "#bf812d", "#dfc27d", "#f5f5f5", "#80cdc1", "#35978f", "#01665e", "#253494"),
      palette_values = c(-0.5, 1, 6, 21.5, 50, 78.5, 94, 99, 100.5), limits = c(-1, 101),
      breaks = c(-1, 0, 2, 10, 33, 67, 90, 98, 100, 101), product_id = "monthly_precipitation_record_percentile",
      scale_type = "categorical")
    paths <- c(paths, map = file.path(output_dir, "precipitation-ranking.png"))
    save_southwest_map(plot, paths[["map"]], logo_path = southwest_brand_logo_path(),
      footer_text = prism_monthly_precipitation_footer(summary))
  }
  summary$elapsed_seconds <- proc.time()[["elapsed"]] - started
  write.csv(summary, file.path(output_dir, "summary.csv"), row.names = FALSE)
  writeLines(c("Precipitation windows sum monthly totals in inches without day weighting.",
    "Every month must be valid at the cell; missing or negative input makes the whole window unavailable.",
    "Compare the same ending calendar month and duration, with current year included once.",
    "Percentile = 100 * (count lower + 0.5 * count tied) / n; average ordinal ranks handle ties.",
    "Wet rank 1 = wettest; dry rank 1 = driest. Numerical tie tolerance is 1e-8 inch.",
    "Rank support defaults: at least 30 years and 90% of eligible comparison windows.",
    "1991-2020 mean and departure require at least 27 matching windows.",
    "zero_fraction reports the fraction of valid comparison windows with zero precipitation.",
    "If every valid historical total is zero, percentile is 50; do not label this a wet event.",
    "Record wet requires every eligible window and a maximum exceeding at least one historical value; tied maxima qualify.",
    "All-zero or other constant series are not highlighted as records. Missing-history cells can retain a percentile but not a record flag.",
    "Record dry includes tied minima only with complete history and at least one higher total.",
    "A zero total is highlighted as record dry only if zero windows are <=2% of the matching comparison record, including the current window.",
    "More common zero minima keep their ordinary percentile class; record_low_zero_withheld identifies this suppression.",
    "record_high/record_low and their tied flags are separate; display_class.tif uses -1 and 101 as record codes, not percentiles.",
    "Empirical precipitation percentiles are not SPI; no probability distribution was fitted.",
    "Local pilot only; no daily workflow, input files, website or publication changed."), file.path(output_dir, "methods.txt"))
  list(summary = summary, paths = paths, windows = windows)
}
