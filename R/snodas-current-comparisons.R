# Operational adapters for the tested daily comparison calculations.
snodas_current_change_endpoint <- function(date, template, processed_dir) {
  checked <- snodas_cool_season_processed(data.frame(date = date,
    path = snodas_processed_path(date, "swe", processed_dir), complete = TRUE), processed_dir)
  unavailable <- function(reason) list(swe = NULL, reason = reason)
  if (!isTRUE(checked$complete[[1L]]))
    return(unavailable("Exact prior endpoint is missing or unverified."))
  pair <- screen_snodas_analysis_pair(
    terra::rast(snodas_processed_path(date, "swe", processed_dir)),
    terra::rast(snodas_processed_path(date, "depth", processed_dir)))
  swe <- snodas_align_common_grid(pair$swe, template)
  snodas_comparison_check_date(swe, date)
  values <- terra::values(swe, mat = FALSE)
  # Match the current-map coverage, paired-QC and high-SWE safeguards.
  if (mean(is.finite(values)) < .8 || pair$summary$excluded_cells > 0 ||
      any(values[is.finite(values)] >= 50))
    return(unavailable("Prior endpoint did not pass the snow map-quality check."))
  list(swe = swe, reason = "")
}

build_snodas_current_comparisons <- function(date, output_dir, processed_dir,
                                             climatology_root) {
  inputs <- load_snodas_swe_map_pilot_inputs(date, processed_dir = processed_dir,
    climatology_root = climatology_root)
  percent <- snodas_daily_percent_swe(inputs$observed, inputs$median_swe,
    inputs$sample_years, date, min_years = 18L, minimum_median_inches = 1)
  endpoint <- snodas_current_change_endpoint(date - 7L, inputs$observed, processed_dir)
  change <- if (is.null(endpoint$swe)) NULL else
    snodas_seven_day_swe_change(inputs$observed, endpoint$swe, date)
  if (!is.null(change) && mean(is.finite(terra::values(change, mat = FALSE))) < .8) {
    change <- NULL
    endpoint$reason <- "Too little shared valid coverage at the exact seven-day endpoints."
  }
  states <- southwest_state_boundaries(); counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries(); cities <- southwest_reference_cities()
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c(percent = file.path(output_dir, "swe-percent-median.png"))
  save_southwest_map(plot_snodas_peak_percent_median(percent, 0L, 2005:2025, 1,
    states, counties, countries, cities,
    title = "Snow water equivalent as percent of median",
    subtitle = paste(date, "| WY2005-WY2025 centered five-day daily reference"),
    reference_label = "Typical SWE", fill_label = "SWE (% of date-specific median)"),
    paths[["percent"]], logo_path = southwest_brand_logo_path(),
    footer_text = "Data source: NOAA/NSIDC SNODAS\nMedian >=1 inch; >=18 reference years")
  if (!is.null(change)) {
    paths <- c(paths, change = file.path(output_dir, "swe-change-7day.png"))
    save_southwest_map(plot_snodas_seven_day_change(change, date,
      states, counties, countries, cities), paths[["change"]],
      logo_path = southwest_brand_logo_path(),
      footer_text = "Data source: NOAA/NSIDC SNODAS\nExact seven-day endpoints; net SWE change, not snowfall")
  }
  list(paths = paths, change_available = !is.null(change), change_note = endpoint$reason)
}
