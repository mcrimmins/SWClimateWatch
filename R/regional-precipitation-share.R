# Ratio of reference means, using matched complete annual and quarterly samples.
regional_precipitation_shares <- function(annual, seasonal) {
  if (!is.numeric(annual) || !is.matrix(seasonal) || ncol(seasonal) != 4L || nrow(seasonal) != length(annual))
    stop("Require annual values and four matching seasonal columns.")
  if (any(is.finite(annual) & annual < 0) || any(is.finite(seasonal) & seasonal < 0))
    stop("Reference precipitation must be non-negative.")
  supported <- is.finite(annual) & annual > 0 & rowSums(is.finite(seasonal)) == 4L
  totals <- rowSums(seasonal)
  tolerance <- pmax(.Machine$double.eps * 32, pmax(abs(annual), abs(totals)) * 2e-6)
  if (any(abs(totals[supported] - annual[supported]) > tolerance[supported]))
    stop("Seasonal reference totals do not match the annual reference; rebuild matched inputs.")
  result <- matrix(NA_real_, nrow = length(annual), ncol = 4L, dimnames = dimnames(seasonal))
  result[supported, ] <- 100 * seasonal[supported, , drop = FALSE] / annual[supported]
  if (any(result > 100.001, na.rm = TRUE)) stop("Derived share exceeds the annual total.")
  # Correct only Float32 storage roundoff at the physical endpoint, never a real exceedance.
  result[result > 100 & result <= 100.001] <- 100
  if (any(abs(rowSums(result)[supported] - 100) > .001)) stop("Supported seasonal shares do not sum to 100 percent.")
  result
}

regional_share_style <- function() list(
  breaks = c(-Inf, seq(10, 90, 10), Inf),
  labels = c("<10%", "10-20%", "20-30%", "30-40%", "40-50%", "50-60%", "60-70%", "70-80%", "80-90%", ">=90%"),
  colors = c("#f7fbff", "#deebf7", "#c6dbef", "#9ecae1", "#6baed6", "#4292c6", "#2171b5", "#08519c", "#08306b", "#041b42"))

plot_regional_precipitation_share <- function(raster, period) {
  spec <- regional_reference_seasons()[[period]]; style <- regional_share_style()
  data <- terra::as.data.frame(raster, xy = TRUE, na.rm = FALSE); names(data) <- c("x", "y", "value")
  classes <- as.character(cut(data$value, style$breaks, labels = style$labels, right = FALSE))
  classes[!is.finite(data$value)] <- "Unavailable"
  data$class <- factor(classes, levels = c(style$labels, "Unavailable"))
  plot <- plot_regional_climate_reference(raster, "precipitation", 1991:2020)
  plot$layers[[1L]] <- ggplot2::geom_tile(data = data, ggplot2::aes(x, y, fill = class),
    width = terra::res(raster)[1], height = terra::res(raster)[2], show.legend = TRUE)
  suppressMessages(plot + ggplot2::scale_fill_manual(
    values = stats::setNames(c(style$colors, "#ede8df"), levels(data$class)), drop = FALSE,
    name = "Share of average annual precipitation (%)") + ggplot2::labs(
      title = paste(spec$label, "share of annual precipitation"),
      subtitle = paste(spec$text, "| 1991-2020 reference | Ratio of seasonal to annual means")))
}

regional_share_dependencies <- function(annual_dir, seasonal_dir) {
  c(annual = file.path(annual_dir, "annual-precipitation.tif"), stats::setNames(
    file.path(seasonal_dir, names(regional_reference_seasons()), "precipitation.tif"), names(regional_reference_seasons())))
}

verify_regional_precipitation_share_pilot <- function(output_dir, annual_dir, seasonal_dir) {
  marker <- file.path(output_dir, "complete.rds")
  saved <- if (file.exists(marker)) tryCatch(readRDS(marker), error = function(e) NULL) else NULL
  dependencies <- regional_share_dependencies(annual_dir, seasonal_dir)
  if (!is.list(saved) || !length(saved$files) || !all(file.exists(saved$files)) ||
      !all(file.exists(dependencies)) || !identical(unname(tools::md5sum(saved$files)), saved$md5) ||
      !identical(unname(tools::md5sum(dependencies)), saved$source_md5))
    stop("Missing, changed or stale seasonal share maps; rebuild the share pilot.")
  invisible(saved)
}

