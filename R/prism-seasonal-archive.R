# Historical cool-season and water-year summaries from processed daily PRISM.
# A water year is named for the calendar year in which it ends.

prism_archive_periods <- function(water_year) {
  water_year <- as.integer(water_year)
  if (length(water_year) != 1L || is.na(water_year) || water_year < 1982L) {
    stop("`water_year` must be one year from 1982 onward.", call. = FALSE)
  }
  list(
    cool_start = as.Date(sprintf("%04d-10-01", water_year - 1L)),
    cool_end = as.Date(sprintf("%04d-03-31", water_year)),
    water_start = as.Date(sprintf("%04d-10-01", water_year - 1L)),
    water_end = as.Date(sprintf("%04d-09-30", water_year))
  )
}

prism_archive_summary_from_daily <- function(
    precipitation,
    water_year,
    wet_day_threshold = swc_prism$wet_day_threshold_inches) {
  period <- prism_archive_periods(water_year)
  dates <- as.Date(terra::time(precipitation))
  expected <- seq(period$water_start, period$water_end, by = "day")
  if (terra::nlyr(precipitation) != length(expected) ||
      length(dates) != length(expected) || anyNA(dates) ||
      any(dates != expected)) {
    stop("Water-year precipitation must have every ordered daily layer.", call. = FALSE)
  }
  cool <- precipitation[[dates <= period$cool_end]]
  cool_total <- terra::app(cool, sum, na.rm = FALSE)
  cool_wet_count <- terra::app(
    prism_is_wet_day(cool, wet_day_threshold), sum, na.rm = FALSE
  )
  water_total <- terra::app(precipitation, sum, na.rm = FALSE)
  result <- c(cool_total, cool_wet_count, water_total)
  names(result) <- c("cool_total", "cool_wet_count", "water_total")
  terra::time(result) <- rep(period$water_end, 3L)
  result
}

prism_archive_summary_path <- function(
    water_year,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  file.path(
    processed_dir, "prism", aoi_id, "seasonal-archive", "reference",
    sprintf("wy%04d.tif", as.integer(water_year))
  )
}

prism_archive_summary_signature <- function(
    water_year,
    processed_manifest,
    aoi_id = swc_prism$aoi_id,
    wet_day_threshold = swc_prism$wet_day_threshold_inches) {
  period <- prism_archive_periods(water_year)
  rows <- processed_manifest[
    processed_manifest$product == "daily" &
      processed_manifest$aoi_id == aoi_id &
      processed_manifest$variable == "pcpn" &
      processed_manifest$start_date <= period$water_end &
      processed_manifest$end_date >= period$water_start,
    , drop = FALSE
  ]
  rows <- rows[order(rows$path), , drop = FALSE]
  digest::digest(
    list(
      water_year = water_year,
      wet_day_threshold = wet_day_threshold,
      paths = rows$path,
      md5 = rows$md5
    ),
    algo = "sha256"
  )
}

build_prism_archive_year_summary <- function(
    water_year,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    overwrite = FALSE,
    quiet = FALSE) {
  period <- prism_archive_periods(water_year)
  path <- prism_archive_summary_path(water_year, aoi_id, processed_dir)
  signature_path <- sub("\\.tif$", ".signature", path)
  signature <- prism_archive_summary_signature(water_year, processed_manifest, aoi_id)
  if (!overwrite && file.exists(path) && file.exists(signature_path) &&
      identical(readLines(signature_path, warn = FALSE), signature)) {
    summary <- terra::rast(path)
    if (terra::nlyr(summary) == 3L &&
        identical(names(summary), c("cool_total", "cool_wet_count", "water_total"))) {
      return(summary)
    }
  }
  if (!quiet) message("Summarizing water year ", water_year, " for archive reference.")
  dates <- seq(period$water_start, period$water_end, by = "day")
  precipitation <- read_prism_best_daily_range(
    "pcpn", dates, aoi_id, processed_manifest
  )$raster
  summary <- prism_archive_summary_from_daily(precipitation, water_year)
  write_prism_processed_raster(summary, path)
  writeLines(signature, signature_path, useBytes = TRUE)
  terra::rast(path)
}

