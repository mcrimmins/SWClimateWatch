# Isolated, cached-only Historic Years review. Never stages operational pages.
historic_monthly_periods <- function() data.frame(
  id = c("water-year", "cool-season", "spring", "monsoon"),
  label = c("Water year", "Cool season", "Spring (April-June)", "Monsoon (July-September)"),
  end_month = c(9L, 3L, 6L, 9L), duration = c(12L, 6L, 3L, 3L),
  definition = c("October-September", "October-March", "April-June", "July-September"))

historic_monthly_products_per_year <- function() 5L * nrow(historic_monthly_periods()) + 1L

historic_monthly_metrics <- function() c(precipitation_total = "Precipitation total",
  precipitation_rank = "Precipitation percentile rank", temperature_mean = "Mean temperature",
  temperature_departure = "Temperature departure", temperature_rank = "Temperature percentile rank",
  spi12 = "September SPI-12")

historic_monthly_windows <- function(years) {
  if (!is.numeric(years) || !length(years) || anyNA(years) || any(!is.finite(years)) ||
      any(years != floor(years)) || any(years < 1896) || anyDuplicated(years))
    stop("Supply unique complete water years from WY1896 onward.")
  specs <- historic_monthly_periods()
  do.call(rbind, lapply(as.integer(years), function(year) {
    end <- sprintf("%04d-%02d", year, specs$end_month)
    data.frame(water_year = year, period = specs$id, label = specs$label,
      start = vapply(seq_along(end), function(i)
        format(min(prism_monthly_window(end[i], specs$duration[i])), "%Y-%m"), character(1)),
      end = end, duration = specs$duration, definition = specs$definition)
  }))
}

historic_monthly_signature <- function(...) digest::digest(list(...), algo = "sha256")

# Copy a verified matching cache into a separate review tree without retaining
# absolute paths to the original pilot. Source data and source markers are read-only.
historic_monthly_seed_cache <- function(from, to, signature) {
  if (is.null(from) || !prism_monthly_ranking_complete(from, signature)) return(FALSE)
  saved <- readRDS(from)
  if (anyDuplicated(basename(saved$files))) stop("Ambiguous cache filenames; cannot seed archive.")
  dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
  files <- file.path(dirname(to), basename(saved$files))
  if (identical(normalizePath(from, winslash = "/"), normalizePath(to, winslash = "/", mustWork = FALSE))) return(FALSE)
  for (i in seq_along(files)) {
    if (!file.exists(files[i]) || !identical(unname(tools::md5sum(files[i])), saved$md5[i]))
      if (!file.copy(saved$files[i], files[i], overwrite = TRUE)) stop("Could not seed verified archive cache.")
  }
  if (!identical(unname(tools::md5sum(files)), saved$md5)) stop("Archive seed copy checksum mismatch.")
  if (is.data.frame(saved$records)) for (field in intersect(c("grid", "map"), names(saved$records))) {
    present <- nzchar(saved$records[[field]])
    indices <- match(saved$records[[field]][present], saved$files)
    if (anyNA(indices)) stop("Seed record refers to a file outside its verified cache.")
    saved$records[[field]][present] <- files[indices]
  }
  saved$files <- files
  temporary <- tempfile("historic-seed-", tmpdir = dirname(to))
  on.exit(unlink(temporary), add = TRUE)
  saveRDS(saved, temporary); replace_file_atomically(temporary, to)
  TRUE
}

historic_monthly_code_signature <- function() {
  functions <- list(historic_monthly_windows, historic_monthly_periods, historic_monthly_statistics,
    historic_monthly_style, historic_monthly_plot, historic_monthly_existing_comparison,
    prism_monthly_precipitation_window, prism_monthly_temperature_window,
    prism_monthly_ranking_statistics, prism_monthly_precipitation_statistics,
    prism_monthly_temperature_statistics, prism_monthly_record_display,
    fit_prism_monthly_spi_gamma, evaluate_prism_monthly_spi, prism_monthly_spi_display,
    southwest_raster_map, southwest_raster_layer, map_product_categorical_classes)
  historic_monthly_signature("historic-monthly-v1", lapply(functions, function(f) deparse(body(f))))
}

