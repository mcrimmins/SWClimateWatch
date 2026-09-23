# Build current water-year-to-date PRISM precipitation products and maps.

prism_water_year_product_path <- function(
    product = c("total", "normal", "percent-normal", "percentile-rank"),
    date,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  product <- match.arg(product)
  file.path(
    processed_dir, "prism", aoi_id, "daily", "water-year", "pcpn", product,
    paste0(format(as.Date(date)), ".tif")
  )
}

prism_water_year_map_path <- function(
    product = c("total", "percent-normal", "percentile-rank"),
    date = NULL,
    maps_dir = swc_paths$maps) {
  product <- match.arg(product)
  suffix <- if (is.null(date)) "latest" else format(as.Date(date))
  file.path(
    maps_dir, "prism", "precipitation",
    paste("pcpn", "water-year", product, suffix, sep = "-") |> paste0(".png")
  )
}

prism_current_water_year_total <- function(
    date,
    aoi_id = swc_prism$aoi_id,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path())) {
  date <- as.Date(date)
  if (length(date) != 1L || is.na(date)) {
    stop("`date` must be one valid date.", call. = FALSE)
  }
  start_date <- prism_water_year_start(date)
  dates <- seq(start_date, date, by = "day")
  collection <- read_prism_best_daily_range(
    "pcpn", dates, aoi_id, processed_manifest
  )
  result <- prism_accumulation_from_raster(collection$raster, "pcpn", date)
  names(result) <- paste0("pcpn_water_year_total_", date)
  terra::time(result) <- date
  result
}

prism_water_year_comparison_rasters <- function(
    current_total,
    reference_totals,
    date,
    minimum_normal_inches = swc_prism$percent_normal_minimum_inches) {
  date <- as.Date(date)
  if (length(date) != 1L || is.na(date)) {
    stop("`date` must be one valid date.", call. = FALSE)
  }
  if (terra::nlyr(current_total) != 1L || terra::nlyr(reference_totals) < 1L) {
    stop("Current total must have one layer and the reference must not be empty.", call. = FALSE)
  }
  if (length(minimum_normal_inches) != 1L || !is.finite(minimum_normal_inches) ||
      minimum_normal_inches < 0) {
    stop("`minimum_normal_inches` must be one non-negative number.", call. = FALSE)
  }
  terra::compareGeom(current_total, reference_totals, stopOnError = TRUE)

  normal <- terra::app(reference_totals, mean, na.rm = FALSE)
  percent_normal <- terra::ifel(
    normal >= minimum_normal_inches,
    100 * current_total / normal,
    NA
  )
  elapsed_days <- as.integer(date - prism_water_year_start(date)) + 1L
  percentile_rank <- prism_accumulation_percentile_rank_raster(
    current_total, reference_totals, elapsed_days, date
  )
  names(normal) <- paste0("pcpn_water_year_normal_", format(date, "%m-%d"))
  names(percent_normal) <- paste0("pcpn_water_year_percent_normal_", date)
  names(percentile_rank) <- paste0("pcpn_water_year_percentile_rank_", date)
  terra::time(normal) <- date
  terra::time(percent_normal) <- date
  terra::time(percentile_rank) <- date
  list(
    normal = normal,
    percent_normal = percent_normal,
    percentile_rank = percentile_rank
  )
}

calculate_current_prism_water_year_products <- function(
    date = NULL,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    minimum_normal_inches = swc_prism$percent_normal_minimum_inches,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    cache_overwrite = FALSE,
    overwrite = TRUE,
    progress_every = 5L,
    quiet = FALSE) {
  if (is.null(date)) {
    date <- latest_common_prism_date(
      "pcpn", aoi_id = aoi_id, processed_manifest = processed_manifest
    )
  }
  date <- as.Date(date)
  if (!quiet) {
    message(
      "Calculating water year ", prism_water_year(date),
      " precipitation through ", date, "."
    )
  }
  current_total <- prism_current_water_year_total(
    date, aoi_id, processed_manifest
  )
  cache <- build_prism_water_year_cache(
    target_date = date,
    baseline_start = baseline_start,
    baseline_end = baseline_end,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    processed_manifest = processed_manifest,
    overwrite = cache_overwrite,
    progress_every = progress_every,
    quiet = quiet
  )
  comparison <- prism_water_year_comparison_rasters(
    current_total, cache$raster, date, minimum_normal_inches
  )
  rasters <- list(
    total = current_total,
    normal = comparison$normal,
    `percent-normal` = comparison$percent_normal,
    `percentile-rank` = comparison$percentile_rank
  )
  paths <- vapply(
    names(rasters),
    prism_water_year_product_path,
    character(1),
    date = date,
    aoi_id = aoi_id,
    processed_dir = processed_dir
  )
  for (product in names(rasters)) {
    path <- paths[[product]]
    if (file.exists(path) && !overwrite) {
      stop("Water-year output already exists; set `overwrite = TRUE`: ", path, call. = FALSE)
    }
    write_prism_processed_raster(rasters[[product]], path)
  }
  list(
    date = date,
    water_year = prism_water_year(date),
    start_date = prism_water_year_start(date),
    total = rasters$total,
    normal = rasters$normal,
    percent_normal = rasters$`percent-normal`,
    percentile_rank = rasters$`percentile-rank`,
    paths = paths,
    cache = cache,
    minimum_normal_inches = minimum_normal_inches
  )
}