build_prism_archive_reference <- function(
    reference_years = 1982:2025,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    overwrite = FALSE,
    quiet = FALSE) {
  reference_years <- sort(unique(as.integer(reference_years)))
  if (length(reference_years) < 2L || anyNA(reference_years) ||
      any(reference_years < 1982L)) {
    stop("`reference_years` must contain at least two valid water years.", call. = FALSE)
  }
  summaries <- lapply(seq_along(reference_years), function(index) {
    if (!quiet) message("Reference ", index, "/", length(reference_years), ".")
    build_prism_archive_year_summary(
      reference_years[[index]], processed_manifest, aoi_id, processed_dir,
      overwrite, quiet
    )
  })
  stack <- function(layer_name) {
    layers <- lapply(summaries, function(x) x[[layer_name]])
    result <- do.call(c, layers)
    names(result) <- paste0(layer_name, "_wy", reference_years)
    result
  }
  list(
    years = reference_years,
    cool_total = stack("cool_total"),
    cool_wet_count = stack("cool_wet_count"),
    water_total = stack("water_total")
  )
}

prism_archive_percentile_rank <- function(current, reference, name, date) {
  if (terra::nlyr(current) != 1L || terra::nlyr(reference) < 2L) {
    stop("Ranking requires one current layer and at least two reference years.", call. = FALSE)
  }
  terra::compareGeom(current, reference, stopOnError = TRUE)
  result <- terra::app(c(current, reference), function(values) {
    prism_type8_percentile_rank(values[[1L]], values[-1L])
  })
  names(result) <- name
  terra::time(result) <- as.Date(date)
  result
}

prism_archive_temperature_departure <- function(
    variable,
    water_year,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  if (!variable %in% c("maxt", "mint")) {
    stop("Seasonal temperature departure requires `maxt` or `mint`.", call. = FALSE)
  }
  period <- prism_archive_periods(water_year)
  dates <- seq(period$cool_start, period$cool_end, by = "day")
  observed <- read_prism_best_daily_range(
    variable, dates, aoi_id, processed_manifest
  )$raster
  normal <- prism_temperature_normal_raster(
    variable, dates, aoi_id = aoi_id, processed_dir = processed_dir
  )
  terra::compareGeom(observed, normal, stopOnError = TRUE)
  result <- terra::app(observed, mean, na.rm = FALSE) -
    terra::app(normal, mean, na.rm = FALSE)
  names(result) <- paste0(variable, "_cool_departure_wy", water_year)
  terra::time(result) <- period$cool_end
  result
}