historic_monthly_statistics <- function(reference, year, normal_years = 1991:2020,
    min_years = 30L, min_fraction = .9, min_normal_years = 27L) {
  p <- prism_monthly_precipitation_statistics(reference$precipitation, reference$years, year,
    min_years, min_fraction, normal_years, min_normal_years)
  t <- prism_monthly_temperature_statistics(reference$temperature, reference$years, year,
    min_years, min_fraction, normal_years, min_normal_years)
  fields <- cbind(precipitation_total = p[, "total_precipitation_inches"],
    precipitation_rank = p[, "percentile"], temperature_mean = t[, "mean_temperature_f"],
    temperature_departure = t[, "departure_f"], temperature_rank = t[, "percentile"],
    precipitation_display = prism_monthly_record_display(p[, "percentile"], p[, "record_high"], p[, "record_low"]),
    temperature_display = prism_monthly_record_display(t[, "percentile"], t[, "record_high"], t[, "record_low"]),
    precipitation_sample_years = p[, "sample_years"], temperature_sample_years = t[, "sample_years"],
    temperature_normal = t[, "normal_mean_f"], temperature_normal_years = t[, "normal_years"],
    precipitation_zero_fraction = p[, "zero_fraction"],
    precipitation_record_high = p[, "record_high"], precipitation_record_high_tied = p[, "record_high_tied"],
    precipitation_record_low = p[, "record_low"], precipitation_record_low_tied = p[, "record_low_tied"],
    temperature_record_high = t[, "record_high"], temperature_record_high_tied = t[, "record_high_tied"],
    temperature_record_low = t[, "record_low"], temperature_record_low_tied = t[, "record_low_tied"])
  for (name in colnames(fields)[1:5]) if (!any(is.finite(fields[, name])))
    stop("No supported cells for ", name, "; no complete pilot release produced.")
  fields
}

historic_monthly_reference <- function(audit, years, period, root, force, code, seed_dir = NULL) {
  windows <- historic_monthly_windows(years)
  windows <- windows[windows$period == period, ]
  months <- unique(unlist(lapply(seq_len(nrow(windows)), function(i)
    format(prism_monthly_window(windows$end[i], windows$duration[i]), "%Y-%m"))))
  signature <- historic_monthly_signature(code, years, period,
    prism_monthly_input_signature(audit, c("pcpn", "maxt", "mint"), months))
  folder <- file.path(root, "reference", period); dir.create(folder, recursive = TRUE, showWarnings = FALSE)
  marker <- file.path(folder, "complete.rds")
  path <- file.path(folder, "windows.rds")
  if (!force && !prism_monthly_ranking_complete(marker, signature) && !is.null(seed_dir))
    historic_monthly_seed_cache(file.path(seed_dir, "reference", period, "complete.rds"), marker, signature)
  if (!force && prism_monthly_ranking_complete(marker, signature)) {
    message(period, " reference: REUSED.")
    return(c(readRDS(path), list(signature = signature)))
  }
  template <- terra::rast(audit$plan$path[1])
  p <- t <- matrix(NA_real_, terra::ncell(template), length(years))
  for (i in seq_along(years)) {
    p[, i] <- terra::values(prism_monthly_precipitation_window(audit$plan, windows$end[i], windows$duration[i]), mat = FALSE)
    t[, i] <- terra::values(prism_monthly_temperature_window(audit$plan, windows$end[i], windows$duration[i]), mat = FALSE)
    if (i %% 10L == 0 || i == length(years)) message(period, ": ", i, "/", length(years), " complete-year windows.")
  }
  result <- list(years = years, precipitation = p, temperature = t, windows = windows)
  saveRDS(result, path)
  write.csv(windows, file.path(folder, "windows.csv"), row.names = FALSE)
  files <- c(path, file.path(folder, "windows.csv"))
  saveRDS(list(signature = signature, files = files, md5 = unname(tools::md5sum(files))), marker)
  c(result, list(signature = signature))
}

