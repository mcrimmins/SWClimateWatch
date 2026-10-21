# Unpublished static daily explorer. Native-grid summaries; cached PNG displays.
daily_explorer_version <- 1L

daily_explorer_water_year <- function(date) {
  date <- as.Date(date)
  as.integer(format(date, "%Y")) + as.integer(format(date, "%m") >= "10")
}

daily_explorer_index <- function(start_date, end_date, manifest) {
  rows <- manifest[manifest$product == "daily" &
    manifest$aoi_id == swc_prism$aoi_id &
    manifest$variable %in% c("pcpn", "maxt", "mint") &
    manifest$start_date <= end_date & manifest$end_date >= start_date, , drop = FALSE]
  rows <- rows[!duplicated(rows$path, fromLast = TRUE), , drop = FALSE]
  result <- lapply(seq_len(nrow(rows)), function(i) {
    path <- rows$path[[i]]
    if (!file.exists(path)) return(NULL)
    raster <- terra::rast(path)
    dates <- prism_raster_dates(path, raster)
    keep <- which(dates >= start_date & dates <= end_date)
    if (!length(keep)) return(NULL)
    data.frame(date = as.character(dates[keep]), variable = rows$variable[[i]],
               path = path, layer = keep,
               recent = grepl("[\\\\/]daily[\\\\/]recent[\\\\/]", path),
               span = as.integer(rows$end_date[[i]] - rows$start_date[[i]]),
               processed = if ("processed_at" %in% names(rows)) {
                 stamp <- suppressWarnings(as.numeric(as.POSIXct(rows$processed_at[[i]], tz = "UTC")))
                 if (is.na(stamp)) 0 else stamp
               } else 0, stringsAsFactors = FALSE)
  })
  result <- do.call(rbind, result)
  if (is.null(result) || !nrow(result)) stop("No cached PRISM days in the selected period.")
  groups <- split(seq_len(nrow(result)), paste(result$date, result$variable))
  keep <- vapply(groups, function(group) {
    candidates <- result[group, , drop = FALSE]
    best <- order(!candidates$recent, candidates$span, -candidates$processed)[[1L]]
    tied <- candidates$recent == candidates$recent[[best]] &
      candidates$span == candidates$span[[best]] & candidates$processed == candidates$processed[[best]]
    if (sum(tied) > 1L) stop("Ambiguous overlapping daily sources; resolve the PRISM manifest before building.")
    group[[best]]
  }, integer(1))
  result[keep, c("date", "variable", "path", "layer"), drop = FALSE]
}

daily_explorer_weighted_quantile <- function(values, weights, probability = 0.99) {
  ok <- is.finite(values) & is.finite(weights) & weights > 0
  if (!any(ok)) return(NA_real_)
  values <- values[ok]; weights <- weights[ok]
  order <- order(values)
  values[order][which(cumsum(weights[order]) / sum(weights) >= probability)[[1L]]]
}

daily_explorer_summary <- function(values, weights, variable, normal = NULL,
                                   p10 = NULL, p90 = NULL, min_coverage = 0.95) {
  inside <- is.finite(weights) & weights > 0
  denominator <- sum(weights[inside])
  good <- inside & is.finite(values)
  coverage <- if (denominator > 0) sum(weights[good]) / denominator else 0
  output <- list(coverage = coverage, mean = NA_real_, departure = NA_real_,
    rain010 = NA_real_, rain050 = NA_real_, rain100 = NA_real_,
    spatial_p99 = NA_real_, warm = NA_real_, cold = NA_real_, freeze = NA_real_)
  if (coverage < min_coverage) return(output)
  output$mean <- stats::weighted.mean(values[good], weights[good])
  area_fraction <- function(test, eligible = good) {
    valid <- eligible & !is.na(test)
    if (sum(weights[valid]) / denominator < min_coverage) return(NA_real_)
    sum(weights[valid & test], na.rm = TRUE) / sum(weights[valid]) * 100
  }
  if (variable == "pcpn") {
    output$rain010 <- area_fraction(values >= 0.10 - swc_prism$wet_day_storage_tolerance_inches)
    output$rain050 <- area_fraction(values >= 0.50 - swc_prism$wet_day_storage_tolerance_inches)
    output$rain100 <- area_fraction(values >= 1 - swc_prism$wet_day_storage_tolerance_inches)
    output$spatial_p99 <- daily_explorer_weighted_quantile(values, weights)
  } else {
    if (!is.null(normal)) {
      paired <- good & is.finite(normal)
      if (sum(weights[paired]) / denominator >= min_coverage) {
        output$departure <- stats::weighted.mean(values[paired] - normal[paired], weights[paired])
      }
    }
    if (!is.null(p90)) output$warm <- area_fraction(values > p90)
    if (!is.null(p10)) output$cold <- area_fraction(values < p10)
    if (variable == "mint") output$freeze <- area_fraction(values <= 32)
  }
  output
}

