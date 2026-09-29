# Unpublished winter SNODAS SWE map pair. Source the SNODAS daily baseline and
# Southwest map utilities first. Outputs stay under data/diagnostics/.

snodas_swe_departure_raster <- function(observed, median_swe, date) {
  date <- snodas_date(date)
  if (!inherits(observed, "SpatRaster") ||
      !inherits(median_swe, "SpatRaster") ||
      terra::nlyr(observed) != 1L || terra::nlyr(median_swe) != 1L ||
      !terra::compareGeom(observed, median_swe, stopOnError = FALSE,
                          tolerance = 0)) {
    stop("Observed and median SNODAS SWE must be single layers on the ",
         "same grid.", call. = FALSE)
  }
  observed_time <- as.Date(terra::time(observed))
  if (length(observed_time) != 1L || is.na(observed_time) ||
      observed_time != date) {
    stop("Observed SNODAS SWE date does not match the requested date.",
         call. = FALSE)
  }
  departure <- observed - median_swe
  names(departure) <- paste0("snodas_swe_departure_", date)
  terra::time(departure) <- date
  departure
}

load_snodas_swe_map_pilot_inputs <- function(
    date = as.Date("2025-02-15"),
    years = 2005:2025, snow_threshold_inches = 0.1,
    min_valid_days = 3L, min_years = 15L,
    processed_dir = swc_paths$processed,
    climatology_root = snodas_climatology_output_root(years, processed_dir),
    template = snodas_common_grid()) {
  date <- snodas_date(date)
  month_day <- format(date, "%m-%d")
  if (!month_day %in% snodas_climatology_month_days()) {
    stop("Choose an October-May SNODAS date for this pilot.",
         call. = FALSE)
  }
  processed <- snodas_cool_season_processed(data.frame(
    date = date, path = snodas_processed_path(date, "swe", processed_dir),
    complete = TRUE
  ), processed_dir)
  if (!processed$complete) {
    stop("Missing or unverified processed SNODAS SWE/depth pair: ", date,
         call. = FALSE)
  }
  reference_paths <- snodas_climatology_day_paths(climatology_root,
                                                   month_day)
  spec <- snodas_climatology_spec(month_day, years,
                                  snow_threshold_inches,
                                  min_valid_days, min_years)
  if (!snodas_climatology_day_complete(reference_paths, spec)) {
    stop("Missing or invalid SNODAS daily reference for ", month_day,
         call. = FALSE)
  }
  screened <- screen_snodas_analysis_pair(
    terra::rast(snodas_processed_path(date, "swe", processed_dir)),
    terra::rast(snodas_processed_path(date, "depth", processed_dir))
  )
  observed <- snodas_align_common_grid(screened$swe, template)
  names(observed) <- paste0("snodas_swe_", date)
  terra::time(observed) <- date
  median_swe <- terra::rast(reference_paths[["median_swe"]])
  departure <- snodas_swe_departure_raster(observed, median_swe, date)
  list(date = date, observed = observed, median_swe = median_swe,
       departure = departure, sample_years = terra::rast(
         reference_paths[["sample_years"]]),
       qc = screened$summary, reference_paths = reference_paths)
}

