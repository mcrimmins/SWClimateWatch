# Local regional climatology pilot. Reuses verified monthly PRISM inputs read-only.
regional_reference_function_text <- function(functions) {
  # Source-reference attributes can differ between RStudio and Rscript callers.
  # Hash the actual function text, not source-file environments or attributes.
  lapply(functions, function(fun) paste(deparse(body(fun), width.cutoff = 500L), collapse = "\n"))
}

regional_reference_statistics <- function(precipitation, temperature) {
  if (!is.matrix(precipitation) || !is.matrix(temperature) ||
      !identical(dim(precipitation), dim(temperature)) || ncol(precipitation) < 1L)
    stop("Require matched cell-by-year annual precipitation and temperature matrices.")
  if (any(is.finite(precipitation) & precipitation < 0)) stop("Annual precipitation cannot be negative.")
  count_p <- rowSums(is.finite(precipitation)); count_t <- rowSums(is.finite(temperature))
  mean_p <- rowMeans(replace(precipitation, !is.finite(precipitation), NA_real_), na.rm = TRUE)
  mean_t <- rowMeans(replace(temperature, !is.finite(temperature), NA_real_), na.rm = TRUE)
  mean_p[count_p != ncol(precipitation)] <- NA_real_
  mean_t[count_t != ncol(temperature)] <- NA_real_
  cbind(precipitation_inches = mean_p, mean_temperature_f = mean_t,
    precipitation_years = count_p, temperature_years = count_t)
}

regional_reference_style <- function(variable) {
  variable <- match.arg(variable, c("precipitation", "temperature"))
  if (variable == "precipitation") {
    list(breaks = c(-Inf, 4, 8, 12, 16, 20, 24, 32, 40, 60, Inf),
      labels = c("<4", "4-8", "8-12", "12-16", "16-20", "20-24", "24-32", "32-40", "40-60", ">=60"),
      colors = c("#f7fbff", "#deebf7", "#c6dbef", "#9ecae1", "#6baed6", "#2b8cbe", "#238b8e", "#3d7947", "#86639e", "#532765"),
      title = "Average annual precipitation", legend = "Annual precipitation (inches)")
  } else {
    list(breaks = c(-Inf, 30, 40, 45, 50, 55, 60, 65, 70, 75, 80, Inf),
      labels = c("<30", "30-40", "40-45", "45-50", "50-55", "55-60", "60-65", "65-70", "70-75", "75-80", ">=80"),
      colors = c("#313695", "#4575b4", "#74add1", "#abd9e9", "#e0f3f8", "#ffffbf", "#fee090", "#fdae61", "#f46d43", "#d73027", "#7f0000"),
      title = "Mean annual temperature", legend = "Mean temperature (degrees F)")
  }
}

regional_reference_classes <- function(values, variable) {
  style <- regional_reference_style(variable)
  classes <- as.character(cut(values, style$breaks, labels = style$labels, right = FALSE))
  classes[!is.finite(values)] <- "Unavailable"
  factor(classes, levels = c(style$labels, "Unavailable"))
}

plot_regional_climate_reference <- function(raster, variable, years,
    states = southwest_state_boundaries(), counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(), cities = southwest_reference_cities()) {
  style <- regional_reference_style(variable)
  data <- terra::as.data.frame(raster, xy = TRUE, na.rm = FALSE)
  names(data) <- c("x", "y", "value")
  data$class <- regional_reference_classes(data$value, variable)
  plot <- southwest_raster_map(raster, states = states, counties = counties,
    countries = countries, cities = cities, mask_to_states = FALSE,
    title = style$title, subtitle = sprintf("%d-%d calendar-year reference | PRISM monthly grids", min(years), max(years)),
    caption = NULL, fill_label = style$legend, scale_type = "continuous")
  plot$layers[[1L]] <- ggplot2::geom_tile(data = data, ggplot2::aes(x, y, fill = class),
    width = terra::res(raster)[1L], height = terra::res(raster)[2L], show.legend = TRUE)
  suppressMessages(plot + ggplot2::scale_fill_manual(
    values = stats::setNames(c(style$colors, "#ede8df"), levels(data$class)),
    drop = FALSE, name = style$legend) +
    ggplot2::guides(fill = ggplot2::guide_legend(nrow = 1, title.position = "top",
      title.hjust = .5, label.position = "bottom", keywidth = grid::unit(.95, "cm"), keyheight = grid::unit(.35, "cm"))) +
    ggplot2::theme(legend.text = ggplot2::element_text(size = 8)))
}