build_regional_precipitation_share_pilot <- function(
    annual_dir = "data/diagnostics/regional-climate-reference-pilot",
    seasonal_dir = "data/diagnostics/regional-seasonal-reference-pilot",
    output_dir = "data/diagnostics/regional-precipitation-share-pilot", force = FALSE) {
  started <- proc.time()[["elapsed"]]
  regional_climate_site_verify(annual_dir, seasonal_dir)
  dependencies <- regional_share_dependencies(annual_dir, seasonal_dir)
  hashes <- unname(tools::md5sum(dependencies))
  signature <- digest::digest(list(hashes, regional_share_style(),
    regional_reference_function_text(list(regional_precipitation_shares, plot_regional_precipitation_share,
      plot_regional_climate_reference)), "ratio-of-means-matched-v1"), algo = "sha256")
  saved <- if (!force) tryCatch(verify_regional_precipitation_share_pilot(output_dir, annual_dir, seasonal_dir), error = function(e) NULL) else NULL
  if (is.list(saved) && identical(saved$signature, signature)) {
    saved$result$summary$event <- "REUSED"
    message("Seasonal precipitation shares: REUSED.")
    return(invisible(saved$result))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  template <- terra::rast(dependencies[1]); annual <- terra::values(template, mat = FALSE)
  seasonal <- vapply(dependencies[-1], function(path) {
    raster <- terra::rast(path); terra::compareGeom(template, raster, stopOnError = TRUE, tolerance = 0)
    terra::values(raster, mat = FALSE)
  }, numeric(terra::ncell(template)))
  shares <- regional_precipitation_shares(annual, seasonal)
  files <- character(); periods <- names(regional_reference_seasons())
  samples <- read.csv(file.path(annual_dir, "samples.csv"), stringsAsFactors = FALSE)[c("location", "longitude", "latitude")]
  for (i in seq_along(periods)) {
    period <- periods[i]; raster <- terra::setValues(template, shares[, i]); names(raster) <- "share_of_annual_precipitation_percent"
    tif <- file.path(output_dir, paste0(period, "-precipitation-share.tif")); png <- sub("[.]tif$", ".png", tif)
    terra::writeRaster(raster, tif, overwrite = TRUE, datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
    message("Rendering ", period, " precipitation share.")
    save_southwest_map(plot_regional_precipitation_share(raster, period), png,
      logo_path = southwest_brand_logo_path(), footer_text = paste0(
        "PRISM Climate Group via RCC-ACIS\n1991-2020 | 30 matched complete years | 100 x seasonal mean / annual mean\nClimate Science Applications Program - University of Arizona"))
    point_values <- terra::extract(raster, as.matrix(samples[c("longitude", "latitude")]))
    samples[[period]] <- as.numeric(point_values[[ncol(point_values)]])
    files <- c(files, tif, png)
  }
  supported <- rowSums(is.finite(shares)) == 4L
  summary <- data.frame(status = "READY", event = "BUILT", maps = 4L, supported_cells = sum(supported),
    max_sum_difference_percent = if (any(supported)) max(abs(rowSums(shares)[supported] - 100)) else NA_real_, requests = 0L,
    elapsed_seconds = round(proc.time()[["elapsed"]] - started, 2))
  methods <- data.frame(reference = "1991-2020", required_complete_years = 30L,
    formula = "100 * average seasonal total / average annual total", averaging = "Ratio of means, not mean of yearly ratios",
    coverage = "All four seasonal means and annual mean must be supported; annual mean must be positive",
    tolerance = "Float32 consistency tolerance only; no filling, year substitution or rescaling to force sums")
  write.csv(methods, file.path(output_dir, "methods.csv"), row.names = FALSE)
  write.csv(samples, file.path(output_dir, "samples.csv"), row.names = FALSE)
  write.csv(summary, file.path(output_dir, "summary.csv"), row.names = FALSE)
  files <- c(files, file.path(output_dir, c("methods.csv", "samples.csv", "summary.csv")))
  result <- list(summary = summary, samples = samples)
  saveRDS(list(signature = signature, source_md5 = hashes, files = files,
    md5 = unname(tools::md5sum(files)), result = result), file.path(output_dir, "complete.rds"))
  message("Seasonal shares ready locally; no downloads or publication.")
  invisible(result)
}
