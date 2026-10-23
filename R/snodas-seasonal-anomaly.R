# Local-only pilot: differences from the median of QC-screened seasonal peaks.
# Never use the calendar-day SWE median as the reference for this product.

snodas_peak_anomaly_inventory <- function(years = 2005:2025,
    archive_dir = file.path("data", "diagnostics", "snodas-seasonal-archive")) {
  if (!is.numeric(years) || !length(years) || anyNA(years) ||
      any(years != floor(years) | years < 2005 | years > 2025) || anyDuplicated(years))
    stop("Choose unique completed reference water years from 2005-2025.")
  rows <- lapply(sort(as.integer(years)), function(year) {
    directory <- file.path(archive_dir, sprintf("wy%d", year))
    paths <- file.path(directory, c("complete.csv", "quality-summary.csv", "peak_swe.tif", "coverage.tif"))
    if (!all(file.exists(paths))) stop("Missing seasonal archive inputs for WY", year)
    marker <- utils::read.csv(paths[1L], stringsAsFactors = FALSE)
    quality <- utils::read.csv(paths[2L], stringsAsFactors = FALSE)
    required <- c("source_signature", "peak_swe_md5", "coverage_md5", "quality_md5")
    if (nrow(marker) != 1L || nrow(quality) != 1L ||
        !all(required %in% names(marker)) ||
        !all(c("water_year", "source_signature", "status", "known_missing_days", "reasons") %in% names(quality)) ||
        anyNA(marker[required]) || anyNA(quality[c("water_year", "source_signature", "status", "known_missing_days")]) ||
        quality$water_year != year ||
        !identical(marker$source_signature, quality$source_signature) ||
        !quality$status %in% c("PASS", "REVIEW"))
      stop("Invalid or failed seasonal archive provenance for WY", year)
    hashes <- unname(tools::md5sum(paths[c(3L, 4L, 2L)]))
    if (anyNA(hashes) || !identical(hashes, unname(unlist(marker[c("peak_swe_md5", "coverage_md5", "quality_md5")]))))
      stop("Seasonal archive checksums changed for WY", year, "; rebuild/verify the archive first.")
    data.frame(water_year = year, peak_path = paths[3L], coverage_path = paths[4L],
      peak_md5 = hashes[1L], coverage_md5 = hashes[2L], quality_md5 = hashes[3L],
      source_signature = marker$source_signature, quality_status = quality$status,
      known_missing_days = quality$known_missing_days, quality_reasons = quality$reasons,
      stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

snodas_peak_anomaly_screen <- function(peak, coverage, minimum_coverage = 0.95) {
  if (!inherits(peak, "SpatRaster") || !inherits(coverage, "SpatRaster") ||
      terra::nlyr(peak) != 1L || terra::nlyr(coverage) != 1L ||
      !terra::compareGeom(peak, coverage, stopOnError = FALSE, tolerance = 0) ||
      length(minimum_coverage) != 1L || !is.numeric(minimum_coverage) ||
      !is.finite(minimum_coverage) || minimum_coverage <= 0 || minimum_coverage > 1)
    stop("Seasonal peak and coverage must be aligned single layers with a valid coverage threshold.")
  values <- terra::values(peak, mat = FALSE)
  support <- terra::values(coverage, mat = FALSE)
  if (any(is.finite(values) & values < 0) ||
      any(is.finite(support) & (support < 0 | support > 1)) ||
      any(is.finite(values) & !is.finite(support)))
    stop("Invalid peak SWE or seasonal coverage values.")
  # Archive coverage is stored as Float32; allow only storage-roundoff tolerance.
  eligible <- is.finite(values) & is.finite(support) & support >= minimum_coverage - 1e-7
  values[!eligible] <- NA_real_
  terra::setValues(peak, values)
}

snodas_peak_anomaly_reference <- function(peaks, coverage, min_years = 18L,
                                          minimum_coverage = 0.95) {
  if (!is.list(peaks) || !length(peaks) || !is.list(coverage) || length(peaks) != length(coverage) ||
      length(min_years) != 1L || !is.numeric(min_years) || !is.finite(min_years) ||
      min_years != floor(min_years) || min_years < 1L || min_years > length(peaks))
    stop("Require matched peak/coverage lists and a valid minimum year count.")
  screened <- lapply(seq_along(peaks), function(i) {
    terra::compareGeom(peaks[[1L]], peaks[[i]], stopOnError = TRUE, tolerance = 0)
    snodas_peak_anomaly_screen(peaks[[i]], coverage[[i]], minimum_coverage)
  })
  stack <- do.call(c, screened)
  sample_years <- terra::app(!is.na(stack), fun = "sum")
  median <- terra::app(stack, fun = "median", na.rm = TRUE)
  median <- terra::ifel(sample_years >= min_years, median, NA)
  names(median) <- "median_seasonal_peak_swe_inches"
  names(sample_years) <- "valid_reference_years"
  list(median_peak_swe = median, sample_years = sample_years)
}

snodas_peak_anomaly_departure <- function(peak, coverage, reference, minimum_coverage = 0.95) {
  screened <- snodas_peak_anomaly_screen(peak, coverage, minimum_coverage)
  terra::compareGeom(screened, reference, stopOnError = TRUE, tolerance = 0)
  if (terra::nlyr(reference) != 1L) stop("Reference must be a single seasonal median layer.")
  values <- terra::values(reference, mat = FALSE)
  if (any(is.finite(values) & values < 0)) stop("Median peak SWE cannot be negative.")
  departure <- screened - reference
  names(departure) <- "seasonal_peak_swe_departure_inches"
  departure
}

plot_snodas_peak_anomaly <- function(raster, water_year, years,
                                    states, counties, countries, cities) {
  southwest_raster_map(raster = raster, states = states, counties = counties,
    countries = countries, cities = cities, mask_to_states = FALSE,
    title = sprintf("Peak SWE departure from median - WY%d", water_year),
    subtitle = sprintf("October %d-May %d | relative to WY%d-WY%d seasonal peaks",
      water_year - 1L, water_year, min(years), max(years)),
    caption = NULL, fill_label = "Peak SWE departure (inches)",
    scale_type = "categorical", product_id = "snodas_swe_departure",
    palette = c("#59301f", "#8e4725", "#ba713d", "#ddb079", "#f7f7f4",
      "#d9eaf0", "#7bb8d7", "#3379b4", "#413585"),
    palette_values = c(-90, -16, -8, -4, 0, 4, 8, 16, 90), limits = c(-90, 90))
}

snodas_peak_percent_median <- function(peak, coverage, reference,
    minimum_coverage = 0.95, minimum_median_inches = 1) {
  screened <- snodas_peak_anomaly_screen(peak, coverage, minimum_coverage)
  snodas_percent_median_raster(screened, reference, minimum_median_inches)
}

# Shared guarded ratio for seasonal peaks and single-day SWE. Callers perform
# the period-specific QC first; no seasonal coverage rule is applied to a day.
snodas_percent_median_raster <- function(screened, reference, minimum_median_inches = 1) {
  if (length(minimum_median_inches) != 1L || !is.numeric(minimum_median_inches) ||
      !is.finite(minimum_median_inches) || minimum_median_inches <= 0)
    stop("minimum_median_inches must be one positive number.")
  if (!inherits(screened, "SpatRaster") || terra::nlyr(screened) != 1L ||
      !inherits(reference, "SpatRaster") || terra::nlyr(reference) != 1L ||
      !terra::compareGeom(screened, reference, stopOnError = FALSE, tolerance = 0))
    stop("Median peak SWE must be one aligned reference layer.")
  observed <- terra::values(screened, mat = FALSE)
  if (any(is.finite(observed) & observed < 0)) stop("Observed SWE cannot be negative.")
  median <- terra::values(reference, mat = FALSE)
  if (any(is.finite(median) & median < 0)) stop("Median peak SWE cannot be negative.")
  supported <- is.finite(observed) & is.finite(median)
  eligible <- supported & median >= minimum_median_inches
  percent <- rep(NA_real_, length(observed))
  # Do not divide first and mask later: zero/tiny medians never enter a ratio.
  percent[eligible] <- 100 * observed[eligible] / median[eligible]
  status <- rep(3L, length(observed)) # unavailable target or reference support
  status[supported & !eligible] <- 2L # valid data, insufficient typical snow
  status[eligible] <- 1L
  values <- terra::setValues(screened, percent)
  names(values) <- "seasonal_peak_swe_percent_of_median"
  flags <- terra::setValues(screened, status)
  names(flags) <- "display_status_1_percent_2_low_median_3_unavailable"
  list(percent_of_median = values, display_status = flags)
}

snodas_peak_percent_classes <- function(percent, status, minimum_median_inches = 1,
                                       reference_label = "Typical peak") {
  labels <- c("<50%", "50-75%", "75-90%", "90-110%", "110-125%",
    "125-150%", "150-200%", ">=200%",
    sprintf("%s\n<%g inch", reference_label, minimum_median_inches), "Unavailable")
  classes <- as.character(cut(percent, c(-Inf, 50, 75, 90, 110, 125, 150, 200, Inf),
    labels = labels[1:8], right = FALSE))
  classes[status == 2L] <- labels[9L]
  classes[status == 3L] <- labels[10L]
  factor(classes, levels = labels)
}

plot_snodas_peak_percent_median <- function(product, water_year, years, minimum_median_inches,
    states, counties, countries, cities, title = NULL, subtitle = NULL,
    reference_label = "Typical peak", fill_label = "Peak SWE (% of median)") {
  raster <- product$percent_of_median
  data <- terra::as.data.frame(c(raster, product$display_status), xy = TRUE, na.rm = FALSE)
  names(data) <- c("x", "y", "percent", "status")
  data$class <- snodas_peak_percent_classes(data$percent, data$status, minimum_median_inches, reference_label)
  colors <- c("#8c510a", "#bf812d", "#dfc27d", "#f7f7f4", "#d1e5f0",
    "#92c5de", "#4393c3", "#081d58", "#d2d6d8", "#ede8df")
  plot <- southwest_raster_map(raster, states = states, counties = counties,
    countries = countries, cities = cities, mask_to_states = FALSE,
    title = if (is.null(title)) sprintf("Peak SWE as percent of median - WY%d", water_year) else title,
    subtitle = if (is.null(subtitle)) sprintf("October %d-May %d | relative to WY%d-WY%d seasonal peaks",
      water_year - 1L, water_year, min(years), max(years)) else subtitle,
    caption = NULL, fill_label = fill_label, scale_type = "continuous")
  plot$layers[[1L]] <- ggplot2::geom_tile(data = data,
    ggplot2::aes(x, y, fill = class), width = terra::res(raster)[1L], height = terra::res(raster)[2L],
    show.legend = TRUE)
  suppressMessages(plot + ggplot2::scale_fill_manual(
    values = stats::setNames(colors, levels(data$class)), drop = FALSE,
    name = fill_label) +
    ggplot2::guides(fill = ggplot2::guide_legend(nrow = 1, title.position = "top",
      title.hjust = .5, label.position = "bottom", keywidth = grid::unit(1.1, "cm"),
      keyheight = grid::unit(.35, "cm"))) +
    ggplot2::theme(legend.text = ggplot2::element_text(size = 8)))
}

build_snodas_seasonal_anomaly_pilot <- function(target_years = c(2005L, 2018L, 2024L),
    years = 2005:2025, min_years = 18L, minimum_coverage = 0.95,
    archive_dir = file.path("data", "diagnostics", "snodas-seasonal-archive"),
    output_dir = file.path("data", "diagnostics", "snodas-seasonal-anomaly-pilot"),
    render_maps = TRUE, minimum_median_inches = 1) {
  if (!is.numeric(target_years) || !length(target_years) || anyNA(target_years) ||
      any(!target_years %in% years) || anyDuplicated(target_years) ||
      length(render_maps) != 1L || !is.logical(render_maps) || is.na(render_maps))
    stop("Choose unique target years in the reference period and a logical render_maps.")
  if (length(minimum_median_inches) != 1L || !is.numeric(minimum_median_inches) ||
      !is.finite(minimum_median_inches) || minimum_median_inches <= 0)
    stop("minimum_median_inches must be one positive number.")
  inventory <- snodas_peak_anomaly_inventory(years, archive_dir)
  peaks <- lapply(inventory$peak_path, terra::rast)
  coverage <- lapply(inventory$coverage_path, terra::rast)
  reference <- snodas_peak_anomaly_reference(peaks, coverage, min_years, minimum_coverage)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c(median_peak_swe = file.path(output_dir, "median_peak_swe.tif"),
             sample_years = file.path(output_dir, "sample_years.tif"))
  for (name in names(paths)) terra::writeRaster(reference[[name]], paths[[name]],
    overwrite = TRUE, datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
  utils::write.csv(inventory, file.path(output_dir, "source-inventory.csv"), row.names = FALSE)
  metadata <- data.frame(baseline_start_wy = min(years), baseline_end_wy = max(years),
    reference_years = length(years), min_years = min_years, minimum_coverage = minimum_coverage,
    reference_statistic = "median of one screened October-May peak per water year",
    target_in_reference = TRUE,
    minimum_median_inches = minimum_median_inches,
    percent_formula = "100 * target seasonal peak / median seasonal peak",
    display_status_codes = "1=percentage;2=typical peak below threshold;3=unavailable data/support",
    input_signature = digest::digest(list(inventory, min_years, minimum_coverage,
      minimum_median_inches), algo = "sha256"))
  utils::write.csv(metadata, file.path(output_dir, "methods.csv"), row.names = FALSE)
  if (render_maps) {
    states <- southwest_state_boundaries(); counties <- southwest_county_boundaries()
    countries <- southwest_country_boundaries(); cities <- southwest_reference_cities()
  }
  summaries <- lapply(as.integer(target_years), function(year) {
    i <- match(year, inventory$water_year)
    departure <- snodas_peak_anomaly_departure(peaks[[i]], coverage[[i]],
      reference$median_peak_swe, minimum_coverage)
    percent <- snodas_peak_percent_median(peaks[[i]], coverage[[i]], reference$median_peak_swe,
      minimum_coverage, minimum_median_inches)
    path <- file.path(output_dir, sprintf("wy%d-peak-swe-departure.tif", year))
    terra::writeRaster(departure, path, overwrite = TRUE, datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
    percent_path <- file.path(output_dir, sprintf("wy%d-peak-swe-percent-median.tif", year))
    status_path <- file.path(output_dir, sprintf("wy%d-percent-display-status.tif", year))
    terra::writeRaster(percent$percent_of_median, percent_path, overwrite = TRUE,
      datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
    terra::writeRaster(percent$display_status, status_path, overwrite = TRUE,
      datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
    if (render_maps) save_southwest_map(plot_snodas_peak_anomaly(departure, year, years,
      states, counties, countries, cities), sub("\\.tif$", ".png", path),
      logo_path = southwest_brand_logo_path(), footer_text = sprintf(
        "Data: NOAA/NSIDC SNODAS | Pilot, not published\nReference: WY%d-WY%d | >=%d years; >=%.0f%% daily coverage",
        min(years), max(years), min_years, 100 * minimum_coverage))
    if (render_maps) save_southwest_map(plot_snodas_peak_percent_median(percent,
      year, years, minimum_median_inches, states, counties, countries, cities),
      sub("\\.tif$", ".png", percent_path), logo_path = southwest_brand_logo_path(),
      footer_text = sprintf("Data: NOAA/NSIDC SNODAS | Pilot, not published\nReference: WY%d-WY%d | Median >=%g in.; >=%d years; >=%.0f%% daily coverage",
        min(years), max(years), minimum_median_inches, min_years, minimum_coverage * 100))
    values <- terra::values(departure, mat = FALSE)
    normal <- terra::values(reference$median_peak_swe, mat = FALSE)
    supported <- is.finite(values)
    percentages <- terra::values(percent$percent_of_median, mat = FALSE)
    status <- terra::values(percent$display_status, mat = FALSE)
    data.frame(water_year = year, quality_status = inventory$quality_status[[i]],
      valid_cells = sum(supported), zero_median_cells = sum(supported & normal == 0, na.rm = TRUE),
      below_median_cells = sum(values < -1, na.rm = TRUE),
      above_median_cells = sum(values > 1, na.rm = TRUE),
      min_departure_inches = if (any(supported)) min(values[supported]) else NA_real_,
      max_departure_inches = if (any(supported)) max(values[supported]) else NA_real_,
      percent_valid_cells = sum(status == 1L), percent_low_median_cells = sum(status == 2L),
      percent_unavailable_cells = sum(status == 3L),
      max_percent_of_median = if (any(is.finite(percentages))) max(percentages, na.rm = TRUE) else NA_real_,
      path = path, percent_path = percent_path, percent_status_path = status_path)
  })
  summary <- do.call(rbind, summaries)
  utils::write.csv(summary, file.path(output_dir, "pilot-summary.csv"), row.names = FALSE)
  message("SNODAS seasonal peak anomaly pilot ready: ", output_dir,
    ". No downloads, historic-page changes, or publication.")
  invisible(list(paths = paths, summary = summary, inventory = inventory, methods = metadata))
}
