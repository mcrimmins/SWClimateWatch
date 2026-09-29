# Reusable map utilities for Arizona and New Mexico climate grids.

southwest_context_states <- c(
  "arizona", "california", "colorado", "nevada", "new mexico", "texas", "utah"
)

#' Build a Southwest raster map
#'
#' @param raster A single-layer terra SpatRaster.
#' @param states An sf object containing state boundaries.
#' @param title,subtitle,caption Plot annotations.
#' @param fill_label Legend title.
#' @param palette Vector of colours used for a continuous scale.
#' @param palette_values Optional data values corresponding to `palette`.
#' @param limits Optional numeric vector with minimum and maximum scale values.
#' @param breaks,labels Optional legend breaks and labels.
#' @param counties Optional sf object containing county boundaries.
#' @param countries Optional sf object containing national boundaries.
#' @param tribal_areas Optional sf object containing tribal-area boundaries.
#' @param rivers Optional sf object containing selected major rivers.
#' @param interstates Optional sf object containing selected interstate highways.
#' @param cities Optional data frame with `city`, `longitude`, and `latitude`.
#' @param city_label_fill_alpha Opacity of the white background behind city labels.
#' @param tucson_label_southwest Place Tucson's label southwest of its marker
#'   instead of letting the label-repelling algorithm place it.
#' @param mask_to_states Whether to mask the raster to the supplied state polygons.
#' @param county_colour,county_linewidth,county_alpha,county_linetype County
#'   boundary styling.
#' @param tribal_colour,tribal_linewidth,tribal_alpha,tribal_linetype Tribal-area
#'   boundary styling.
#' @param state_colour,state_linewidth,state_alpha,state_linetype State boundary
#'   styling.
#' @param product_id Stable ID from `config/map-products.yml`.
#' @param scale_type Optional `continuous` or `categorical` override. When NULL,
#'   the product catalog controls the display mode.
#' @return A ggplot object.
southwest_raster_map <- function(
    raster,
    states,
    title,
    subtitle = NULL,
    caption = "Data: PRISM Climate Group",
    fill_label = NULL,
    palette = c("#6e3b87", "#3f77b5", "#74add1", "#f7f7f7", "#fdae61", "#d73027"),
    palette_values = NULL,
    limits = NULL,
    breaks = NULL,
    labels = NULL,
    counties = NULL,
    countries = NULL,
    tribal_areas = if (isTRUE(getOption("swc.map.tribal", TRUE))) {
      southwest_tribal_boundaries()
    } else NULL,
    rivers = if (isTRUE(getOption("swc.map.rivers", FALSE))) {
      southwest_major_rivers()
    } else NULL,
    interstates = if (isTRUE(getOption("swc.map.interstates", FALSE))) {
      southwest_interstates()
    } else NULL,
    cities = NULL,
    city_label_fill_alpha = 0.60,
    tucson_label_southwest = TRUE,
    mask_to_states = FALSE,
    county_colour = "#3f474c",
    county_linewidth = 0.28,
    county_alpha = 0.78,
    county_linetype = "solid",
    tribal_colour = "#aeb4b8",
    tribal_linewidth = 0.18,
    tribal_alpha = 0.9,
    tribal_linetype = "solid",
    state_colour = "#000000",
    state_linewidth = 0.82,
    state_alpha = 1,
    state_linetype = "solid",
    product_id = NULL,
    scale_type = NULL) {
  check_swc_packages()

  if (!inherits(raster, "SpatRaster") || terra::nlyr(raster) != 1L) {
    stop("`raster` must be a single-layer terra SpatRaster.", call. = FALSE)
  }
  if (!inherits(states, "sf")) {
    stop("`states` must be an sf object.", call. = FALSE)
  }
  if (!is.null(counties) && !inherits(counties, "sf")) {
    stop("`counties` must be NULL or an sf object.", call. = FALSE)
  }
  if (!is.null(countries) && !inherits(countries, "sf")) {
    stop("`countries` must be NULL or an sf object.", call. = FALSE)
  }
  if (!is.null(tribal_areas) && !inherits(tribal_areas, "sf")) {
    stop("`tribal_areas` must be NULL or an sf object.", call. = FALSE)
  }
  if (!is.null(rivers) && !inherits(rivers, "sf")) {
    stop("`rivers` must be NULL or an sf object.", call. = FALSE)
  }
  if (!is.null(interstates) && !inherits(interstates, "sf")) {
    stop("`interstates` must be NULL or an sf object.", call. = FALSE)
  }
  if (!is.null(cities)) {
    required_city_columns <- c("city", "longitude", "latitude")
    missing_city_columns <- setdiff(required_city_columns, names(cities))
    if (length(missing_city_columns) > 0L) {
      stop(
        "`cities` is missing column(s): ",
        paste(missing_city_columns, collapse = ", "),
        call. = FALSE
      )
    }
  }
  if (!is.numeric(city_label_fill_alpha) ||
      length(city_label_fill_alpha) != 1L ||
      !is.finite(city_label_fill_alpha) ||
      city_label_fill_alpha < 0 || city_label_fill_alpha > 1) {
    stop("`city_label_fill_alpha` must be between 0 and 1.", call. = FALSE)
  }
  if (!is.logical(tucson_label_southwest) ||
      length(tucson_label_southwest) != 1L || is.na(tucson_label_southwest)) {
    stop("`tucson_label_southwest` must be TRUE or FALSE.", call. = FALSE)
  }

  map_crs <- terra::crs(raster, proj = TRUE)
  if (is.na(map_crs) || !nzchar(map_crs)) {
    stop("`raster` must have a coordinate reference system.", call. = FALSE)
  }

  states_map <- sf::st_transform(states, crs = map_crs)
  counties_map <- if (is.null(counties)) NULL else sf::st_transform(counties, crs = map_crs)
  countries_map <- if (is.null(countries)) NULL else sf::st_transform(countries, crs = map_crs)
  tribal_map <- if (is.null(tribal_areas)) NULL else sf::st_transform(tribal_areas, crs = map_crs)
  rivers_map <- if (is.null(rivers)) NULL else sf::st_transform(rivers, crs = map_crs)
  interstates_map <- if (is.null(interstates)) NULL else sf::st_transform(interstates, crs = map_crs)
  raster_region <- if (isTRUE(mask_to_states)) {
    terra::mask(
      terra::crop(raster, terra::vect(states_map)),
      terra::vect(states_map)
    )
  } else {
    raster
  }

  raster_extent <- terra::ext(raster_region)
  x_limits <- c(raster_extent$xmin, raster_extent$xmax)
  y_limits <- c(raster_extent$ymin, raster_extent$ymax)

  raster_df <- terra::as.data.frame(raster_region, xy = TRUE, na.rm = TRUE)
  names(raster_df)[3L] <- "value"
  if (is.null(scale_type)) {
    scale_type <- if (exists("configured_map_product_scale", mode = "function")) {
      configured_map_product_scale(product_id)
    } else {
      "continuous"
    }
  }
  scale_type <- match.arg(scale_type, c("continuous", "categorical"))
  if (!is.null(palette_values)) {
    if (is.null(limits) || length(palette_values) != length(palette)) {
      stop("`palette_values` requires `limits` and one value per palette colour.", call. = FALSE)
    }
    palette_values <- (palette_values - limits[[1L]]) / diff(limits)
  }

  if (scale_type == "categorical") {
    if (!exists("map_product_categorical_classes", mode = "function")) {
      stop(
        "Categorical maps require `R/map-product-scales.R` to be sourced.",
        call. = FALSE
      )
    }
    classes <- map_product_categorical_classes(product_id, breaks, limits)
    raster_df$value <- scales::squish(raster_df$value, range = limits)
    raster_df$category <- cut(
      raster_df$value,
      breaks = classes$breaks,
      labels = classes$labels,
      include.lowest = TRUE,
      right = TRUE
    )
    plot <- ggplot2::ggplot() +
      ggplot2::geom_raster(
        data = raster_df,
        ggplot2::aes(x = x, y = y, fill = category),
        show.legend = TRUE
      )
  } else {
    plot <- ggplot2::ggplot() +
      ggplot2::geom_raster(
        data = raster_df,
        ggplot2::aes(x = x, y = y, fill = value)
      )
  }

  if (!is.null(rivers_map) && nrow(rivers_map) > 0L) {
    plot <- plot + ggplot2::geom_sf(
      data = rivers_map,
      colour = "#2d789d",
      linewidth = 0.4,
      alpha = 0.64,
      inherit.aes = FALSE
    )
  }

  if (!is.null(interstates_map) && nrow(interstates_map) > 0L) {
    plot <- plot +
      ggplot2::geom_sf(
        data = interstates_map,
        colour = "#fffdf5",
        linewidth = 1.0,
        alpha = 0.68,
        inherit.aes = FALSE
      ) +
      ggplot2::geom_sf(
        data = interstates_map,
        colour = "#6b4f3f",
        linewidth = 0.32,
        alpha = 0.76,
        inherit.aes = FALSE
      )
  }

  if (!is.null(counties_map) && nrow(counties_map) > 0L) {
    plot <- plot + ggplot2::geom_sf(
      data = counties_map,
      fill = NA,
      colour = county_colour,
      linewidth = county_linewidth,
      alpha = county_alpha,
      linetype = county_linetype,
      inherit.aes = FALSE
    )
  }

  if (!is.null(tribal_map) && nrow(tribal_map) > 0L) {
    plot <- plot + ggplot2::geom_sf(
      data = tribal_map,
      fill = NA,
      colour = tribal_colour,
      linewidth = tribal_linewidth,
      alpha = tribal_alpha,
      linetype = tribal_linetype,
      inherit.aes = FALSE
    )
  }

  plot <- plot +
    ggplot2::geom_sf(
      data = states_map,
      fill = NA,
      colour = state_colour,
      linewidth = state_linewidth,
      alpha = state_alpha,
      linetype = state_linetype,
      inherit.aes = FALSE
    )

  if (!is.null(countries_map) && nrow(countries_map) > 0L) {
    plot <- plot + ggplot2::geom_sf(
      data = countries_map,
      fill = NA,
      colour = "#101820",
      linewidth = 0.8,
      inherit.aes = FALSE
    )
  }

  if (!is.null(cities) && nrow(cities) > 0L) {
    city_points <- sf::st_as_sf(
      cities,
      coords = c("longitude", "latitude"),
      crs = 4326,
      remove = FALSE
    )
    city_points <- sf::st_transform(city_points, crs = map_crs)
    city_xy <- sf::st_coordinates(city_points)
    cities$x <- city_xy[, 1L]
    cities$y <- city_xy[, 2L]
    cities <- cities[
      cities$x >= x_limits[[1L]] & cities$x <= x_limits[[2L]] &
        cities$y >= y_limits[[1L]] & cities$y <= y_limits[[2L]],
      , drop = FALSE
    ]
    if (nrow(cities) > 0L) {
      plot <- plot + ggplot2::geom_point(
          data = cities,
          ggplot2::aes(x = x, y = y),
          colour = "#101820",
          fill = "white",
          shape = 21,
          size = 1.8,
          stroke = 0.55,
          inherit.aes = FALSE
        )
      tucson <- if (tucson_label_southwest) {
        cities[cities$city == "Tucson", , drop = FALSE]
      } else cities[FALSE, , drop = FALSE]
      repel_cities <- if (nrow(tucson) == 1L) {
        cities[cities$city != "Tucson", , drop = FALSE]
      } else cities
      if (nrow(repel_cities) > 0L) plot <- plot + ggrepel::geom_label_repel(
          data = repel_cities,
          ggplot2::aes(x = x, y = y, label = city),
          seed = 314,
          size = 3.05,
          fontface = "bold",
          colour = "#101820",
          fill = scales::alpha("white", city_label_fill_alpha),
          label.size = 0,
          label.padding = grid::unit(0.09, "lines"),
          box.padding = grid::unit(0.18, "lines"),
          point.padding = grid::unit(0.14, "lines"),
          min.segment.length = 0,
          segment.colour = scales::alpha("#101820", 0.6),
          segment.size = 0.3,
          max.overlaps = Inf,
          inherit.aes = FALSE
        )
      if (nrow(tucson) == 1L) {
        label_point <- sf::st_as_sf(
          data.frame(longitude = -111.23, latitude = 32.08),
          coords = c("longitude", "latitude"), crs = 4326
        )
        label_xy <- sf::st_coordinates(sf::st_transform(label_point, crs = map_crs))
        tucson$label_x <- label_xy[1L, 1L]
        tucson$label_y <- label_xy[1L, 2L]
        plot <- plot +
          ggplot2::geom_segment(
            data = tucson,
            ggplot2::aes(x = label_x, y = label_y, xend = x, yend = y),
            colour = "#4c5961", linewidth = 0.28, inherit.aes = FALSE
          ) +
          ggplot2::geom_label(
            data = tucson,
            ggplot2::aes(x = label_x, y = label_y, label = city),
            size = 3.05, fontface = "bold", colour = "#101820",
            fill = scales::alpha("white", city_label_fill_alpha),
            linewidth = 0, label.padding = grid::unit(0.09, "lines"),
            inherit.aes = FALSE
          )
      }
    }
  }

  fill_scale <- if (scale_type == "categorical") {
    class_midpoints <- (head(classes$breaks, -1L) + tail(classes$breaks, -1L)) / 2
    scaled_midpoints <- (class_midpoints - limits[[1L]]) / diff(limits)
    class_colours <- scales::gradient_n_pal(
      colours = palette,
      values = palette_values
    )(scaled_midpoints)
    ggplot2::scale_fill_manual(
      values = stats::setNames(class_colours, classes$labels),
      limits = classes$labels,
      breaks = classes$labels,
      name = fill_label,
      drop = FALSE,
      na.value = "transparent"
    )
  } else {
    ggplot2::scale_fill_gradientn(
      colours = palette,
      values = palette_values,
      limits = limits,
      breaks = breaks,
      labels = labels,
      name = fill_label,
      na.value = "transparent",
      oob = scales::squish
    )
  }
  fill_guide <- if (scale_type == "categorical") {
    ggplot2::guide_legend(
      title.position = "top",
      title.hjust = 0.5,
      direction = "horizontal",
      nrow = 1,
      byrow = TRUE,
      label.position = "bottom",
      label.hjust = 0.5,
      keywidth = grid::unit(1.5, "cm"),
      keyheight = grid::unit(0.42, "cm")
    )
  } else {
    ggplot2::guide_colourbar(
      title.position = "top",
      title.hjust = 0.5,
      barwidth = grid::unit(7, "cm"),
      barheight = grid::unit(0.42, "cm"),
      ticks.colour = "#263238",
      frame.colour = "#667078"
    )
  }

  plot +
    fill_scale +
    ggplot2::guides(
      fill = fill_guide
    ) +
    ggplot2::coord_sf(
      crs = sf::st_crs(states_map),
      xlim = x_limits,
      ylim = y_limits,
      datum = NA,
      expand = FALSE
    ) +
    ggplot2::labs(
      title = title,
      subtitle = subtitle,
      caption = caption,
      x = NULL,
      y = NULL
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      panel.background = ggplot2::element_rect(fill = "#ebe8e1", colour = NA),
      panel.border = ggplot2::element_rect(fill = NA, colour = "#69747c", linewidth = 0.35),
      plot.title = ggplot2::element_text(face = "bold", size = 18, colour = "#18242d"),
      plot.subtitle = ggplot2::element_text(size = 11.5, colour = "#4c5961"),
      plot.caption = ggplot2::element_text(size = 8.5, colour = "#5d676e", hjust = 0),
      plot.caption.position = "plot",
      legend.position = "bottom",
      legend.title = ggplot2::element_text(face = "bold", size = 10),
      legend.text = ggplot2::element_text(size = 9),
      plot.margin = ggplot2::margin(6, 8, 6, 6)
    )
}