calculate_prism_archive_year <- function(
    water_year,
    reference,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    overwrite = FALSE,
    quiet = FALSE) {
  water_year <- as.integer(water_year)
  if (!water_year %in% reference$years) {
    stop("The archive water year must be included in the fixed reference.", call. = FALSE)
  }
  period <- prism_archive_periods(water_year)
  index <- match(water_year, reference$years)
  cool_dates <- seq(period$cool_start, period$cool_end, by = "day")
  cool_daily <- read_prism_best_daily_range(
    "pcpn", cool_dates, aoi_id, processed_manifest
  )$raster
  intensity <- terra::app(
    cool_daily, prism_mean_wet_day_intensity,
    wet_day_threshold = swc_prism$wet_day_threshold_inches
  )
  names(intensity) <- paste0("cool_wet_day_intensity_wy", water_year)
  terra::time(intensity) <- period$cool_end
  products <- list(
    cool_total = reference$cool_total[[index]],
    cool_percentile = prism_archive_percentile_rank(
      reference$cool_total[[index]], reference$cool_total,
      paste0("cool_percentile_wy", water_year), period$cool_end
    ),
    maxt_departure = prism_archive_temperature_departure(
      "maxt", water_year, processed_manifest, aoi_id, processed_dir
    ),
    mint_departure = prism_archive_temperature_departure(
      "mint", water_year, processed_manifest, aoi_id, processed_dir
    ),
    wet_day_count_percentile = prism_archive_percentile_rank(
      reference$cool_wet_count[[index]], reference$cool_wet_count,
      paste0("wet_day_count_percentile_wy", water_year), period$cool_end
    ),
    wet_day_intensity = intensity,
    water_total = reference$water_total[[index]],
    water_percentile = prism_archive_percentile_rank(
      reference$water_total[[index]], reference$water_total,
      paste0("water_percentile_wy", water_year), period$water_end
    )
  )
  names(products$cool_total) <- paste0("cool_total_wy", water_year)
  names(products$water_total) <- paste0("water_total_wy", water_year)
  terra::time(products$cool_total) <- period$cool_end
  terra::time(products$water_total) <- period$water_end
  paths <- vapply(names(products), function(product) {
    file.path(
      processed_dir, "prism", aoi_id, "seasonal-archive",
      sprintf("wy%04d", water_year), paste0(product, ".tif")
    )
  }, character(1))
  for (product in names(products)) {
    if (file.exists(paths[[product]]) && !overwrite) next
    if (!quiet) message("Writing WY", water_year, " ", product, ".")
    write_prism_processed_raster(products[[product]], paths[[product]])
  }
  list(water_year = water_year, products = products, paths = paths)
}

prism_archive_product_specs <- function() {
  data.frame(
    id = c(
      "cool_total", "cool_percentile", "maxt_departure", "mint_departure",
      "wet_day_count_percentile", "wet_day_intensity",
      "water_total", "water_percentile"
    ),
    label = c(
      "Cool-season precipitation", "Cool-season precipitation rank",
      "Maximum-temperature departure", "Minimum-temperature departure",
      "Wet-day-count rank", "Precipitation per wet day",
      "Water-year precipitation", "Water-year precipitation rank"
    ),
    description = c(
      "Total inches received from October through March.",
      "Higher ranks indicate a wetter-than-usual cool season.",
      "Positive values indicate warmer-than-normal afternoons.",
      "Positive values indicate warmer-than-normal nights.",
      "Higher ranks mean wet days occurred more often.",
      "Average inches on days with at least 0.04 inch.",
      "Total inches received through September 30.",
      "Higher ranks indicate a wetter-than-usual full year."
    ),
    stringsAsFactors = FALSE
  )
}

prism_archive_map_path <- function(
    water_year,
    product,
    maps_dir = swc_paths$maps) {
  file.path(
    maps_dir, "prism", "seasonal-archive", sprintf("wy%04d", water_year),
    paste0(product, ".png")
  )
}