snodas_swe_map_review_summary <- function(
    observed, median_swe, date, screen_qc,
    review_threshold_inches = 50) {
  date <- snodas_date(date)
  if (!inherits(observed, "SpatRaster") ||
      !inherits(median_swe, "SpatRaster") ||
      terra::nlyr(observed) != 1L || terra::nlyr(median_swe) != 1L ||
      !terra::compareGeom(observed, median_swe, stopOnError = FALSE,
                          tolerance = 0)) {
    stop("SWE review requires observed and reference grids to align.",
         call. = FALSE)
  }
  if (!is.numeric(review_threshold_inches) ||
      length(review_threshold_inches) != 1L ||
      !is.finite(review_threshold_inches) ||
      review_threshold_inches <= 30) {
    stop("The SWE review threshold must exceed 30 inches.",
         call. = FALSE)
  }
  if (!is.data.frame(screen_qc) || nrow(screen_qc) != 1L ||
      !"excluded_cells" %in% names(screen_qc)) {
    stop("Expected one paired-screening QC row.", call. = FALSE)
  }
  observed_values <- terra::values(observed, mat = FALSE)
  median_values <- terra::values(median_swe, mat = FALSE)
  valid_observed <- observed_values[is.finite(observed_values)]
  valid_median <- median_values[is.finite(median_values)]
  high_observed <- sum(valid_observed >= review_threshold_inches)
  high_median <- sum(valid_median >= review_threshold_inches)
  data.frame(
    date = as.character(date),
    review_threshold_inches = review_threshold_inches,
    screened_excluded_cells = screen_qc$excluded_cells[[1L]],
    observed_valid_cells = length(valid_observed),
    observed_max_inches = if (length(valid_observed)) {
      max(valid_observed)
    } else NA_real_,
    observed_cells_over_30_inches = sum(valid_observed > 30),
    observed_cells_for_review = high_observed,
    reference_max_inches = if (length(valid_median)) {
      max(valid_median)
    } else NA_real_,
    reference_cells_for_review = high_median,
    high_swe_review_flag = high_observed > 0L || high_median > 0L,
    stringsAsFactors = FALSE
  )
}

snodas_swe_map_pilot_plot <- function(
    raster, date, kind = c("observed", "departure"),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),
    scale_type = c("categorical", "continuous")) {
  kind <- match.arg(kind)
  scale_type <- match.arg(scale_type)
  date_label <- sub(" 0", " ", format(as.Date(date), "%B %d, %Y"),
                    fixed = TRUE)
  common <- list(
    raster = raster, states = states, counties = counties,
    countries = countries, cities = cities,
    caption = NULL, mask_to_states = FALSE, scale_type = scale_type,
    product_id = paste0("snodas_swe_", kind)
  )
  if (kind == "observed") {
    if (scale_type == "categorical") {
      return(do.call(southwest_raster_map, c(common, list(
        title = "Snow water equivalent (inches)",
        subtitle = date_label,
        fill_label = "SWE (inches)",
        palette = c("#f7f7f4", "#d7e9f1", "#a6cfe2", "#6baed6",
                    "#3182bd", "#225ea8", "#253494", "#54278f",
                    "#8b176a", "#67104f"),
        palette_values = c(0, 0.1, 1, 2, 4, 8, 12, 20, 30, 90),
        limits = c(0, 90)
      ))))
    }
    return(do.call(southwest_raster_map, c(common, list(
      title = "Snow water equivalent (inches)",
      subtitle = date_label,
      fill_label = "SWE (inches)",
      palette = c("#f7f7f4", "#d7e9f1", "#a6cfe2", "#6baed6",
                  "#3182bd", "#225ea8", "#253494", "#54278f",
                  "#8b176a", "#67104f"),
      palette_values = c(0, 0.1, 1, 2, 4, 8, 12, 20, 30, 40),
      limits = c(0, 40),
      breaks = c(0, 4, 8, 12, 20, 30, 40),
      labels = c("0", "4", "8", "12", "20", "30", "40")
    ))))
  }
  if (scale_type == "categorical") {
    return(do.call(southwest_raster_map, c(common, list(
      title = "Snow water equivalent departure (inches)",
      subtitle = paste0(date_label,
                        " relative to WY2005-WY2025 centered 5-day median"),
      fill_label = "Departure (inches)",
      palette = c("#59301f", "#8e4725", "#ba713d", "#ddb079",
                  "#f5eee4", "#f7f7f4", "#d9eaf0", "#7bb8d7",
                  "#3379b4", "#413585", "#2c1e63"),
      palette_values = c(-90, -16, -8, -4, -1, 0, 1, 4, 8, 16, 90),
      limits = c(-90, 90)
    ))))
  }
  do.call(southwest_raster_map, c(common, list(
    title = "Snow water equivalent departure (inches)",
    subtitle = paste0(date_label,
                      " relative to WY2005-WY2025 centered 5-day median"),
    fill_label = "Departure (inches)",
    palette = c("#59301f", "#8e4725", "#ba713d", "#ddb079",
                "#f5eee4", "#f7f7f4", "#d9eaf0", "#7bb8d7",
                "#3379b4", "#413585", "#2c1e63"),
    palette_values = c(-24, -16, -8, -4, -1, 0, 1, 4, 8, 16, 24),
    limits = c(-24, 24),
    breaks = c(-24, -16, -8, 0, 8, 16, 24),
    labels = c("-24", "-16", "-8", "0", "+8", "+16", "+24")
  )))
}