#' Configure optional reference layers for subsequent Southwest maps
#'
#' Tribal boundaries are on by default. Rivers are enabled explicitly by the
#' precipitation-map builders. Interstates remain opt-in for specialty maps.
configure_southwest_map_context <- function(
    tribal = TRUE,
    rivers = FALSE,
    interstates = FALSE) {
  options(
    swc.map.tribal = isTRUE(tribal),
    swc.map.rivers = isTRUE(rivers),
    swc.map.interstates = isTRUE(interstates)
  )
  invisible(list(
    tribal = isTRUE(tribal),
    rivers = isTRUE(rivers),
    interstates = isTRUE(interstates)
  ))
}

validate_southwest_map_products <- function(products, supported, allow_empty = FALSE) {
  products <- unique(as.character(products))
  supported <- as.character(supported)
  if (length(products) == 0L && isTRUE(allow_empty)) {
    return(products)
  }
  if (length(products) == 0L || anyNA(products) || any(!nzchar(products))) {
    stop("At least one map product is required.", call. = FALSE)
  }
  unsupported <- setdiff(products, supported)
  if (length(unsupported) > 0L) {
    stop(
      "Unsupported map product(s): ", paste(unsupported, collapse = ", "),
      ". Supported products are: ", paste(supported, collapse = ", "),
      call. = FALSE
    )
  }
  products
}