historic_monthly_style <- function(metric) {
  if (metric %in% c("precipitation_rank", "temperature_rank")) {
    temperature <- metric == "temperature_rank"
    return(list(product_id = paste0("monthly_", if (temperature) "temperature" else "precipitation", "_record_percentile"),
      fill_label = "Historical percentile / record", limits = c(-1, 101),
      breaks = c(-1, 0, 2, 10, 33, 67, 90, 98, 100, 101),
      palette_values = c(-.5, 1, 6, 21.5, 50, 78.5, 94, 99, 100.5),
      palette = if (temperature) c("#081d58", "#313695", "#4575b4", "#91bfdb", "#f7f7f7", "#fdae61", "#d73027", "#7f0000", "#542788") else
        c("#543005", "#8c510a", "#bf812d", "#dfc27d", "#f5f5f5", "#80cdc1", "#35978f", "#01665e", "#253494")))
  }
  if (metric == "spi12") return(list(product_id = "monthly_spi", fill_label = "SPI (negative = drier; positive = wetter)",
    limits = c(.5, 8.5), breaks = seq(.5, 8.5, 1), palette_values = 1:8,
    palette = c("#8c510a", "#bf812d", "#dfc27d", "#f5f5f5", "#80cdc1", "#35978f", "#01665e", "#bdbdbd")))
  if (metric == "precipitation_total") return(list(product_id = "historic_pcpn_total", fill_label = "Precipitation (inches)",
    limits = c(0, 64), breaks = c(0, .5, 1, 2, 4, 8, 12, 16, 24, 40, 64),
    # Anchor one intended colour at each unequal-width category's midpoint.
    # Linear 0-64 interpolation otherwise collapses the low bins toward white.
    palette_values = c(.25, .75, 1.5, 3, 6, 10, 14, 20, 32, 52),
    palette = c("#f5f5f5", "#bddde9", "#7ebcd3", "#3596b9", "#247697", "#3d8350", "#21572c", "#80609c", "#552267", "#320d45")))
  if (metric == "temperature_mean") return(list(product_id = "historic_temperature_mean", fill_label = "Mean temperature (degrees F)",
    limits = c(-20, 100), breaks = c(-20, 0, seq(10, 100, 10)),
    palette = grDevices::colorRampPalette(c("#313695", "#74add1", "#ffffbf", "#f46d43", "#7f0000"))(11)))
  if (metric == "temperature_departure") return(list(product_id = "historic_temperature_departure", fill_label = "Departure (degrees F)",
    limits = c(-10, 10), breaks = c(-10, -6, -4, -2, -1, 1, 2, 4, 6, 10),
    palette = c("#313695", "#4575b4", "#74add1", "#e0f3f8", "#f7f7f7", "#fee090", "#fdae61", "#f46d43", "#a50026")))
  stop("Unknown historic metric.")
}

historic_monthly_plot <- function(raster, metric, window, reference_years, normal_years, policy, cal_years) {
  style <- historic_monthly_style(metric)
  period <- paste(format(as.Date(paste0(window$start, "-01")), "%B %Y"),
    format(as.Date(paste0(window$end, "-01")), "%B %Y"), sep = " - ")
  reference <- if (metric == "temperature_departure") sprintf("%d-%d matching-season normal", min(normal_years), max(normal_years)) else
    if (metric == "spi12") sprintf("fixed calibration: WY%d-WY%d", min(cal_years), max(cal_years)) else
      if (grepl("rank", metric)) sprintf("retrospective comparison: WY%d-WY%d", min(reference_years), max(reference_years)) else "PRISM monthly grids"
  plot <- do.call(southwest_raster_map, c(list(raster = raster, states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(), countries = southwest_country_boundaries(), cities = southwest_reference_cities(),
    title = paste0(historic_monthly_metrics()[[metric]], " - WY", window$water_year),
    subtitle = paste(period, reference, sep = " | "), caption = NULL, scale_type = "categorical"), style))
  footer <- if (grepl("rank", metric)) paste0("Full-record midrank; target included once; >=30 years and 90% windows\n",
    "*Records include ties; complete history required",
    if (metric == "precipitation_rank") "; zero dry records require <=2% zeros" else "") else
      if (metric == "spi12") paste0("Gamma MLE, zero-adjusted; fixed ", policy$calibration_start, "-", policy$calibration_end,
        " policy\nGray: insufficient support, common zeros or poor fit; precipitation only") else
          if (metric == "temperature_departure") "Mean of matching reference seasons; >=27 of 30 normal years\nTemperature uses actual month-day weights; missing months are not filled" else
            "Complete monthly inputs at each cell; no gap filling\nPrecipitation: sum; temperature: day-weighted mean"
  list(plot = plot, footer = paste0("Data: PRISM Climate Group via RCC-ACIS | Local pilot, not published\n", footer))
}

