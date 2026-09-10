# Reusable map utilities for Arizona and New Mexico climate grids.

#' Build a Southwest raster map
#'
#' @param raster A single-layer terra SpatRaster.
#' @param states An sf object containing Arizona and New Mexico boundaries.
#' @param title,subtitle,caption Plot annotations.
#' @param fill_label Legend title.
#' @param palette Vector of colours used for a continuous scale.
#' @param limits Optional numeric vector with minimum and maximum scale values.
#' @return A ggplot object.
southwest_raster_map <- function(
    raster,
    states,
    title,
    subtitle = NULL,
    caption = "Data: PRISM Climate Group",
    fill_label = NULL,
    palette = c("#6e3b87", "#3f77b5", "#74add1", "#f7f7f7", "#fdae61", "#d73027"),
    limits = NULL) {
  check_swc_packages()

  if (!inherits(raster, "SpatRaster") || terra::nlyr(raster) != 1L) {
    stop("`raster` must be a single-layer terra SpatRaster.", call. = FALSE)
  }
  if (!inherits(states, "sf")) {
    stop("`states` must be an sf object.", call. = FALSE)
  }

  map_crs <- terra::crs(raster, proj = TRUE)
  if (is.na(map_crs) || !nzchar(map_crs)) {
    stop("`raster` must have a coordinate reference system.", call. = FALSE)
  }

  states_map <- sf::st_transform(states, crs = map_crs)
  raster_region <- terra::mask(
    terra::crop(raster, terra::vect(states_map)),
    terra::vect(states_map)
  )

  raster_df <- terra::as.data.frame(raster_region, xy = TRUE, na.rm = TRUE)
  names(raster_df)[3L] <- "value"

  ggplot2::ggplot() +
    ggplot2::geom_raster(
      data = raster_df,
      ggplot2::aes(x = x, y = y, fill = value)
    ) +
    ggplot2::geom_sf(
      data = states_map,
      fill = NA,
      colour = "#303030",
      linewidth = 0.45,
      inherit.aes = FALSE
    ) +
    ggplot2::scale_fill_gradientn(
      colours = palette,
      limits = limits,
      name = fill_label,
      na.value = "transparent"
    ) +
    ggplot2::coord_sf(crs = sf::st_crs(states_map), datum = NA, expand = FALSE) +
    ggplot2::labs(title = title, subtitle = subtitle, caption = caption) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(face = "bold"),
      legend.position = "bottom",
      legend.key.width = grid::unit(2.5, "cm")
    )
}

#' Save a map consistently for use by Quarto
save_southwest_map <- function(plot, filename, width = 9, height = 6, dpi = 180) {
  dir.create(dirname(filename), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(
    filename = filename,
    plot = plot,
    width = width,
    height = height,
    dpi = dpi,
    bg = "white"
  )
  invisible(filename)
}