#' State boundaries surrounding the Arizona-New Mexico data footprint
#'
#' @param regions Lowercase state names accepted by the `maps` package.
#' @return An sf polygon object in EPSG:4326.
southwest_state_boundaries <- function(regions = southwest_context_states) {
  boundaries <- sf::st_as_sf(
    maps::map(
      "state",
      regions = regions,
      fill = TRUE,
      plot = FALSE
    )
  )
  if (is.na(sf::st_crs(boundaries))) {
    sf::st_crs(boundaries) <- 4326
  }
  boundaries
}

#' County boundaries surrounding the Arizona-New Mexico data footprint
#'
#' @param regions Lowercase state names accepted by the `maps` package.
#' @return An sf polygon object in EPSG:4326.
southwest_county_boundaries <- function(regions = southwest_context_states) {
  boundaries <- sf::st_as_sf(
    maps::map(
      "county",
      regions = regions,
      fill = TRUE,
      plot = FALSE
    )
  )
  if (is.na(sf::st_crs(boundaries))) {
    sf::st_crs(boundaries) <- 4326
  }
  boundaries
}

#' U.S.-Mexico boundary around the Southwest map footprint
#'
#' @return An sf polygon object in EPSG:4326.
southwest_country_boundaries <- function() {
  boundaries <- sf::st_as_sf(
    maps::map(
      "world",
      regions = c("USA", "Mexico"),
      fill = TRUE,
      plot = FALSE
    )
  )
  if (is.na(sf::st_crs(boundaries))) {
    sf::st_crs(boundaries) <- 4326
  }
  boundaries
}