daily_explorer_reference_path <- function(variable, statistic) {
  prism_climatology_path(variable, statistic, swc_prism$normal_start, swc_prism$normal_end)
}

# Use paired native cells only; never fill a missing maximum or minimum.
daily_explorer_mean_temperature <- function(maximum, minimum) {
  terra::compareGeom(maximum, minimum, stopOnError = TRUE)
  (maximum + minimum) / 2
}

daily_explorer_reference <- function(path, date, template) {
  if (!file.exists(path)) return(NULL)
  reference <- terra::rast(path)
  time <- as.Date(terra::time(reference))
  keys <- if (length(time) == terra::nlyr(reference) && !anyNA(time)) {
    format(time, "%m-%d")
  } else sub("^.*_", "", names(reference))
  selected <- which(keys == format(as.Date(date), "%m-%d"))
  if (length(selected) != 1L) return(NULL)
  reference <- reference[[selected]]
  terra::compareGeom(template, reference, stopOnError = TRUE)
  reference
}

daily_explorer_map_context <- function(states = southwest_state_boundaries(),
                                       cities = southwest_reference_cities()) {
  list(states = states, counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(), cities = cities,
    tribal_areas = if (isTRUE(getOption("swc.map.tribal", TRUE))) southwest_tribal_boundaries() else NULL,
    rivers = if (isTRUE(getOption("swc.map.rivers", FALSE))) southwest_major_rivers() else NULL,
    interstates = if (isTRUE(getOption("swc.map.interstates", FALSE))) southwest_interstates() else NULL)
}

