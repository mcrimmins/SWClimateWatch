# Read-only cached-input pilot. Not connected to current snow publication.

snodas_comparison_check_date <- function(raster, date) {
  if (!inherits(raster, "SpatRaster") || terra::nlyr(raster) != 1L)
    stop("Expected one daily SWE layer.")
  stamp <- as.Date(terra::time(raster))
  if (length(stamp) != 1L || is.na(stamp) || stamp != as.Date(date))
    stop("Daily SWE date does not match the requested endpoint.")
  values <- terra::values(raster, mat = FALSE)
  if (any(is.finite(values) & values < 0)) stop("Daily SWE cannot be negative.")
  invisible(TRUE)
}

snodas_daily_percent_swe <- function(observed, median_swe, sample_years, date,
                                    min_years = 18L, minimum_median_inches = 1) {
  snodas_comparison_check_date(observed, date)
  if (length(min_years) != 1L || !is.numeric(min_years) || !is.finite(min_years) ||
      min_years < 1L || min_years != floor(min_years) ||
      !inherits(sample_years, "SpatRaster") || terra::nlyr(sample_years) != 1L ||
      !terra::compareGeom(observed, sample_years, stopOnError = FALSE, tolerance = 0) ||
      !inherits(median_swe, "SpatRaster") || terra::nlyr(median_swe) != 1L ||
      !terra::compareGeom(observed, median_swe, stopOnError = FALSE, tolerance = 0))
    stop("Daily references must align and minimum year support must be a positive integer.")
  counts <- terra::values(sample_years, mat = FALSE)
  if (any(is.finite(counts) & (counts < 0 | counts != floor(counts))))
    stop("Reference year counts must be nonnegative integers.")
  reference <- terra::ifel(sample_years >= min_years, median_swe, NA)
  result <- snodas_percent_median_raster(observed, reference, minimum_median_inches)
  names(result$percent_of_median) <- "daily_swe_percent_of_median"
  terra::time(result$percent_of_median) <- as.Date(date)
  result
}

snodas_seven_day_swe_change <- function(current, previous, date) {
  date <- as.Date(date)
  snodas_comparison_check_date(current, date)
  snodas_comparison_check_date(previous, date - 7L)
  terra::compareGeom(current, previous, stopOnError = TRUE, tolerance = 0)
  change <- current - previous
  names(change) <- "seven_day_net_swe_change_inches"
  terra::time(change) <- date
  change
}

snodas_read_comparison_endpoint <- function(date, template,
    processed_dir = swc_paths$processed) {
  date <- snodas_date(date)
  checked <- snodas_cool_season_processed(data.frame(date = date,
    path = snodas_processed_path(date, "swe", processed_dir), complete = TRUE), processed_dir)
  if (!isTRUE(checked$complete[[1L]])) return(NULL)
  pair <- screen_snodas_analysis_pair(
    terra::rast(snodas_processed_path(date, "swe", processed_dir)),
    terra::rast(snodas_processed_path(date, "depth", processed_dir)))
  result <- snodas_align_common_grid(pair$swe, template)
  snodas_comparison_check_date(result, date)
  result
}

plot_snodas_seven_day_change <- function(raster, date, states, counties, countries, cities) {
  data <- terra::as.data.frame(raster, xy = TRUE, na.rm = TRUE)
  names(data)[3L] <- "change"
  labels <- c("<-4", "-4 to -2", "-2 to -1", "-1 to -0.25", "-0.25 to 0.25",
    "0.25-1", "1-2", "2-4", ">=4")
  data$class <- cut(data$change, c(-Inf, -4, -2, -1, -.25, .25, 1, 2, 4, Inf),
    labels = labels, right = FALSE)
  colors <- c("#8c510a", "#bf812d", "#dfc27d", "#f1e0b5", "#f7f7f4",
    "#d1e5f0", "#92c5de", "#4393c3", "#081d58")
  plot <- southwest_raster_map(raster, states = states, counties = counties,
    countries = countries, cities = cities, mask_to_states = FALSE,
    title = "Seven-day change in snow water equivalent",
    subtitle = sprintf("%s to %s | Net modeled snowpack gain or loss", as.Date(date) - 7L, as.Date(date)),
    caption = NULL, fill_label = "SWE change (inches)", scale_type = "continuous")
  plot$layers[[1L]] <- ggplot2::geom_tile(data = data, ggplot2::aes(x, y, fill = class),
    width = terra::res(raster)[1L], height = terra::res(raster)[2L], show.legend = TRUE)
  suppressMessages(plot + ggplot2::scale_fill_manual(values = stats::setNames(colors, labels),
    drop = FALSE, name = "SWE change (inches)") +
    ggplot2::guides(fill = ggplot2::guide_legend(nrow = 1, title.position = "top",
      title.hjust = .5, label.position = "bottom")))
}