historic_monthly_existing_comparison <- function(raster, year, period) {
  old <- file.path("data/processed/prism", swc_prism$aoi_id, "seasonal-archive/reference", sprintf("wy%d.tif", year))
  field <- switch(period, "water-year" = "water_total", "cool-season" = "cool_total", "")
  result <- data.frame(water_year = year, period = period, status = "UNAVAILABLE", paired_cells = 0L,
    mean_difference_inches = NA_real_, mean_absolute_difference_inches = NA_real_, max_absolute_difference_inches = NA_real_,
    note = "No matching cached daily-derived precipitation total; no replacement or download.")
  if (!nzchar(field) || !file.exists(old)) return(result)
  tryCatch({
    old_grid <- terra::rast(old)
    if (!field %in% names(old_grid)) stop("Matching daily-derived total layer absent.")
    old_grid <- old_grid[[field]]
    terra::compareGeom(raster, old_grid, stopOnError = TRUE, tolerance = 0)
    delta <- terra::values(raster - old_grid, mat = FALSE); delta <- delta[is.finite(delta)]
    if (!length(delta)) stop("No paired valid cells.")
    result$status <- "COMPARED"; result$paired_cells <- length(delta)
    result$mean_difference_inches <- mean(delta)
    result$mean_absolute_difference_inches <- mean(abs(delta)); result$max_absolute_difference_inches <- max(abs(delta))
    result$note <- "Monthly minus existing daily-derived totals; differences are diagnostic, not a pass/fail tolerance."
    result
  }, error = function(e) { result$note <- conditionMessage(e); result })
}

historic_monthly_gallery <- function(records, root, reference_years, normal_years, cal_years) {
  metrics <- historic_monthly_metrics(); periods <- historic_monthly_periods()
  cards <- vapply(seq_len(nrow(records)), function(i) {
    x <- records[i, ]; src <- x$relative_map
    sprintf('<article data-year="%d" data-period="%s" data-metric="%s"><h2>WY%d &middot; %s</h2><p>%s</p><a href="%s" target="_blank" rel="noopener"><img loading="lazy" src="%s" alt="WY%d %s %s"></a><p><a href="%s" target="_blank" rel="noopener">Open full-resolution PNG</a></p></article>',
      x$water_year, x$period, x$metric, x$water_year, metrics[[x$metric]],
      x$definition, src, src, x$water_year, x$definition, metrics[[x$metric]], src)
  }, character(1))
  options <- function(values, labels = values) paste(sprintf('<option value="%s">%s</option>', values, labels), collapse = "")
  html <- c('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Historic Years monthly PRISM pilot</title>',
    '<style>body{font:16px system-ui;color:#263d47;background:#f3f6f6;max-width:1700px;margin:24px auto;padding:0 20px}p{line-height:1.5}.controls{display:flex;gap:18px;flex-wrap:wrap;background:white;padding:18px;border:1px solid #cdd9de;border-radius:8px;position:sticky;top:0;z-index:2}label{display:grid;gap:6px;font-weight:600}select{padding:9px;max-width:100%;font:inherit}.maps{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px;margin-top:20px}article{padding:12px;background:white;border:1px solid #cdd9de;border-radius:8px;min-width:0}article[hidden]{display:none}h2{font-size:18px}img{width:100%;height:auto}a{color:#12667e}details{margin-top:18px;background:white;padding:14px}#selection-status{font-weight:600}@media(max-width:1100px){.maps{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:700px){.maps{grid-template-columns:1fr}.controls{position:static}}</style></head><body>',
    '<h1>Historic Years &middot; monthly PRISM pilot</h1><p>Local review only. Existing Historic Years pages and maps remain unchanged. Compare years for the same period and metric, or explore a single year.</p>',
    '<div class="controls"><label>Year<select id="year">', options(c("all", unique(records$water_year)), c("Compare all years", paste0("WY", unique(records$water_year)))),
    '</select></label><label>Period<select id="period">', options(periods$id, periods$label),
    '</select></label><label>Map<select id="metric">', options(c("precipitation_rank", "precipitation_total", "temperature_mean", "temperature_departure", "temperature_rank", "spi12", "all"),
      c(unname(metrics[c("precipitation_rank", "precipitation_total", "temperature_mean", "temperature_departure", "temperature_rank", "spi12")]), "All maps for this period")),
    '</select></label></div><p id="selection-status" role="status"></p>',
    '<details><summary>How to read these maps and comparison methods</summary>',
    sprintf('<p>Water year: October-September; cool season: October-March; spring: April-June; monsoon: July-September. The three seasons cover all twelve months without gaps or overlaps. The July-September monsoon summary is a historical climate window, not the June 15-September 30 meteorological season.</p><p>Retrospective ranks compare the same period in all complete water years WY%d-WY%d, including each target once. Later years are included when describing older years. Minimum support: 30 years and 90%% of eligible windows. True record categories require every window; ties count. Common zero totals are not labeled record dry.</p>', min(reference_years), max(reference_years)),
    sprintf('<p>Temperature departures use matching %d-%d seasons, at least 27 of 30 years. Monthly high/low means form mean temperature; actual month lengths, including leap days, weight each season. Missing months are never filled.</p><p>September SPI-12 describes October-September precipitation with fixed WY%d-WY%d gamma-MLE calibration, zero adjustment and existing fit/support guards. It is not a temperature-demand, streamflow or official drought measure. SPI is shown only under Water year.</p>', min(normal_years), max(normal_years), min(cal_years), max(cal_years)),
    '<p>Shared metric scales apply across years and periods. Temperature percentiles differ from fixed-reference daily-map ranks. Existing archive precipitation ranks use WY1982-WY2025; existing temperature departures describe maximum/minimum temperatures separately, so they are not direct substitutes for mean-temperature departure.</p>',
    '<p><a href="manifest.csv">Map manifest</a> &middot; <a href="methods.txt">Methods</a> &middot; <a href="existing-comparison.csv">Existing daily-derived precipitation comparison</a> &middot; <a href="source-inventory.csv">Source inventory</a></p></details>',
    '<div class="maps">', cards, '</div><script src="controls.js"></script></body></html>')
  writeLines(html, file.path(root, "index.html"), useBytes = TRUE)
  if (!file.copy("scripts/historic-monthly-pilot-assets/controls.js", file.path(root, "controls.js"), overwrite = TRUE)) stop("Could not copy pilot controls.")
}