daily_explorer_plot <- function(raster, variable, view, date, states, cities, path,
                                context = NULL, city_label_halo = FALSE,
                                city_label_size = 2.05, city_label_fontface = "bold",
                                city_label_halo_radius = 0.07, city_label_style = "label",
                                city_label_colour = "#202b30", city_label_halo_colour = "white") {
  if (is.null(context)) context <- daily_explorer_map_context(states, cities)
  data <- terra::as.data.frame(raster, xy = TRUE, na.rm = TRUE)
  names(data)[3L] <- "value"
  if (variable == "pcpn") {
    breaks <- c(-Inf, 0, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 1.5, 2, 3, Inf)
    labels <- c("0", ">0-0.01", "0.01-0.05", "0.05-0.10", "0.10-0.25",
      "0.25-0.50", "0.50-1", "1-1.5", "1.5-2", "2-3", ">3")
    colors <- c("#f5f3ef", "#edf5f7", "#dcecf1", "#c1dfe9", "#a9d4e2",
      "#68b6c8", "#2f8d9c", "#427845", "#2b562f", "#8d659b", "#572968")
    title <- "Daily precipitation"; unit <- "Precipitation (inches)"
  } else if (view == "departure") {
    breaks <- c(-Inf, -20, -10, -5, -2, 2, 5, 10, 20, Inf)
    labels <- c("<=-20", "-20 to -10", "-10 to -5", "-5 to -2", "-2 to 2", "2-5", "5-10", "10-20", ">20")
    colors <- c("#253494", "#2c7fb8", "#7fcdbb", "#c7e9e3", "#f5f3ef", "#fee8b4", "#fdb163", "#df633b", "#a32424")
    title <- switch(variable, maxt = "Daily maximum temperature departure",
      mint = "Daily minimum temperature departure", tmean = "Daily mean temperature departure")
    unit <- "Departure (degrees F)"
  } else {
    breaks <- c(-Inf, 0, 20, 32, 50, 70, 90, 100, 110, Inf)
    labels <- c("<=0", "0-20", "20-32", "32-50", "50-70", "70-90", "90-100", "100-110", ">110")
    colors <- c("#4a3182", "#466db0", "#8cb9d3", "#c4e2da", "#f3efc3", "#f6cb7d", "#e9934e", "#cb5033", "#892225")
    title <- switch(variable, maxt = "Daily maximum temperature",
      mint = "Daily minimum temperature", tmean = "Daily mean temperature")
    unit <- "Temperature (degrees F)"
  }
  data$class <- cut(data$value, breaks, labels = labels, include.lowest = TRUE)
  # Reuse public geographic context, city placement, and theme. Only the raster
  # layer and its categorical scale are specific to this explorer.
  plot <- southwest_raster_map(raster = raster, states = context$states,
    title = title,
    subtitle = paste(date, if (view == "departure") " | relative to 1991-2020" else ""),
    caption = "Climate Science Applications Program \u2013 University of Arizona\nData: PRISM Climate Group via RCC-ACIS",
    fill_label = unit, scale_type = "continuous",
    counties = context$counties, countries = context$countries,
    tribal_areas = context$tribal_areas, rivers = context$rivers,
    interstates = context$interstates, cities = context$cities,
    city_label_style = city_label_style, city_label_halo = city_label_halo,
    city_label_size = city_label_size, city_label_fontface = city_label_fontface,
    city_label_halo_radius = city_label_halo_radius,
    city_label_colour = city_label_colour, city_label_halo_colour = city_label_halo_colour)
  # Explicit native cell width/height avoids inferring spacing after NA removal.
  plot$layers[[1L]] <- ggplot2::geom_tile(data = data,
    ggplot2::aes(x, y, fill = class), width = terra::res(raster)[1L],
    height = terra::res(raster)[2L], show.legend = TRUE)
  # Replacing the shared continuous scale with this explorer's exact classes is
  # intentional; suppress only ggplot's scale-replacement informational message.
  plot <- suppressMessages(plot +
    ggplot2::scale_fill_manual(values = stats::setNames(colors, labels),
      drop = FALSE, name = unit, na.value = "transparent") +
    ggplot2::guides(fill = ggplot2::guide_legend(
      nrow = 1, byrow = TRUE,
      title.position = "top", title.hjust = 0.5, label.position = "bottom",
      keywidth = grid::unit(1.55, "cm"), keyheight = grid::unit(0.35, "cm"))) +
    ggplot2::theme(legend.text = ggplot2::element_text(size = 7.5),
      legend.spacing.x = grid::unit(0.04, "cm")))
  ggplot2::ggsave(path, plot, width = 9.3, height = 6.5, dpi = 120, bg = "white")
}