#' Curated cities used as stable Southwest reference labels
#'
#' @param max_priority Maximum label priority to include. Lower values are more
#'   important; the default balances reference value and visual density.
#' @return A data frame with city names and WGS84 coordinates.
southwest_reference_cities <- function(max_priority = 2L) {
  cities <- data.frame(
    city = c(
      "Phoenix", "Tucson", "Flagstaff", "Prescott", "Yuma", "Kingman",
      "Show Low", "Sierra Vista", "Safford", "Douglas", "Kayenta",
      "Albuquerque", "Santa Fe", "Las Cruces", "Farmington", "Gallup",
      "Roswell", "Clovis", "Carlsbad", "Socorro", "Silver City", "Raton",
      "Tucumcari"
    ),
    longitude = c(
      -112.0740, -110.9747, -111.6513, -112.4685, -114.6244, -114.0530,
      -110.0298, -110.3037, -109.7076, -109.5453, -110.2546,
      -106.6504, -105.9378, -106.7637, -108.2187, -108.7426,
      -104.5230, -103.2052, -104.2288, -106.8914, -108.2803, -104.4430,
      -103.7250
    ),
    latitude = c(
      33.4484, 32.2226, 35.1983, 34.5400, 32.6927, 35.1894,
      34.2542, 31.5455, 32.8340, 31.3445, 36.7278,
      35.0844, 35.6870, 32.3199, 36.7281, 35.5281,
      33.3943, 34.4048, 32.4207, 34.0584, 32.7701, 36.9034,
      35.1717
    ),
    priority = c(
      1L, 1L, 1L, 2L, 2L, 2L,
      2L, 2L, 3L, 3L, 3L,
      1L, 1L, 1L, 2L, 2L,
      2L, 2L, 2L, 2L, 2L, 3L,
      3L
    ),
    stringsAsFactors = FALSE
  )
  cities[cities$priority <= as.integer(max_priority), , drop = FALSE]
}

