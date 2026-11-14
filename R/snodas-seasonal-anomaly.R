# Comparisons with the median of QC-screened seasonal peaks: local pilots and
# an explicit publication-ready archive build. No source downloads.
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

snodas_peak_departure_classes <- function(departure, reference, minimum_median_inches = 1) {
  if (length(departure) != length(reference) ||
      length(minimum_median_inches) != 1L || !is.finite(minimum_median_inches) ||
      minimum_median_inches <= 0 || any(is.finite(reference) & reference < 0))
    stop("Require matched departure/reference values and a positive median threshold.")
  labels <- c("<=-16", "-16 to -8", "-8 to -4", "-4 to -1", "-1 to +1",
    "+1 to +4", "+4 to +8", "+8 to +16", ">16",
    "Typically\nlittle snow", "Unavailable")
  classes <- as.character(cut(departure, c(-Inf, -16, -8, -4, -1, 1, 4, 8, 16, Inf),
    labels = labels[1:9], right = TRUE))
  supported <- is.finite(departure) & is.finite(reference)
  near <- supported & abs(departure) <= 1
  classes[near] <- labels[5L]
  classes[near & reference < minimum_median_inches] <- labels[10L]
  classes[!supported] <- labels[11L]
  factor(classes, levels = labels)
}

plot_snodas_peak_anomaly <- function(raster, water_year, years,
                                    states, counties, countries, cities,
                                    reference, minimum_median_inches = 1) {
  terra::compareGeom(raster, reference, stopOnError = TRUE, tolerance = 0)
  if (terra::nlyr(raster) != 1L || terra::nlyr(reference) != 1L)
    stop("Departure and median must be aligned single layers.")
  data <- terra::as.data.frame(c(raster, reference), xy = TRUE, na.rm = FALSE)
  names(data) <- c("x", "y", "departure", "reference")
  data$class <- snodas_peak_departure_classes(data$departure, data$reference, minimum_median_inches)
  colors <- c("#743b25", "#a3592d", "#ce8b53", "#ebcba5", "#f7f7f4",
    "#e1eef2", "#a9d2e5", "#5b9bc8", "#40589c", "#d2d6d8", "#ede8df")
  plot <- southwest_raster_map(raster = raster, states = states, counties = counties,
    countries = countries, cities = cities, mask_to_states = FALSE,
    title = sprintf("Peak SWE departure from median - WY%d", water_year),
    subtitle = sprintf("October %d-May %d | relative to WY%d-WY%d seasonal peaks",
      water_year - 1L, water_year, min(years), max(years)),
    caption = NULL, fill_label = "Peak SWE departure (inches)",
    scale_type = "continuous")
  plot$layers[[1L]] <- ggplot2::geom_tile(data = data,
    ggplot2::aes(x, y, fill = class), width = terra::res(raster)[1L],
    height = terra::res(raster)[2L], show.legend = TRUE)
  suppressMessages(plot + ggplot2::scale_fill_manual(
    values = stats::setNames(colors, levels(data$class)), drop = FALSE,
    name = "Peak SWE departure (inches)") +
    ggplot2::guides(fill = ggplot2::guide_legend(nrow = 1, title.position = "top",
      title.hjust = .5, label.position = "bottom", keywidth = grid::unit(1, "cm"),
      keyheight = grid::unit(.35, "cm"))) +
    ggplot2::theme(legend.text = ggplot2::element_text(size = 8)))
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
    render_maps = TRUE, minimum_median_inches = 1, publication_ready = FALSE) {
  if (!is.numeric(target_years) || !length(target_years) || anyNA(target_years) ||
      any(!target_years %in% years) || anyDuplicated(target_years) ||
      length(render_maps) != 1L || !is.logical(render_maps) || is.na(render_maps))
    stop("Choose unique target years in the reference period and a logical render_maps.")
  if (length(minimum_median_inches) != 1L || !is.numeric(minimum_median_inches) ||
      !is.finite(minimum_median_inches) || minimum_median_inches <= 0)
    stop("minimum_median_inches must be one positive number.")
  inventory <- snodas_peak_anomaly_inventory(years, archive_dir)
  if (!is.logical(publication_ready) || length(publication_ready) != 1L || is.na(publication_ready))
    stop("publication_ready must be TRUE or FALSE.")
  # Bump the display/method version below when changing fixed plotting or QC rules.
  signature <- digest::digest(list(inventory[c("water_year", "peak_md5", "coverage_md5", "quality_md5", "source_signature")],
    min_years, minimum_coverage, minimum_median_inches, publication_ready, render_maps,
    "seasonal-peak-anomaly-20261113-2"), algo = "sha256")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c(median_peak_swe = file.path(output_dir, "median_peak_swe.tif"),
             sample_years = file.path(output_dir, "sample_years.tif"))
  read_csv_cache <- function(name) {
    path <- file.path(output_dir, name)
    if (!file.exists(path)) return(NULL)
    tryCatch(utils::read.csv(path), error = function(e) NULL)
  }
  previous <- read_csv_cache("methods.csv")
  ref_hashes <- read_csv_cache("reference-checksums.csv")
  ref_reused <- !is.null(previous) && nrow(previous) == 1L && identical(previous$input_signature, signature) &&
    !is.null(ref_hashes) && identical(ref_hashes$file, unname(basename(paths))) && all(file.exists(paths)) &&
    identical(unname(tools::md5sum(paths)), ref_hashes$md5)
  if (ref_reused) {
    reference <- lapply(paths, terra::rast)
  } else {
    message("Preparing screened seasonal peak reference for ", length(years), " years.")
    peaks <- lapply(inventory$peak_path, terra::rast)
    coverage <- lapply(inventory$coverage_path, terra::rast)
    reference <- snodas_peak_anomaly_reference(peaks, coverage, min_years, minimum_coverage)
    for (name in names(paths)) terra::writeRaster(reference[[name]], paths[[name]],
      overwrite = TRUE, datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
    utils::write.csv(data.frame(file = unname(basename(paths)), md5 = unname(tools::md5sum(paths))),
      file.path(output_dir, "reference-checksums.csv"), row.names = FALSE)
  }
  utils::write.csv(inventory, file.path(output_dir, "source-inventory.csv"), row.names = FALSE)
  metadata <- data.frame(baseline_start_wy = min(years), baseline_end_wy = max(years),
    reference_years = length(years), min_years = min_years, minimum_coverage = minimum_coverage,
    reference_statistic = "median of one screened October-May peak per water year",
    target_in_reference = TRUE,
    publication_ready = publication_ready,
    minimum_median_inches = minimum_median_inches,
    departure_low_snow_rule = "Gray only when median peak < threshold and absolute departure <= 1 inch; larger departures retain anomaly colors",
    percent_formula = "100 * target seasonal peak / median seasonal peak",
    display_status_codes = "1=percentage;2=typical peak below threshold;3=unavailable data/support",
    input_signature = signature)
  utils::write.csv(metadata, file.path(output_dir, "methods.csv"), row.names = FALSE)
  if (render_maps) {
    states <- southwest_state_boundaries(); counties <- southwest_county_boundaries()
    countries <- southwest_country_boundaries(); cities <- southwest_reference_cities()
  }
  summaries <- lapply(as.integer(target_years), function(year) {
    i <- match(year, inventory$water_year)
    checkpoint <- file.path(output_dir, sprintf("wy%d-complete.rds", year))
    expected <- c(sprintf("wy%d-%s.tif", year, c("peak-swe-departure", "peak-swe-percent-median", "percent-display-status")),
      if (render_maps) sprintf("wy%d-%s.png", year, c("peak-swe-departure", "peak-swe-percent-median")))
    saved <- if (file.exists(checkpoint)) tryCatch(readRDS(checkpoint), error = function(e) NULL) else NULL
    if (ref_reused && is.list(saved) && identical(saved$signature, signature) &&
        identical(saved$files, expected) && all(file.exists(file.path(output_dir, expected))) &&
        identical(unname(tools::md5sum(file.path(output_dir, expected))), saved$md5)) {
      message("Seasonal snow anomaly WY", year, ": REUSED.")
      saved$summary$event <- "REUSED"
      return(saved$summary)
    }
    message("Seasonal snow anomaly WY", year, ": building two companion maps.")
    peak <- terra::rast(inventory$peak_path[i]); daily_coverage <- terra::rast(inventory$coverage_path[i])
    departure <- snodas_peak_anomaly_departure(peak, daily_coverage,
      reference$median_peak_swe, minimum_coverage)
    percent <- snodas_peak_percent_median(peak, daily_coverage, reference$median_peak_swe,
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
      states, counties, countries, cities, reference = reference$median_peak_swe,
      minimum_median_inches = minimum_median_inches), sub("\\.tif$", ".png", path),
      logo_path = southwest_brand_logo_path(), footer_text = sprintf(
        "Data: NOAA/NSIDC SNODAS%s\nReference: WY%d-WY%d | >=%d years; >=%.0f%% daily coverage\nGray: median peak <%g in. and departure within +/-1 in.; beige: unavailable",
        if (publication_ready) "" else " | Pilot, not published",
        min(years), max(years), min_years, 100 * minimum_coverage, minimum_median_inches))
    if (render_maps) save_southwest_map(plot_snodas_peak_percent_median(percent,
      year, years, minimum_median_inches, states, counties, countries, cities),
      sub("\\.tif$", ".png", percent_path), logo_path = southwest_brand_logo_path(),
      footer_text = sprintf("Data: NOAA/NSIDC SNODAS%s\nReference: WY%d-WY%d | Median >=%g in.; >=%d years; >=%.0f%% daily coverage",
        if (publication_ready) "" else " | Pilot, not published",
        min(years), max(years), minimum_median_inches, min_years, minimum_coverage * 100))
    values <- terra::values(departure, mat = FALSE)
    normal <- terra::values(reference$median_peak_swe, mat = FALSE)
    supported <- is.finite(values)
    percentages <- terra::values(percent$percent_of_median, mat = FALSE)
    status <- terra::values(percent$display_status, mat = FALSE)
    result <- data.frame(water_year = year, quality_status = inventory$quality_status[[i]],
      valid_cells = sum(supported), zero_median_cells = sum(supported & normal == 0, na.rm = TRUE),
      below_median_cells = sum(values < -1, na.rm = TRUE),
      above_median_cells = sum(values > 1, na.rm = TRUE),
      min_departure_inches = if (any(supported)) min(values[supported]) else NA_real_,
      max_departure_inches = if (any(supported)) max(values[supported]) else NA_real_,
      percent_valid_cells = sum(status == 1L), percent_low_median_cells = sum(status == 2L),
      percent_unavailable_cells = sum(status == 3L),
      max_percent_of_median = if (any(is.finite(percentages))) max(percentages, na.rm = TRUE) else NA_real_,
      path = path, percent_path = percent_path, percent_status_path = status_path,
      event = "BUILT")
    saveRDS(list(signature = signature, files = expected,
      md5 = unname(tools::md5sum(file.path(output_dir, expected))), summary = result), checkpoint)
    result
  })
  summary <- do.call(rbind, summaries)
  utils::write.csv(summary, file.path(output_dir, "pilot-summary.csv"), row.names = FALSE)
  output_files <- c(basename(paths), "methods.csv", "source-inventory.csv", "pilot-summary.csv",
    unlist(lapply(as.integer(target_years), function(year) c(
      sprintf("wy%d-%s.tif", year, c("peak-swe-departure", "peak-swe-percent-median", "percent-display-status")),
      if (render_maps) sprintf("wy%d-%s.png", year, c("peak-swe-departure", "peak-swe-percent-median"))))))
  utils::write.csv(data.frame(file = output_files,
    md5 = unname(tools::md5sum(file.path(output_dir, output_files)))),
    file.path(output_dir, "output-checksums.csv"), row.names = FALSE)
  message("SNODAS seasonal peak anomalies ready: ", output_dir,
    ". No downloads, historic-page changes, or publication.")
  invisible(list(paths = paths, summary = summary, inventory = inventory, methods = metadata))
}