regional_reference_gallery <- function(output_dir, years) {
  html <- c('<!doctype html><html lang="en"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1"><title>Regional climate reference pilot</title>',
    '<style>body{font:16px system-ui,sans-serif;color:#26363d;background:#f4f6f7;margin:24px auto;max-width:1600px;padding:0 20px}p{line-height:1.5}.maps{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}article{background:white;border:1px solid #d8e0e4;border-radius:8px;padding:12px}h2{font-size:18px}img{width:100%;height:auto}a{color:#14647c}@media(max-width:850px){.maps{grid-template-columns:1fr}}</style></head><body>',
    sprintf('<h1>Regional climate reference: %d-%d</h1>', min(years), max(years)),
    '<p>Local review only. These maps describe the typical climate, not current conditions, anomalies or rankings. They are project-calculated references from monthly PRISM grids, not downloaded official NOAA normals.</p>',
    '<div class="maps"><article><h2>Average annual precipitation</h2>',
    '<a href="annual-precipitation.png" target="_blank" rel="noopener"><img src="annual-precipitation.png" alt="Average annual precipitation"></a>',
    '<p>Mean of complete January-December precipitation totals, in inches.</p><a href="annual-precipitation.png" target="_blank" rel="noopener">Open full-resolution PNG</a></article>',
    '<article><h2>Mean annual temperature</h2>',
    '<a href="annual-mean-temperature.png" target="_blank" rel="noopener"><img src="annual-mean-temperature.png" alt="Mean annual temperature"></a>',
    '<p>Monthly mean temperature is (mean daily high + mean daily low)/2. Months are weighted by actual days within each year, then the annual means are averaged equally.</p><a href="annual-mean-temperature.png" target="_blank" rel="noopener">Open full-resolution PNG</a></article></div>',
    sprintf('<p>Both maps require %d complete years at each cell. A missing month invalidates that year for its variable; missing data are never filled with zero. Beige means unavailable support. February 29 is included in leap years.</p>', length(years)),
    '<p><a href="samples.csv">City/grid-cell sample values</a> &middot; <a href="methods.csv">Methods</a> &middot; <a href="source-inventory.csv">Source inventory</a></p></body></html>')
  writeLines(html, file.path(output_dir, "index.html"), useBytes = TRUE)
}