build_historic_monthly_pilot <- function(years = c(2002L, 2005L, 2020L),
    end = prism_monthly_latest_complete(), cache_dir = prism_monthly_cache_dir(),
    output_dir = "data/diagnostics/historic-monthly-pilot", force = FALSE,
    make_maps = TRUE, bbox = swc_region$bbox, seed_dir = NULL) {
  started <- proc.time()[["elapsed"]]
  historic_monthly_windows(years)
  last_year <- as.integer(substr(end, 1, 4)) - as.integer(as.integer(substr(end, 6, 7)) < 9L)
  reference_years <- seq.int(1896L, last_year); normal_years <- 1991:2020
  if (last_year < 2020L || any(!years %in% reference_years)) stop("Target years and the full 1991-2020 normal must be complete in the cache cutoff.")
  # Restrict all writes to diagnostics, including fits and audit reports.
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  root <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)
  allowed <- paste0(normalizePath("data/diagnostics", winslash = "/", mustWork = TRUE), "/")
  if (!startsWith(tolower(root), tolower(allowed))) stop("Pilot outputs must be inside data/diagnostics.")
  write.csv(data.frame(status = "BUILDING", years = length(years), maps = 0L,
    products = historic_monthly_products_per_year() * length(years), built = 0L, reused = 0L, requests = 0L,
    comparison_first_year = min(reference_years), comparison_last_year = max(reference_years),
    elapsed_seconds = 0), file.path(root, "summary.csv"), row.names = FALSE)
  message("Historic monthly pilot: checking cached inputs through ", end,
    ". Initial checksum scanning can take a minute; no downloads will be made.")
  if (!is.null(seed_dir) && !file.exists(file.path(root, "audit/months.csv")) &&
      file.exists(file.path(seed_dir, "audit/months.csv"))) {
    dir.create(file.path(root, "audit"), showWarnings = FALSE)
    if (!file.copy(file.path(seed_dir, "audit/months.csv"), file.path(root, "audit/months.csv")))
      stop("Could not seed the audit report.")
    # The auditor recomputes each month signature; changed inputs never reuse it.
  }
  audit <- audit_prism_monthly_cache("1895-01", end, cache_dir, file.path(root, "audit"), bbox)
  if (!audit$summary$status %in% c("PASS", "WARN") || !all(audit$plan$complete)) stop("Monthly cache is incomplete; see pilot audit. No downloads attempted.")
  audit$plan$md5 <- unname(tools::md5sum(audit$plan$path))
  write.csv(audit$plan[c("month", "variable", "path", "request_signature", "md5")], file.path(root, "source-inventory.csv"), row.names = FALSE)
  code <- historic_monthly_code_signature(); policy <- prism_monthly_spi_policy()
  # Display/statistic edits must not reread thousands of unchanged monthly grids.
  window_code <- historic_monthly_signature(lapply(list(historic_monthly_windows,
    historic_monthly_periods, prism_monthly_window, prism_monthly_day_weights,
    prism_monthly_precipitation_window, prism_monthly_temperature_window), function(f) deparse(body(f))))
  cal_years <- reference_years[reference_years >= policy$calibration_start & reference_years <= policy$calibration_end]
  records <- comparisons <- list(); built <- reused <- 0L
  template <- terra::rast(audit$plan$path[1]); specs <- historic_monthly_periods()
  for (period in specs$id) {
    reference <- historic_monthly_reference(audit, reference_years, period, root, force, window_code, seed_dir)
    if (period == "water-year") {
      calibration <- reference$precipitation[, reference$years %in% cal_years, drop = FALSE]
      signature <- historic_monthly_signature(policy, cal_years, calibration,
        deparse(body(fit_prism_monthly_spi_gamma)), deparse(body(validate_prism_monthly_spi_policy)))
      fit_path <- file.path(root, "reference", "spi-fit.rds"); fit_marker <- paste0(fit_path, ".complete")
      if (!force && !prism_monthly_ranking_complete(fit_marker, signature) && !is.null(seed_dir))
        historic_monthly_seed_cache(file.path(seed_dir, "reference/spi-fit.rds.complete"), fit_marker, signature)
      if (!force && prism_monthly_ranking_complete(fit_marker, signature)) fit <- readRDS(fit_path) else {
        message("Fitting September SPI-12 with ", length(cal_years), " matching complete-water-year windows.")
        fit <- fit_prism_monthly_spi_gamma(calibration, policy); saveRDS(fit, fit_path)
        saveRDS(list(signature = signature, files = fit_path, md5 = unname(tools::md5sum(fit_path))), fit_marker)
      }
      rm(calibration)
    }
    for (year in years) {
      window <- historic_monthly_windows(year); window <- window[window$period == period, ]
      folder <- file.path(root, paste0("wy", year), period); dir.create(folder, recursive = TRUE, showWarnings = FALSE)
      marker <- file.path(folder, "complete.rds")
      signature <- historic_monthly_signature(code, reference$signature, year, normal_years, policy, make_maps)
      if (!force && !prism_monthly_ranking_complete(marker, signature) && !is.null(seed_dir))
        historic_monthly_seed_cache(file.path(seed_dir, paste0("wy", year), period, "complete.rds"), marker, signature)
      if (!force && prism_monthly_ranking_complete(marker, signature)) {
        saved <- readRDS(marker); rows <- saved$records; compare <- saved$comparison
        reused <- reused + nrow(rows); message("WY", year, " ", period, ": REUSED.")
      } else {
        fields <- historic_monthly_statistics(reference, year)
        grid <- terra::rast(rep(template, ncol(fields))); grid <- terra::setValues(grid, fields)
        names(grid) <- colnames(fields); terra::time(grid) <- rep(as.Date(paste0(window$end, "-01")), ncol(fields))
        grid_path <- file.path(folder, "summary.tif")
        terra::writeRaster(grid, grid_path, overwrite = TRUE, datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
        compare <- historic_monthly_existing_comparison(grid[["precipitation_total"]], year, period)
        metrics <- names(historic_monthly_metrics())[1:5]; spi_path <- file.path(folder, "spi.tif")
        if (period == "water-year") {
          evaluation <- evaluate_prism_monthly_spi(fields[, "precipitation_total"], fit, policy)
          if (!any(is.finite(evaluation$spi))) stop("No supported SPI cells for WY", year)
          spi_fields <- cbind(evaluation, fit)
          spi_fields$display_class <- prism_monthly_spi_display(evaluation$spi,
            fit$sample_years > 0 | is.finite(fields[, "precipitation_total"]))
          spi <- terra::setValues(terra::rast(rep(template, ncol(spi_fields))), as.matrix(spi_fields)); names(spi) <- names(spi_fields)
          terra::writeRaster(spi, spi_path, overwrite = TRUE, datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
          metrics <- c(metrics, "spi12")
        }
        rows <- do.call(rbind, lapply(metrics, function(metric) {
          layer <- switch(metric, precipitation_rank = "precipitation_display", temperature_rank = "temperature_display", spi12 = "display_class", metric)
          values <- if (metric == "spi12") spi[[layer]] else grid[[layer]]
          map <- file.path(folder, paste0(metric, ".png"))
          if (make_maps) {
            message("Rendering WY", year, " ", period, ": ", historic_monthly_metrics()[[metric]])
            product <- historic_monthly_plot(values, metric, window, reference_years, normal_years, policy, cal_years)
            save_southwest_map(product$plot, map, logo_path = southwest_brand_logo_path(), footer_text = product$footer)
          }
          data.frame(water_year = year, period = period, metric = metric, definition = window$definition,
            start = window$start, end = window$end, grid = if (metric == "spi12") spi_path else grid_path,
            layer = if (metric == "spi12") "spi" else metric,
            map = if (make_maps) map else "", relative_map = paste0("wy", year, "/", period, "/", metric, ".png"),
            comparison_first_year = min(reference_years), comparison_last_year = max(reference_years),
            normal_first_year = 1991L, normal_last_year = 2020L,
            supported_cells = sum(is.finite(terra::values(if (metric == "spi12") spi[["spi"]] else grid[[metric]], mat = FALSE))))
        }))
        files <- c(grid_path, if (period == "water-year") spi_path, if (make_maps) rows$map)
        saveRDS(list(signature = signature, files = files, md5 = unname(tools::md5sum(files)), records = rows, comparison = compare), marker)
        built <- built + nrow(rows)
      }
      records[[length(records) + 1L]] <- rows; comparisons[[length(comparisons) + 1L]] <- compare
      write.csv(do.call(rbind, records), file.path(root, "last-batch.csv"), row.names = FALSE)
    }
    rm(reference); gc(FALSE)
  }
  if (!identical(unname(tools::md5sum(audit$plan$path)), audit$plan$md5)) stop("Monthly inputs changed during the build. Rerun before review.")
  records <- do.call(rbind, records)
  if (nrow(records) != length(years) * historic_monthly_products_per_year() || anyDuplicated(records[c("water_year", "period", "metric")])) stop("Incomplete pilot product set.")
  write.csv(records, file.path(root, "manifest.csv"), row.names = FALSE)
  write.csv(do.call(rbind, comparisons), file.path(root, "existing-comparison.csv"), row.names = FALSE)
  writeLines(c("Isolated local pilot: no downloads, shared fit writes, staging, publication or archive replacement.",
    "Water year October-September; cool season October-March; spring April-June; monsoon July-September.",
    "The three seasonal windows partition the water year without gaps or overlaps; July-September differs from the June 15-September 30 meteorological monsoon season.",
    sprintf("Retrospective comparison: common complete water years WY%d-WY%d; target included once; later years included.", min(reference_years), max(reference_years)),
    "Ranks: 100*(lower+0.5*tied)/n; 30 years and 90% eligible windows; records need every window; zero dry record <=2% zeros.",
    "Mean temperature: (monthly maxt+mint)/2, actual day weights including leap days. Total precipitation: sum, inches.",
    "Departures: mean of matching 1991-2020 seasons, minimum 27 years; unavailable is not zero.",
    sprintf("SPI-12 September: existing gamma-MLE/zero-adjusted policy; eligible calibration windows WY%d-WY%d; support/fit QC preserved.", min(cal_years), max(cal_years)),
    "Precipitation totals can be compared to cached daily-derived archive totals; no fixed equality tolerance assumed.",
    "Older archive ranks have a shorter baseline and temperature departures are separate high/low metrics, not identical comparisons."), file.path(root, "methods.txt"))
  if (make_maps) historic_monthly_gallery(records, root, reference_years, normal_years, cal_years)
  summary <- data.frame(status = "READY", years = length(years), maps = if (make_maps) nrow(records) else 0L,
    products = nrow(records), built = built, reused = reused, requests = 0L,
    comparison_first_year = min(reference_years), comparison_last_year = max(reference_years),
    elapsed_seconds = round(proc.time()[["elapsed"]] - started, 2))
  write.csv(summary, file.path(root, "summary.csv"), row.names = FALSE)
  list(summary = summary, records = records, gallery = file.path(root, "index.html"))
}