plot_prism_archive_map <- function(
    raster,
    product,
    water_year,
    reference_years = 1982:2025,
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities(),
    rivers = southwest_major_rivers()) {
  specs <- prism_archive_product_specs()
  index <- match(product, specs$id)
  if (is.na(index)) stop("Unknown seasonal archive product: ", product, call. = FALSE)
  period <- prism_archive_periods(water_year)
  is_water <- startsWith(product, "water_")
  is_rank <- grepl("percentile", product, fixed = TRUE)
  is_departure <- grepl("departure", product, fixed = TRUE)
  is_intensity <- identical(product, "wet_day_intensity")
  start <- if (is_water) period$water_start else period$cool_start
  end <- if (is_water) period$water_end else period$cool_end
  subtitle <- format_prism_map_period(start, end)
  if (is_rank) {
    subtitle <- paste0(
      subtitle, " | water years ", min(reference_years), "-", max(reference_years)
    )
    scale <- list(
      palette = c("#7f3b08", "#b35806", "#f1a340", "#f7f7f7", "#998ec3", "#542788", "#2d004b"),
      values = c(0, 10, 25, 50, 75, 90, 100),
      limits = c(0, 100),
      breaks = c(0, 10, 25, 50, 75, 90, 100),
      labels = c("0", "10", "25", "50", "75", "90", "100")
    )
    fill_label <- "Percentile rank"
  } else if (is_departure) {
    subtitle <- paste0(subtitle, " | relative to 1991-2020")
    scale <- list(
      palette = c("#313695", "#4575b4", "#abd9e9", "#f7f7f7", "#fdae61", "#d73027", "#7f0000"),
      values = c(-10, -5, -2, 0, 2, 5, 10),
      limits = c(-10, 10),
      breaks = c(-10, -5, 0, 5, 10),
      labels = c("-10", "-5", "0", "5", "10")
    )
    fill_label <- "Departure (degrees F)"
  } else if (is_intensity) {
    subtitle <- paste0(subtitle, " | wet days >=0.04 inch")
    scale <- list(
      palette = c("#d9f0ff", "#92c5de", "#4eb3d3", "#41ab5d", "#addd8e", "#fee08b", "#f46d43", "#9e0142"),
      values = c(0.04, 0.1, 0.2, 0.35, 0.5, 0.75, 1, 1.5),
      limits = c(0.04, 1.5),
      breaks = c(0.04, 0.25, 0.5, 0.75, 1, 1.5),
      labels = c("0.04", "0.25", "0.50", "0.75", "1.00", "1.50+")
    )
    fill_label <- "Inches per wet day"
  } else {
    scale <- prism_water_year_total_scale()
    fill_label <- "Precipitation (inches)"
  }
  southwest_raster_map(
    raster = raster,
    states = states,
    title = paste0(specs$label[[index]], " - WY", water_year),
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
    product_id = if (is_rank) "archive_percentile" else NULL,
    scale_type = if (is_rank) "categorical" else "continuous",
    mask_to_states = FALSE
  )
}

prism_archive_roni_category <- function(djf_roni) {
  if (!is.numeric(djf_roni) || length(djf_roni) != 1L ||
      is.na(djf_roni) || !is.finite(djf_roni)) {
    stop("djf_roni must be one finite numeric value.", call. = FALSE)
  }
  if (djf_roni >= 0.5) {
    return(list(label = "El Niño", class = "archive-roni-el-nino"))
  }
  if (djf_roni <= -0.5) {
    return(list(label = "La Niña", class = "archive-roni-la-nina"))
  }
  list(label = "Neutral", class = "archive-roni-neutral")
}

read_prism_archive_roni <- function(
    path = file.path("reference", "roni-djf-ersstv6-2026-09-23.csv")) {
  values <- utils::read.csv(path, stringsAsFactors = FALSE)
  if (!identical(names(values), c("water_year", "djf_roni")) ||
      anyNA(values) || anyDuplicated(values$water_year) ||
      !identical(as.integer(values$water_year), 1982:2025) ||
      !is.numeric(values$djf_roni) || any(!is.finite(values$djf_roni))) {
    stop("RONI snapshot must contain one finite DJF value for every WY1982-WY2025.",
         call. = FALSE)
  }
  values
}