build_snodas_daily_comparison_pilot <- function(
    dates = as.Date(c("2023-03-01", "2024-04-15", "2025-02-15")),
    output_dir = file.path("data", "diagnostics", "snodas-daily-comparison-pilot"),
    min_years = 18L, minimum_median_inches = 1, processed_dir = swc_paths$processed,
    render_maps = TRUE) {
  dates <- as.Date(dates)
  if (!length(dates) || anyNA(dates) || anyDuplicated(dates) ||
      !all(format(dates, "%m-%d") %in% snodas_climatology_month_days()) ||
      length(min_years) != 1L || !is.numeric(min_years) || !is.finite(min_years) ||
      min_years < 1 || min_years > 21 || min_years != floor(min_years) ||
      length(render_maps) != 1L || !is.logical(render_maps) || is.na(render_maps))
    stop("Choose unique October-May pilot dates, 1-21 reference years and logical render_maps.")
  template <- snodas_common_grid()
  if (render_maps) {
    states <- southwest_state_boundaries(); counties <- southwest_county_boundaries()
    countries <- southwest_country_boundaries(); cities <- southwest_reference_cities()
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  inputs <- list()
  rows <- lapply(seq_along(dates), function(i) {
    date <- dates[i]
    # Validate the existing 15-year-floor reference exactly as built. Apply the
    # stricter pilot floor to its saved sample counts, not by changing its spec.
    observed <- load_snodas_swe_map_pilot_inputs(date, processed_dir = processed_dir, template = template)
    percent <- snodas_daily_percent_swe(observed$observed, observed$median_swe,
      observed$sample_years, date, min_years, minimum_median_inches)
    prior <- snodas_read_comparison_endpoint(date - 7L, template, processed_dir)
    change <- if (is.null(prior)) NULL else snodas_seven_day_swe_change(observed$observed, prior, date)
    prefix <- file.path(output_dir, as.character(date))
    terra::writeRaster(percent$percent_of_median, paste0(prefix, "-percent-median.tif"), overwrite = TRUE,
      datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
    terra::writeRaster(percent$display_status, paste0(prefix, "-percent-status.tif"), overwrite = TRUE,
      datatype = "INT1U", gdal = "COMPRESS=DEFLATE")
    if (!is.null(change)) terra::writeRaster(change, paste0(prefix, "-swe-change-7day.tif"),
      overwrite = TRUE, datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
    if (is.null(change)) {
      stale <- paste0(prefix, c("-swe-change-7day.tif", "-swe-change-7day.png"))
      stale <- stale[file.exists(stale)]
      if (length(stale) && any(!file.remove(stale))) stop("Could not remove stale pilot change outputs.")
    }
    if (render_maps) {
      save_southwest_map(plot_snodas_peak_percent_median(percent, 0L, 2005:2025,
        minimum_median_inches, states, counties, countries, cities,
        title = "Snow water equivalent as percent of median",
        subtitle = paste(date, "| WY2005-WY2025 centered five-day daily reference"),
        reference_label = "Typical SWE", fill_label = "SWE (% of date-specific median)"),
        paste0(prefix, "-percent-median.png"), logo_path = southwest_brand_logo_path(),
        footer_text = sprintf("Data: NOAA/NSIDC SNODAS | Local pilot\nMedian >=%g in.; >=%d reference years; paired daily QC", minimum_median_inches, min_years))
      if (!is.null(change)) save_southwest_map(plot_snodas_seven_day_change(change, date,
        states, counties, countries, cities), paste0(prefix, "-swe-change-7day.png"),
        logo_path = southwest_brand_logo_path(),
        footer_text = "Data: NOAA/NSIDC SNODAS | Local pilot\nExact seven-day endpoints; not snowfall or melt alone")
    }
    source_dates <- if (is.null(prior)) date else c(date, date - 7L)
    sources <- c(unlist(lapply(source_dates, function(d) vapply(c("swe", "depth"),
      function(v) snodas_processed_path(as.Date(d, origin = "1970-01-01"), v, processed_dir), character(1)))),
      unname(observed$reference_paths))
    inputs[[i]] <<- data.frame(date = as.character(date), path = sources,
      md5 = unname(tools::md5sum(sources)))
    flags <- terra::values(percent$display_status, mat = FALSE)
    differences <- if (is.null(change)) numeric() else terra::values(change, mat = FALSE)
    valid <- is.finite(differences)
    data.frame(date = as.character(date), prior_date = as.character(date - 7L),
      percent_valid_cells = sum(flags == 1), low_median_cells = sum(flags == 2),
      unavailable_percent_cells = sum(flags == 3), change_available = !is.null(change),
      valid_change_cells = sum(valid),
      minimum_change_inches = if (any(valid)) min(differences[valid]) else NA_real_,
      maximum_change_inches = if (any(valid)) max(differences[valid]) else NA_real_,
      change_note = if (is.null(change)) "Exact prior endpoint missing or unverified; no substitution" else "Net SWE change, not snowfall")
  })
  summary <- do.call(rbind, rows)
  utils::write.csv(summary, file.path(output_dir, "pilot-summary.csv"), row.names = FALSE)
  utils::write.csv(do.call(rbind, inputs), file.path(output_dir, "source-checksums.csv"), row.names = FALSE)
  utils::write.csv(data.frame(reference = "WY2005-WY2025 centered five-day yearly reference",
    min_years = min_years, minimum_median_inches = minimum_median_inches,
    change_days = 7L, daily_qc = "paired SWE/depth screening; exact-date endpoints"),
    file.path(output_dir, "methods.csv"), row.names = FALSE)
  message("Daily SNODAS comparison pilot ready: ", output_dir, "; no downloads or publication.")
  invisible(list(summary = summary, output_dir = output_dir))
}