build_daily_explorer <- function(water_years = NULL, start_date = NULL, end_date = NULL,
    output_dir = file.path("data", "diagnostics", "daily-explorer"), force = FALSE,
    manifest = read_prism_manifest(prism_processed_manifest_path()), publication_mode = FALSE) {
  relevant <- manifest[manifest$product == "daily" & manifest$aoi_id == swc_prism$aoi_id &
    manifest$variable %in% c("pcpn", "maxt", "mint") & file.exists(manifest$path), , drop = FALSE]
  if (!nrow(relevant)) stop("No processed daily PRISM files are cached.")
  latest <- max(as.Date(relevant$end_date))
  if (is.null(water_years)) water_years <- daily_explorer_water_year(latest)
  if (!length(water_years) || anyNA(water_years) || any(water_years != as.integer(water_years)) ||
      any(water_years < 1982 | water_years > 2200)) stop("Supply valid water years, e.g. 2027L.")
  water_years <- sort(unique(as.integer(water_years)))
  first <- as.Date(sprintf("%d-10-01", min(water_years) - 1L))
  last <- min(latest, as.Date(sprintf("%d-09-30", max(water_years))))
  if (!is.null(start_date)) first <- max(first, as.Date(start_date))
  if (!is.null(end_date)) last <- min(last, as.Date(end_date))
  if (is.na(first) || is.na(last) || first > last) stop("No valid dates in requested period.")
  dates <- seq(first, last, by = "day")
  dates <- dates[daily_explorer_water_year(dates) %in% water_years]
  index <- daily_explorer_index(first, last, relevant)
  template <- terra::rast(index$path[[1L]])[[index$layer[[1L]]]]
  if (!terra::is.lonlat(template)) stop("Prototype maps require the native geographic PRISM grid.")
  states <- southwest_state_boundaries()
  context <- daily_explorer_map_context(states)
  areas <- sf::st_transform(southwest_state_boundaries(c("arizona", "new mexico")), terra::crs(template))
  area_weights <- terra::values(terra::cellSize(template, unit = "km"), mat = FALSE)
  masks <- lapply(c("arizona", "new mexico"), function(name) {
    inside <- terra::rasterize(terra::vect(areas[areas$ID == name, ]), template,
      field = 1, background = NA)
    ifelse(is.finite(terra::values(inside, mat = FALSE)), area_weights, 0)
  })
  names(masks) <- c("AZ", "NM")
  masks <- c(list(AZNM = masks$AZ + masks$NM), masks)
  if (any(vapply(masks, sum, numeric(1)) <= 0)) stop("Region masks are empty.")
  dir.create(file.path(output_dir, "maps"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(output_dir, "cache"), recursive = TRUE, showWarnings = FALSE)
  hashes <- new.env(parent = emptyenv())
  checksum <- function(path) {
    if (!file.exists(path)) return("missing")
    if (!exists(path, hashes, inherits = FALSE)) assign(path, unname(tools::md5sum(path)), hashes)
    get(path, hashes, inherits = FALSE)
  }
  code <- vapply(c("R/daily-explorer.R", "R/map-southwest.R", "R/map-reference-layers.R"), checksum, character(1))
  context_signature <- digest::digest(context, algo = "sha256")
  records <- list(); built <- 0L; reused <- 0L
  for (i in seq_along(dates)) {
    date <- as.character(dates[[i]])
    sources <- index[index$date == date, , drop = FALSE]
    refs <- unlist(lapply(c("maxt", "mint"), function(v) {
      vapply(c("mean", "p10", "p90"), function(s) daily_explorer_reference_path(v, s), character(1))
    }), use.names = FALSE)
    signature <- digest::digest(list(version = daily_explorer_version, code = code, map_context = context_signature,
      sources = sources, checksums = vapply(c(sources$path, refs), checksum, character(1)),
      geometry = sf::st_as_binary(sf::st_geometry(areas))), algo = "sha256")
    cache_path <- file.path(output_dir, "cache", paste0(date, ".rds"))
    cached <- if (file.exists(cache_path)) tryCatch(readRDS(cache_path), error = function(e) NULL) else NULL
    if (!force && !is.null(cached) && identical(cached$signature, signature) &&
        all(file.exists(file.path(output_dir, unlist(cached$record$images, use.names = FALSE))))) {
      records[[date]] <- cached$record; reused <- reused + 1L; next
    }
    message("Daily Explorer ", i, "/", length(dates), ": ", date)
    record <- list(date = date, water_year = daily_explorer_water_year(date),
      images = list(), regions = list(AZNM = list(), AZ = list(), NM = list()))
    for (variable in c("pcpn", "maxt", "mint", "tmean")) {
      if (variable == "tmean") {
        pair <- lapply(c("maxt", "mint"), function(v) {
          row <- sources[sources$variable == v, , drop = FALSE]
          if (!nrow(row)) return(NULL)
          terra::rast(row$path)[[row$layer]]
        })
        if (any(vapply(pair, is.null, logical(1)))) next
        raster <- daily_explorer_mean_temperature(pair[[1L]], pair[[2L]])
      } else {
      source <- sources[sources$variable == variable, , drop = FALSE]
      if (!nrow(source)) next
      raster <- terra::rast(source$path)[[source$layer]]
      }
      terra::compareGeom(template, raster, stopOnError = TRUE)
      validate_prism_native_values(raster, variable)
      values <- terra::values(raster, mat = FALSE)
      reference <- if (variable == "tmean") {
        normals <- lapply(c("maxt", "mint"), function(v)
          daily_explorer_reference(daily_explorer_reference_path(v, "mean"), date, template))
        if (any(vapply(normals, is.null, logical(1)))) list() else
          list(mean = daily_explorer_mean_temperature(normals[[1L]], normals[[2L]]))
      } else if (variable == "pcpn") list() else stats::setNames(lapply(c("mean", "p10", "p90"), function(s) {
        daily_explorer_reference(daily_explorer_reference_path(variable, s), date, template)
      }), c("mean", "p10", "p90"))
      ref_values <- lapply(reference, function(x) if (is.null(x)) NULL else terra::values(x, mat = FALSE))
      for (region in names(masks)) record$regions[[region]][[variable]] <- daily_explorer_summary(
        values, masks[[region]], variable, ref_values$mean, ref_values$p10, ref_values$p90)
      views <- if (variable == "pcpn") "observed" else c("observed", "departure")
      for (view in views) {
        layer <- raster
        if (view == "departure") {
          if (is.null(reference$mean)) next
          layer <- raster - reference$mean
        }
        image <- paste0("maps/", date, "-", variable, "-", view, ".png")
        daily_explorer_plot(layer, variable, view, date, states,
          context$cities, file.path(output_dir, image), context = context)
        record$images[[paste(variable, view, sep = "_")]] <- image
      }
    }
    records[[date]] <- record
    saveRDS(list(signature = signature, record = record), cache_path)
    built <- built + 1L
  }
  assets <- file.path("scripts", "daily-explorer-assets")
  for (asset in c("index.html", "explorer.css", "explorer.js")) {
    if (!file.copy(file.path(assets, asset), file.path(output_dir, asset), overwrite = TRUE)) stop("Asset copy failed: ", asset)
  }
  payload <- list(schema_version = 1L, publication_mode = isTRUE(publication_mode),
    built_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    latest_cached_date = as.character(latest), baseline = "1991-2020", window_days = 5L,
    days = unname(records))
  json_path <- file.path(output_dir, "daily-data.json")
  # Keep unchanged payload bytes stable: a wall-clock build timestamp alone
  # must not force the entire daily publisher to upload again.
  serialized <- jsonlite::toJSON(payload, auto_unbox = TRUE,
    na = "null", null = "null", digits = 6, pretty = FALSE)
  previous <- if (file.exists(json_path)) tryCatch(jsonlite::read_json(json_path),
    error = function(e) NULL) else NULL
  current <- jsonlite::fromJSON(serialized, simplifyVector = FALSE)
  current$built_at <- previous$built_at <- NULL
  if (!identical(current, previous)) writeLines(serialized, json_path, useBytes = TRUE)
  message("Daily Explorer: ", built, " dates built; ", reused, " reused; no downloads or publication.")
  invisible(list(page = file.path(output_dir, "index.html"), built = built, reused = reused,
    start_date = first, end_date = last, days = length(records)))
}