write_prism_archive_page <- function(
    water_year,
    djf_roni,
    page_dir = file.path("site", "pages", "archive")) {
  specs <- prism_archive_product_specs()
  roni_category <- prism_archive_roni_category(djf_roni)
  page <- file.path(page_dir, sprintf("wy%04d.qmd", water_year))
  card <- function(index) {
    product <- specs$id[[index]]
    image <- paste0(
      "../../maps/generated/prism/seasonal-archive/wy", water_year,
      "/", product, ".png"
    )
    c(
      "::: {.dashboard-map-card}",
      paste0("![", specs$label[[index]], "](", image, ")"),
      "",
      "::: {.archive-map-description}",
      specs$description[[index]],
      ":::",
      "",
      "::: {.dashboard-card-actions}",
      paste0("[Open full-resolution PNG](", image, "){.btn .btn-sm .btn-outline-primary}"),
      ":::",
      ":::"
    )
  }
  lines <- c(
    "---",
    paste0('title: "Water year ', water_year, '"'),
    paste0('subtitle: "October 1, ', water_year - 1L, ' to September 30, ', water_year, '"'),
    "page-layout: full",
    "toc: false",
    "bread-crumbs: false",
    "body-classes: archive-year-page",
    "---",
    "",
    paste0("::: {.archive-year-intro .", roni_category$class, "}"),
    paste0("[", roni_category$label, " · RONI ", sprintf("%+.1f", djf_roni),
           " °C]{.archive-roni-badge}"),
    "",
    paste0("December-February ", water_year,
           " Relative Oceanic Niño Index: a three-month measure of tropical Pacific sea-surface temperature anomalies relative to the tropics. ",
           "[NOAA CPC data](https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso/roni/)."),
    ":::",
    "",
    "## Cool season",
    "",
    "::: {.dashboard-map-grid}"
  )
  for (index in 1:6) lines <- c(lines, card(index), "")
  lines <- c(lines, ":::", "", "## Full water year", "", "::: {.dashboard-map-grid}")
  for (index in 7:8) lines <- c(lines, card(index), "")
  lines <- c(
    lines,
    ":::",
    "",
    "Cool-season maps cover October 1-March 31. Precipitation ranks use water years 1982-2025; temperature departures use 1991-2020 normals. The full water year ends September 30 and includes months outside the cool season. These maps do not attribute local conditions solely to ENSO."
  )
  dir.create(page_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, page, useBytes = TRUE)
  page
}

write_prism_archive_pilot_page <- write_prism_archive_page

prism_archive_page_years <- function(page_dir = file.path("site", "pages", "archive")) {
  pages <- list.files(page_dir, pattern = "^wy[0-9]{4}\\.qmd$", full.names = FALSE)
  sort(as.integer(sub("^wy([0-9]{4})\\.qmd$", "\\1", pages)), decreasing = TRUE)
}

write_prism_archive_navigation <- function(
    page_dir = file.path("site", "pages", "archive"),
    config_path = file.path("site", "_quarto.yml")) {
  years <- prism_archive_page_years(page_dir)
  if (!length(years)) stop("No archive pages exist for the navigation.", call. = FALSE)
  lines <- readLines(config_path, warn = FALSE)
  begin <- match("      # BEGIN GENERATED HISTORIC YEARS", lines)
  end <- match("      # END GENERATED HISTORIC YEARS", lines)
  if (is.na(begin) || is.na(end) || end <= begin) {
    stop("Historic Years navigation markers are missing or out of order.", call. = FALSE)
  }
  navigation <- c("      - section: Historic Years", "        contents:")
  decades <- unique((years %/% 10L) * 10L)
  for (decade in decades) {
    navigation <- c(navigation, sprintf("          - section: %ds", decade),
                    "            contents:")
    for (year in years[years >= decade & years < decade + 10L]) {
      navigation <- c(
        navigation,
        sprintf("              - href: pages/archive/wy%04d.qmd", year),
        sprintf("                text: %d-%02d (WY%d)", year - 1L, year %% 100L, year)
      )
    }
  }
  updated <- c(lines[seq_len(begin)], navigation,
               lines[end:length(lines)])
  if (!identical(lines, updated)) writeLines(updated, config_path, useBytes = TRUE)
  invisible(years)
}

