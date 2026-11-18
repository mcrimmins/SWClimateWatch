# Calendar-quarter reference extension. Annual pilot and monthly inputs stay separate.
regional_reference_seasons <- function() list(
  winter = list(label = "Winter", months = 1:3, text = "January-March"),
  spring = list(label = "Spring", months = 4:6, text = "April-June"),
  summer = list(label = "Summer", months = 7:9, text = "July-September"),
  fall = list(label = "Fall", months = 10:12, text = "October-December"))

regional_seasonal_style <- function(variable) {
  variable <- match.arg(variable, c("precipitation", "temperature"))
  if (variable == "precipitation") list(
    breaks = c(-Inf, .5, 1, 2, 3, 4, 6, 8, 12, 16, Inf),
    labels = c("<0.5", "0.5-1", "1-2", "2-3", "3-4", "4-6", "6-8", "8-12", "12-16", ">=16"),
    colors = regional_reference_style("precipitation")$colors,
    legend = "Seasonal precipitation (inches)") else list(
    breaks = c(-Inf, 20, 30, 40, 50, 60, 70, 80, 90, Inf),
    labels = c("<20", "20-30", "30-40", "40-50", "50-60", "60-70", "70-80", "80-90", ">=90"),
    colors = c("#313695", "#4575b4", "#74add1", "#e0f3f8", "#ffffbf", "#fee090", "#fdae61", "#f46d43", "#7f0000"),
    legend = "Mean temperature (degrees F)")
}

regional_seasonal_classes <- function(values, variable) {
  style <- regional_seasonal_style(variable)
  classes <- as.character(cut(values, style$breaks, labels = style$labels, right = FALSE))
  classes[!is.finite(values)] <- "Unavailable"
  factor(classes, levels = c(style$labels, "Unavailable"))
}

regional_seasonal_statistics <- function(plan, years, period) {
  seasons <- regional_reference_seasons()
  if (length(period) != 1L || !period %in% names(seasons)) stop("Choose winter, spring, summer or fall.")
  template <- terra::rast(plan$path[1])
  p <- t <- matrix(NA_real_, nrow = terra::ncell(template), ncol = length(years))
  for (i in seq_along(years)) {
    end <- sprintf("%d-%02d", years[i], max(seasons[[period]]$months))
    rain <- prism_monthly_precipitation_window(plan, end, duration = 3L)
    temperature <- prism_monthly_temperature_window(plan, end, duration = 3L)
    terra::compareGeom(template, rain, temperature, stopOnError = TRUE, tolerance = 0)
    p[, i] <- terra::values(rain, mat = FALSE)
    t[, i] <- terra::values(temperature, mat = FALSE)
    if (i %% 10L == 0L) message(seasons[[period]]$label, " reference: ", i, "/", length(years), " seasons summarized.")
  }
  list(template = template, statistics = regional_reference_statistics(p, t))
}

plot_regional_seasonal_reference <- function(raster, variable, years, period) {
  season <- regional_reference_seasons()[[period]]
  style <- regional_seasonal_style(variable)
  data <- terra::as.data.frame(raster, xy = TRUE, na.rm = FALSE)
  names(data) <- c("x", "y", "value")
  data$class <- regional_seasonal_classes(data$value, variable)
  plot <- plot_regional_climate_reference(raster, variable, years)
  plot$layers[[1L]] <- ggplot2::geom_tile(data = data, ggplot2::aes(x, y, fill = class),
    width = terra::res(raster)[1], height = terra::res(raster)[2], show.legend = TRUE)
  suppressMessages(plot + ggplot2::scale_fill_manual(
    values = stats::setNames(c(style$colors, "#ede8df"), levels(data$class)), drop = FALSE,
    name = style$legend) + ggplot2::labs(
      title = paste(season$label, if (variable == "precipitation") "average precipitation" else "mean temperature"),
      subtitle = sprintf("%s | %d-%d calendar-quarter reference | PRISM monthly grids", season$text, min(years), max(years))))
}

