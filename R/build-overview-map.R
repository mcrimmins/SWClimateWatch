# Build the static coverage map shown on the homepage.

build_overview_map <- function(
    filename = file.path(swc_paths$maps, "southwest-overview.png")) {
  check_swc_packages()

  states <- ggplot2::map_data(
    map = "state",
    region = c("arizona", "new mexico")
  )

  labels <- data.frame(
    long = c(-111.9, -106.0),
    lat = c(34.2, 34.4),
    label = c("ARIZONA", "NEW MEXICO")
  )

  plot <- ggplot2::ggplot(
    states,
    ggplot2::aes(x = long, y = lat, group = group, fill = region)
  ) +
    ggplot2::geom_polygon(colour = "white", linewidth = 1.1) +
    ggplot2::geom_text(
      data = labels,
      ggplot2::aes(x = long, y = lat, label = label),
      inherit.aes = FALSE,
      colour = "white",
      fontface = "bold",
      size = 4.1
    ) +
    ggplot2::scale_fill_manual(
      values = c(arizona = "#c56a3d", `new mexico` = "#287c8e"),
      guide = "none"
    ) +
    ggplot2::coord_quickmap(expand = FALSE) +
    ggplot2::theme_void() +
    ggplot2::theme(plot.margin = ggplot2::margin(8, 8, 8, 8))

  dir.create(dirname(filename), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(
    filename = filename,
    plot = plot,
    width = 8,
    height = 5.2,
    dpi = 180,
    bg = "transparent"
  )

  invisible(filename)
}