build_prism_archive_maps <- function(
    water_years,
    reference_years = 1982:2025,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path()),
    processed_dir = swc_paths$processed,
    maps_dir = swc_paths$maps,
    overwrite = FALSE,
    quiet = FALSE) {
  water_years <- sort(unique(as.integer(water_years)))
  reference_years <- sort(unique(as.integer(reference_years)))
  if (!length(water_years) || anyNA(water_years) ||
      any(!water_years %in% reference_years)) {
    stop("`water_years` must be nonempty years in the fixed reference.", call. = FALSE)
  }
  specs <- prism_archive_product_specs()
  records <- vector("list", length(water_years) * nrow(specs))
  index <- 0L
  reference <- NULL
  layers <- NULL
  for (water_year in water_years) {
    raster_paths <- setNames(file.path(
      processed_dir, "prism", swc_prism$aoi_id, "seasonal-archive",
      sprintf("wy%04d", water_year), paste0(specs$id, ".tif")
    ), specs$id)
    map_paths <- setNames(vapply(specs$id, function(product) {
      prism_archive_map_path(water_year, product, maps_dir)
    }, character(1)), specs$id)
    need_rasters <- overwrite || any(!file.exists(raster_paths))
    need_maps <- need_rasters || any(!file.exists(map_paths))
    if (!quiet) message("WY", water_year, ": ",
                        if (need_rasters) "calculating grids" else "grids current", "; ",
                        if (need_maps) "rendering missing maps" else "maps current", ".")
    if (need_rasters) {
      if (is.null(reference)) {
        reference <- build_prism_archive_reference(
          reference_years, processed_manifest, processed_dir = processed_dir,
          overwrite = overwrite, quiet = quiet
        )
      }
      result <- calculate_prism_archive_year(
        water_year, reference, processed_manifest, processed_dir = processed_dir,
        overwrite = overwrite, quiet = quiet
      )
      rasters <- result$products
    } else if (need_maps) {
      rasters <- lapply(raster_paths, terra::rast)
    } else {
      rasters <- NULL
    }
    if (need_maps && is.null(layers)) {
      layers <- list(
        states = southwest_state_boundaries(),
        counties = southwest_county_boundaries(),
        countries = southwest_country_boundaries(),
        cities = southwest_reference_cities(),
        rivers = southwest_major_rivers()
      )
    }
    for (product in specs$id) {
      path <- map_paths[[product]]
      map_refreshed <- need_rasters || !file.exists(path)
      if (map_refreshed) {
        plot <- plot_prism_archive_map(
          rasters[[product]], product, water_year, reference_years,
          layers$states, layers$counties, layers$countries,
          layers$cities, layers$rivers
        )
        footer <- paste0(
          "Data source: PRISM Climate Group via RCC-ACIS",
          if (grepl("percentile", product, fixed = TRUE)) {
            "\nRank reference: WY1982-WY2025"
          } else if (grepl("departure", product, fixed = TRUE)) {
            "\nReference period: 1991-2020"
          } else ""
        )
        save_southwest_map(
          plot, path, logo_path = southwest_brand_logo_path(),
          footer_text = footer
        )
      }
      index <- index + 1L
      records[[index]] <- data.frame(
        water_year = water_year, product = product,
        raster_path = raster_paths[[product]], map_path = path,
        map_refreshed = map_refreshed,
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, records)
}

build_prism_archive_pilot_maps <- function(
    water_years = c(1998L, 2011L), ...) {
  build_prism_archive_maps(water_years, ...)
}

build_prism_archive_years <- function(
    water_years,
    roni = read_prism_archive_roni(),
    page_dir = file.path("site", "pages", "archive"),
    config_path = file.path("site", "_quarto.yml"),
    overwrite = FALSE,
    ...) {
  water_years <- sort(unique(as.integer(water_years)))
  if (!length(water_years) || anyNA(water_years) ||
      any(!water_years %in% roni$water_year)) {
    stop("Every requested archive year needs a RONI snapshot value.", call. = FALSE)
  }
  records <- build_prism_archive_maps(
    water_years, overwrite = overwrite, ...
  )
  for (water_year in water_years) {
    page <- file.path(page_dir, sprintf("wy%04d.qmd", water_year))
    if (overwrite || !file.exists(page)) {
      write_prism_archive_page(
        water_year, roni$djf_roni[match(water_year, roni$water_year)], page_dir
      )
    }
  }
  write_prism_archive_navigation(page_dir, config_path)
  records
}