regional_seasonal_gallery <- function(output_dir, years) {
  specs <- c(list(annual = list(label = "Annual", text = "January-December")), regional_reference_seasons())
  cards <- unlist(lapply(names(specs), function(id) {
    spec <- specs[[id]]
    paths <- paste0(id, "/", c("precipitation.png", "temperature.png"))
    paste0('<section id="', id, '"><h2>', spec$label, ' &middot; ', spec$text, '</h2><div class="maps">',
      paste(sprintf('<article><a href="%s" target="_blank" rel="noopener"><img loading="lazy" src="%s" alt="%s %s reference"></a><p><a href="%s" target="_blank" rel="noopener">Open full-resolution PNG</a></p></article>',
        paths, paths, spec$label, c("precipitation", "temperature"), paths), collapse = "\n"), '</div></section>')
  }))
  html <- c('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>Annual and seasonal regional climate reference</title>',
    '<style>body{font:16px system-ui,sans-serif;color:#26363d;background:#f4f6f7;max-width:1600px;margin:24px auto;padding:0 20px}p{line-height:1.5}.maps{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}article{background:white;border:1px solid #d8e0e4;border-radius:8px;padding:10px}img{width:100%;height:auto}a{color:#14647c}nav{display:flex;gap:18px;flex-wrap:wrap}@media(max-width:850px){.maps{grid-template-columns:1fr}}</style></head><body>',
    sprintf('<h1>Regional climate reference &middot; %d-%d</h1>', min(years), max(years)),
    '<p>Local review only. Reference climate from cached PRISM monthly grids, not recent conditions or anomalies. Project-calculated references, not downloaded official NOAA normals.</p>',
    '<nav><a href="#annual">Annual</a><a href="#winter">Winter &middot; Jan-Mar</a><a href="#spring">Spring &middot; Apr-Jun</a><a href="#summer">Summer &middot; Jul-Sep</a><a href="#fall">Fall &middot; Oct-Dec</a></nav>',
    '<p>Precipitation maps show average period totals in inches. Temperature maps use day-weighted means within each year, then equal weighting among years. All four seasons use shared seasonal color scales; annual maps have their own scales.</p>',
    sprintf('<p>Calendar quarters: winter January-March, spring April-June, summer July-September and fall October-December. Each seasonal map requires %d complete seasons at each cell. Missing values are not filled; beige marks unavailable support. Annual coverage is checked separately.</p>', length(years)),
    cards, '<p><a href="samples.csv">Seasonal sample values</a> &middot; <a href="methods.csv">Methods</a> &middot; <a href="source-inventory.csv">Source inventory</a></p></body></html>')
  writeLines(html, file.path(output_dir, "index.html"), useBytes = TRUE)
}