build_snodas_swe_map_pilot <- function(
    date = as.Date("2025-02-15"),
    output_dir = file.path("data", "diagnostics", "snodas-map-pilot",
                           as.character(as.Date(date))),
    processed_dir = swc_paths$processed,
    climatology_root = snodas_climatology_output_root(
      2005:2025, processed_dir),
    logo_path = southwest_brand_logo_path(),
    overwrite = FALSE,
    scale_type = c("categorical", "continuous")) {
  scale_type <- match.arg(scale_type)
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    stop("`overwrite` must be TRUE or FALSE.", call. = FALSE)
  }
  suffix <- if (scale_type == "categorical") "-categorical" else ""
  paths <- file.path(output_dir, paste0(
    c("swe-observed", "swe-departure"), suffix, ".png"
  ))
  names(paths) <- c("observed", "departure")
  if (!overwrite && any(file.exists(paths))) {
    stop("SNODAS map pilot output already exists; inspect it or use ",
         "overwrite=TRUE.", call. = FALSE)
  }
  inputs <- load_snodas_swe_map_pilot_inputs(
    date, processed_dir = processed_dir,
    climatology_root = climatology_root
  )
  review <- snodas_swe_map_review_summary(
    inputs$observed, inputs$median_swe, inputs$date, inputs$qc
  )
  gate <- assess_snodas_swe_map_quality(inputs, review)
  states <- southwest_state_boundaries()
  counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries()
  cities <- southwest_reference_cities()
  plots <- list(
    observed = snodas_swe_map_pilot_plot(
      inputs$observed, inputs$date, "observed", states, counties,
      countries, cities, scale_type
    ),
    departure = snodas_swe_map_pilot_plot(
      inputs$departure, inputs$date, "departure", states, counties,
      countries, cities, scale_type
    )
  )
  footer <- c(
    observed = "Data source: NOAA/NSIDC SNODAS",
    departure = paste0("Data source: NOAA/NSIDC SNODAS\n",
                       "Reference period: WY2005-WY2025")
  )
  for (name in names(plots)) {
    save_southwest_map(plots[[name]], paths[[name]],
                       logo_path = logo_path, footer_text = footer[[name]])
    message("Wrote unpublished SNODAS ", name, " map: ", paths[[name]])
  }
  review_path <- file.path(output_dir, "quality-review.csv")
  utils::write.csv(review, review_path, row.names = FALSE)
  gate_path <- file.path(output_dir, "quality-gate.csv")
  utils::write.csv(gate, gate_path, row.names = FALSE)
  if (review$high_swe_review_flag) {
    message("High SWE review flag for ", inputs$date,
            ": inspect the modeled peak before publication.")
  }
  list(date = inputs$date, scale_type = scale_type, paths = paths, qc = inputs$qc,
       review = review, review_path = review_path, gate = gate,
       gate_path = gate_path,
       observed = inputs$observed, departure = inputs$departure,
       median_swe = inputs$median_swe)
}