prism_water_year_total_scale <- function() {
  list(
    palette = c(
      "#f7fbff", "#d9eff7", "#92c5de", "#4393c3",
      "#41ab5d", "#fddc6c", "#f46d43", "#7a0177"
    ),
    values = c(0, 2, 5, 10, 15, 20, 30, 50),
    limits = c(0, 50),
    breaks = c(0, 5, 10, 20, 30, 50),
    labels = c("0", "5", "10", "20", "30", "50+")
  )
}

build_prism_water_year_map <- function(
    raster,
    product = c("total", "percent-normal", "percentile-rank"),
    date = as.Date(terra::time(raster)),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),
    rivers = southwest_major_rivers()) {
  product <- match.arg(product)
  date <- as.Date(date)
  water_year <- prism_water_year(date)
  period <- format_prism_map_period(prism_water_year_start(date), date)

  if (product == "total") {
    scale <- prism_water_year_total_scale()
    title <- paste0("Water year ", water_year, " precipitation to date")
    fill_label <- "Precipitation (inches)"
  } else if (product == "percent-normal") {
    scale <- prism_precipitation_percent_normal_scale()
    title <- paste0("Water year ", water_year, " precipitation percent of normal")
    fill_label <- "Percent of normal"
  } else {
    scale <- list(
      palette = c("#7f3b08", "#b35806", "#f1a340", "#f7f7f7", "#998ec3", "#542788", "#2d004b"),
      values = c(0, 10, 25, 50, 75, 90, 100),
      limits = c(0, 100),
      breaks = c(0, 10, 25, 50, 75, 90, 100),
      labels = c("0", "10", "25", "50", "75", "90", "100")
    )
    title <- paste0("Water year ", water_year, " precipitation percentile rank")
    fill_label <- "Percentile rank"
  }

  subtitle <- if (product == "total") {
    period
  } else {
    paste0(period, " relative to water years 1991-2020")
  }
  southwest_raster_map(
    raster = raster,
    states = states,
    title = title,
    subtitle = subtitle,
    caption = NULL,
    fill_label = fill_label,
    palette = scale$palette,
    palette_values = scale$values,
    limits = scale$limits,
    breaks = scale$breaks,
    labels = scale$labels,
    counties = counties,
    countries = countries,
    rivers = rivers,
    cities = cities,
    product_id = switch(
      product,
      total = "pcpn_water_year_total",
      `percent-normal` = "pcpn_water_year_percent_normal",
      `percentile-rank` = "pcpn_water_year_percentile"
    ),
    mask_to_states = FALSE
  )
}

build_current_prism_water_year_maps <- function(
    date = NULL,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    minimum_normal_inches = swc_prism$percent_normal_minimum_inches,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    logo_path = southwest_brand_logo_path(),
    overwrite = TRUE,
    progress_every = 5L,
    quiet = FALSE,
    map_products = c("total", "percent-normal", "percentile-rank")) {
  map_products <- validate_southwest_map_products(
    map_products, c("total", "percent-normal", "percentile-rank"),
    allow_empty = TRUE
  )
  products <- calculate_current_prism_water_year_products(
    date = date,
    baseline_start = baseline_start,
    baseline_end = baseline_end,
    minimum_normal_inches = minimum_normal_inches,
    aoi_id = aoi_id,
    processed_dir = processed_dir,
    cache_overwrite = FALSE,
    overwrite = overwrite,
    progress_every = progress_every,
    quiet = quiet
  )
  states <- southwest_state_boundaries()
  counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries()
  cities <- southwest_reference_cities()
  rasters <- list(
    total = products$total,
    `percent-normal` = products$percent_normal,
    `percentile-rank` = products$percentile_rank
  )
  rasters <- rasters[map_products]
  if (length(rasters) == 0L) {
    return(invisible(data.frame()))
  }
  records <- vector("list", length(rasters))

  for (index in seq_along(rasters)) {
    product <- names(rasters)[[index]]
    if (!quiet) message("Building water-year ", product, " map.")
    plot <- build_prism_water_year_map(
      rasters[[product]], product, products$date,
      states, counties, countries, cities
    )
    dated_map <- prism_water_year_map_path(product, products$date, maps_dir)
    latest_map <- prism_water_year_map_path(product, maps_dir = maps_dir)
    footer <- if (product == "total") {
      prism_precipitation_footer_text(products$start_date, products$date)
    } else {
      prism_map_footer_text(baseline_start, baseline_end)
    }
    save_southwest_map(
      plot, dated_map, logo_path = logo_path, footer_text = footer
    )
    dir.create(dirname(latest_map), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(dated_map, latest_map, overwrite = TRUE)) {
      stop("Could not update latest water-year map: ", latest_map, call. = FALSE)
    }
    value_range <- range(terra::values(rasters[[product]]), na.rm = TRUE)
    records[[index]] <- data.frame(
      date = products$date,
      water_year = products$water_year,
      product = product,
      minimum = value_range[[1L]],
      maximum = value_range[[2L]],
      raster_path = unname(products$paths[[product]]),
      map_path = dated_map,
      latest_map_path = latest_map,
      stringsAsFactors = FALSE
    )
  }
  invisible(do.call(rbind, records))
}