build_regional_seasonal_reference_pilot <- function(years = 1991:2020,
    cache_dir = prism_monthly_cache_dir(), output_dir = "data/diagnostics/regional-seasonal-reference-pilot",
    annual_dir = "data/diagnostics/regional-climate-reference-pilot", force = FALSE, bbox = swc_region$bbox) {
  if (!is.logical(force) || length(force) != 1L || is.na(force)) stop("force must be TRUE or FALSE.")
  started <- proc.time()[["elapsed"]]
  # One read-only audit of the shared 1,080 monthly inputs, then reuse across quarters.
  annual <- build_regional_climate_reference_pilot(years = years, cache_dir = cache_dir,
    output_dir = annual_dir, bbox = bbox)
  plan <- read.csv(file.path(annual_dir, "source-inventory.csv"), stringsAsFactors = FALSE)
  if (!identical(unname(tools::md5sum(plan$path)), plan$md5)) stop("Monthly sources changed during reference preparation; rerun.")
  plan$complete <- TRUE
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  results <- samples <- list()
  seasons <- regional_reference_seasons()
  for (period in names(seasons)) {
    period_started <- proc.time()[["elapsed"]]
    spec <- seasons[[period]]
    rows <- plan[as.integer(substr(plan$month, 6, 7)) %in% spec$months, ]
    signature <- digest::digest(list(years, period, spec,
      rows[c("month", "variable", "request_signature", "md5")],
      regional_seasonal_style("precipitation"), regional_seasonal_style("temperature"),
      regional_reference_function_text(list(regional_seasonal_statistics, regional_reference_statistics, plot_regional_seasonal_reference,
        plot_regional_climate_reference, regional_seasonal_classes, prism_monthly_precipitation_window,
        prism_monthly_temperature_window)), "quarter-reference-v2"), algo = "sha256")
    root <- file.path(output_dir, period); dir.create(root, recursive = TRUE, showWarnings = FALSE)
    marker <- file.path(root, "complete.rds")
    saved <- if (file.exists(marker)) tryCatch(readRDS(marker), error = function(e) NULL) else NULL
    reused <- !force && is.list(saved) && identical(saved$signature, signature) && length(saved$files) &&
      all(file.exists(saved$files)) && identical(unname(tools::md5sum(saved$files)), saved$md5)
    if (reused) {
      record <- saved$record; sample <- saved$samples; record$event <- "REUSED"
      message(spec$label, " reference: REUSED.")
    } else {
      product <- regional_seasonal_statistics(plan, years, period)
      stats <- product$statistics; template <- product$template
      paths <- file.path(root, c("precipitation.tif", "temperature.tif", "precipitation-years.tif", "temperature-years.tif"))
      fields <- c("precipitation_inches", "mean_temperature_f", "precipitation_years", "temperature_years")
      for (i in seq_along(paths)) terra::writeRaster(terra::setValues(template, stats[, fields[i]]), paths[i],
        overwrite = TRUE, datatype = if (i < 3L) "FLT4S" else "INT2U", gdal = "COMPRESS=DEFLATE")
      sample <- annual$samples[c("location", "longitude", "latitude")]; sample$period <- period
      points <- as.matrix(sample[c("longitude", "latitude")])
      for (i in 1:2) {
        raster <- terra::rast(paths[i]); names(raster) <- fields[i]
        value <- terra::extract(raster, points)
        sample[[fields[i]]] <- as.numeric(value[[ncol(value)]])
        variable <- c("precipitation", "temperature")[i]
        message("Rendering ", period, " ", variable, " reference.")
        save_southwest_map(plot_regional_seasonal_reference(raster, variable, years, period),
          sub("[.]tif$", ".png", paths[i]), logo_path = southwest_brand_logo_path(),
          footer_text = sprintf("PRISM Climate Group via RCC-ACIS\n%d-%d | %d complete %s seasons | Project-calculated reference\nClimate Science Applications Program - University of Arizona",
            min(years), max(years), length(years), spec$text))
      }
      record <- data.frame(period = period, months = spec$text, event = "BUILT", maps = 2L,
        precipitation_valid_cells = sum(is.finite(stats[, "precipitation_inches"])),
        temperature_valid_cells = sum(is.finite(stats[, "mean_temperature_f"])), requests = 0L)
      write.csv(data.frame(period = period, months = spec$text, start_year = min(years), end_year = max(years),
        complete_seasons_required = length(years), input_signature = signature), file.path(root, "methods.csv"), row.names = FALSE)
      files <- c(paths, sub("[.]tif$", ".png", paths[1:2]), file.path(root, "methods.csv"))
      saveRDS(list(signature = signature, files = files, md5 = unname(tools::md5sum(files)), record = record, samples = sample), marker)
    }
    record$elapsed_seconds <- round(proc.time()[["elapsed"]] - period_started, 2)
    results[[period]] <- record; samples[[period]] <- sample
  }
  annual_root <- file.path(output_dir, "annual"); dir.create(annual_root, showWarnings = FALSE)
  for (variable in c("precipitation", "temperature")) {
    from <- sub("[.]tif$", ".png", annual$paths[[variable]]); to <- file.path(annual_root, paste0(variable, ".png"))
    if (!file.exists(to) || !identical(unname(tools::md5sum(from)), unname(tools::md5sum(to))))
      if (!file.copy(from, to, overwrite = TRUE)) stop("Could not copy annual reference into combined preview.")
    if (!identical(unname(tools::md5sum(from)), unname(tools::md5sum(to)))) stop("Annual preview copy checksum mismatch.")
  }
  summary <- do.call(rbind, results); samples <- do.call(rbind, samples)
  write.csv(summary, file.path(output_dir, "summary.csv"), row.names = FALSE)
  write.csv(samples, file.path(output_dir, "samples.csv"), row.names = FALSE)
  write.csv(plan[c("month", "variable", "path", "md5", "request_signature")], file.path(output_dir, "source-inventory.csv"), row.names = FALSE)
  methods <- data.frame(start_year = min(years), end_year = max(years), calendar = "JFM/AMJ/JAS/OND calendar quarters",
    complete_seasons_required = length(years), precipitation = "Mean of complete three-month sums; inches",
    temperature = "Actual month-day weights within season; equal weights among season-years; degrees F",
    missing = "No zero filling; each period/variable requires all reference seasons independently",
    annual = "Original annual reference preserved; annual maps use separate scales and coverage")
  write.csv(methods, file.path(output_dir, "methods.csv"), row.names = FALSE)
  regional_seasonal_gallery(output_dir, years)
  totals <- data.frame(status = "READY", seasonal_maps = 8L, annual_maps = 2L, annual_event = annual$summary$event, built = sum(summary$event == "BUILT"),
    reused = sum(summary$event == "REUSED"), requests = 0L, elapsed_seconds = round(proc.time()[["elapsed"]] - started, 2))
  message("Annual/seasonal gallery ready: ", output_dir, ". No downloads, site changes or publication.")
  invisible(list(summary = summary, totals = totals, samples = samples, methods = methods))
}