build_regional_climate_reference_pilot <- function(years = 1991:2020,
    cache_dir = prism_monthly_cache_dir(), output_dir = "data/diagnostics/regional-climate-reference-pilot",
    make_maps = TRUE, force = FALSE, bbox = swc_region$bbox) {
  started <- proc.time()[["elapsed"]]
  if (!is.numeric(years) || length(years) < 2L || anyNA(years) || any(!is.finite(years)) || any(years != floor(years)) ||
      anyDuplicated(years) || !identical(as.integer(years), seq.int(min(years), max(years))))
    stop("Choose at least two consecutive ascending reference years.")
  if (!is.logical(make_maps) || length(make_maps) != 1L || is.na(make_maps) ||
      !is.logical(force) || length(force) != 1L || is.na(force)) stop("make_maps and force must be TRUE or FALSE.")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  audit <- audit_prism_monthly_cache(sprintf("%d-01", min(years)), sprintf("%d-12", max(years)),
    cache_dir = cache_dir, report_dir = file.path(output_dir, "input-audit"), bbox = bbox)
  if (!audit$summary$status %in% c("PASS", "WARN") || !all(audit$plan$complete))
    stop("Reference inputs failed verification; inspect ", output_dir, "/input-audit. No downloads attempted.")
  source_signature <- prism_monthly_source_signature(audit)
  signature <- digest::digest(list(source_signature, years, make_maps,
    regional_reference_style("precipitation"), regional_reference_style("temperature"),
    regional_reference_function_text(list(plot_regional_climate_reference, regional_reference_classes, regional_reference_gallery,
      regional_reference_statistics, prism_monthly_precipitation_window, prism_monthly_temperature_window)),
    "annual-reference-complete-years-v2"), algo = "sha256")
  marker_path <- file.path(output_dir, "complete.rds")
  saved <- if (file.exists(marker_path)) tryCatch(readRDS(marker_path), error = function(e) NULL) else NULL
  if (!force && is.list(saved) && identical(saved$signature, signature) &&
      length(saved$files) && all(file.exists(saved$files)) &&
      identical(unname(tools::md5sum(saved$files)), saved$md5)) {
    saved$result$summary$event <- "REUSED"
    saved$result$summary$elapsed_seconds <- round(proc.time()[["elapsed"]] - started, 2)
    message("Annual regional references: REUSED. No downloads or publication.")
    return(invisible(saved$result))
  }
  plan <- audit$plan
  template <- terra::rast(plan$path[1])
  precipitation <- temperature <- matrix(NA_real_, nrow = terra::ncell(template), ncol = length(years))
  for (i in seq_along(years)) {
    end <- sprintf("%d-12", years[i])
    p <- prism_monthly_precipitation_window(plan, end, duration = 12L)
    t <- prism_monthly_temperature_window(plan, end, duration = 12L)
    terra::compareGeom(template, p, t, stopOnError = TRUE, tolerance = 0)
    precipitation[, i] <- terra::values(p, mat = FALSE)
    temperature[, i] <- terra::values(t, mat = FALSE)
    if (i %% 5L == 0L || i == length(years)) message("Annual reference: ", i, "/", length(years), " years summarized.")
  }
  stats <- regional_reference_statistics(precipitation, temperature)
  products <- list(precipitation = terra::setValues(template, stats[, "precipitation_inches"]),
    temperature = terra::setValues(template, stats[, "mean_temperature_f"]))
  names(products$precipitation) <- "mean_annual_precipitation_inches"
  names(products$temperature) <- "mean_annual_temperature_f"
  paths <- c(precipitation = file.path(output_dir, "annual-precipitation.tif"),
    temperature = file.path(output_dir, "annual-mean-temperature.tif"),
    precipitation_years = file.path(output_dir, "precipitation-sample-years.tif"),
    temperature_years = file.path(output_dir, "temperature-sample-years.tif"))
  for (name in names(products)) terra::writeRaster(products[[name]], paths[[name]], overwrite = TRUE,
    datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
  for (name in c("precipitation_years", "temperature_years"))
    terra::writeRaster(terra::setValues(template, stats[, name]), paths[[name]], overwrite = TRUE,
      datatype = "INT2U", gdal = "COMPRESS=DEFLATE")
  write.csv(plan[c("month", "variable", "native_units", "path", "request_signature", "md5")],
    file.path(output_dir, "source-inventory.csv"), row.names = FALSE)
  methods <- data.frame(start_year = min(years), end_year = max(years), calendar = "January-December",
    required_complete_years = length(years), expected_months = length(years) * 12L,
    precipitation = "Mean of complete annual sums; inches",
    temperature = "Monthly (maxt+mint)/2; actual month-day weights within year; equal annual weights; Fahrenheit",
    leap_days = "Actual February days, including February 29", missing = "No imputation; require every month in every reference year independently per variable",
    source_signature = source_signature, input_signature = signature)
  write.csv(methods, file.path(output_dir, "methods.csv"), row.names = FALSE)
  samples <- data.frame(location = c("Phoenix", "Tucson", "Flagstaff", "Yuma", "Albuquerque", "Santa Fe", "Las Cruces", "Southern Colorado mountains"),
    longitude = c(-112.074, -110.975, -111.651, -114.624, -106.651, -105.938, -106.763, -106.8),
    latitude = c(33.448, 32.222, 35.198, 32.693, 35.084, 35.687, 32.32, 37.48))
  points <- as.matrix(samples[c("longitude", "latitude")])
  for (name in names(products)) {
    extracted <- terra::extract(products[[name]], points)
    samples[[if (name == "precipitation") "annual_precipitation_inches" else "annual_mean_temperature_f"]] <- extracted[[ncol(extracted)]]
  }
  write.csv(samples, file.path(output_dir, "samples.csv"), row.names = FALSE)
  if (make_maps) {
    for (name in names(products)) {
      message("Rendering annual ", name, " reference map.")
      save_southwest_map(plot_regional_climate_reference(products[[name]], name, years),
        sub("[.]tif$", ".png", paths[[name]]), logo_path = southwest_brand_logo_path(),
        footer_text = sprintf("PRISM Climate Group via RCC-ACIS\n%d-%d | %d complete calendar years | Project-calculated reference\nClimate Science Applications Program - University of Arizona",
          min(years), max(years), length(years)))
    }
    regional_reference_gallery(output_dir, years)
  }
  summary <- data.frame(status = "READY", event = "BUILT", start_year = min(years), end_year = max(years),
    verified_inputs = nrow(plan), precipitation_valid_cells = sum(is.finite(stats[, "precipitation_inches"])),
    temperature_valid_cells = sum(is.finite(stats[, "mean_temperature_f"])),
    requests = 0L, maps = if (make_maps) 2L else 0L, elapsed_seconds = round(proc.time()[["elapsed"]] - started, 2))
  write.csv(summary, file.path(output_dir, "summary.csv"), row.names = FALSE)
  files <- c(unname(paths), file.path(output_dir, c("source-inventory.csv", "methods.csv", "samples.csv", "summary.csv")),
    if (make_maps) c(sub("[.]tif$", ".png", unname(paths[c("precipitation", "temperature")])), file.path(output_dir, "index.html")))
  result <- list(summary = summary, paths = paths, samples = samples, methods = methods)
  saveRDS(list(signature = signature, files = files, md5 = unname(tools::md5sum(files)), result = result), marker_path)
  message("Annual regional references ready: ", output_dir, ". No downloads or site changes.")
  invisible(result)
}