#' Save a map consistently for use by Quarto
#'
#' @param plot A ggplot object.
#' @param filename Destination PNG path.
#' @param width,height,dpi Output dimensions and resolution.
#' @param logo_path Optional horizontal branding PNG appended below the map.
#' @param logo_width_fraction Width of the logo relative to the map image.
#' @param footer_text Optional right-aligned footer text.
#' @param footer_inset_fraction Horizontal footer inset relative to image width.
save_southwest_map <- function(
    plot,
    filename,
    width = 11.1,
    height = 8.05,
    dpi = 180,
    logo_path = NULL,
    logo_width_fraction = 0.23,
    footer_text = NULL,
    footer_inset_fraction = 0.05) {
  dir.create(dirname(filename), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(
    filename = filename,
    plot = plot,
    width = width,
    height = height,
    dpi = dpi,
    bg = "white"
  )
  if (!is.null(logo_path)) {
    append_southwest_map_branding(
      filename,
      logo_path = logo_path,
      logo_width_fraction = logo_width_fraction,
      footer_text = footer_text,
      footer_inset_fraction = footer_inset_fraction
    )
  }
  invisible(filename)
}

#' Path to the institutional logo used on downloadable maps
#'
#' @return A project-relative PNG path.
southwest_brand_logo_path <- function() {
  file.path(
    "site", "assets", "branding",
    "ua-csap-climas-logos-horizontal.png"
  )
}

#' Append a compact institutional-branding footer to a saved map
#'
#' @param filename Existing map image to update in place.
#' @param logo_path Horizontal transparent PNG.
#' @param logo_width_fraction Width of the logo relative to the map image.
#' @param footer_text Optional two-line attribution text.
#' @param footer_inset_fraction Horizontal footer inset relative to image width.
#' @return The updated filename invisibly.
append_southwest_map_branding <- function(
    filename,
    logo_path = southwest_brand_logo_path(),
    logo_width_fraction = 0.23,
    footer_text = NULL,
    footer_inset_fraction = 0.05) {
  if (!file.exists(filename)) {
    stop("Map image does not exist: ", filename, call. = FALSE)
  }
  if (!file.exists(logo_path)) {
    stop("Brand logo does not exist: ", logo_path, call. = FALSE)
  }
  if (
    length(logo_width_fraction) != 1L || !is.finite(logo_width_fraction) ||
      logo_width_fraction <= 0 || logo_width_fraction >= 1
  ) {
    stop("`logo_width_fraction` must be a number between 0 and 1.", call. = FALSE)
  }
  if (
    length(footer_inset_fraction) != 1L || !is.finite(footer_inset_fraction) ||
      footer_inset_fraction < 0 || footer_inset_fraction >= 0.5
  ) {
    stop("`footer_inset_fraction` must be a number from 0 to less than 0.5.", call. = FALSE)
  }
  if (!is.null(footer_text) && (length(footer_text) != 1L || is.na(footer_text))) {
    stop("`footer_text` must be NULL or one non-missing character value.", call. = FALSE)
  }

  map_image <- magick::image_read(filename)
  map_info <- magick::image_info(map_image)[1L, ]
  logo <- magick::image_trim(magick::image_read(logo_path))
  logo <- magick::image_resize(
    logo,
    paste0(round(map_info$width * logo_width_fraction), "x")
  )
  logo_info <- magick::image_info(logo)[1L, ]
  footer_height <- max(
    round(logo_info$height * 1.12),
    round(map_info$height * 0.048)
  )
  footer <- magick::image_blank(
    width = map_info$width,
    height = footer_height,
    color = "white"
  )
  x_offset <- round(map_info$width * footer_inset_fraction)
  y_offset <- max(0L, floor((footer_height - logo_info$height) / 2))
  footer <- magick::image_composite(
    footer,
    logo,
    operator = "over",
    offset = sprintf("+%d+%d", x_offset, y_offset)
  )
  if (!is.null(footer_text) && nzchar(footer_text)) {
    footer <- magick::image_annotate(
      footer,
      text = footer_text,
      gravity = "east",
      location = sprintf("+%d+0", x_offset),
      size = max(18L, round(map_info$width * 0.0115)),
      color = "#46535c",
      weight = 400
    )
  }
  branded <- magick::image_append(c(map_image, footer), stack = TRUE)
  magick::image_write(branded, path = filename, format = "png")
  invisible(filename)
}
