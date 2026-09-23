# Repaint retained freeze-season maps after a shared layout change. The current
# season may not be publishable, but its preceding completed-season grids remain
# available and should use the same layout as the other published maps.

retained_prism_freeze_map_specs <- function() {
  data.frame(
    id = c(
      "mint_first_freeze_date", "mint_first_freeze_departure",
      "mint_last_freeze_date", "mint_last_freeze_departure",
      "mint_freeze_free_length", "mint_freeze_free_departure"
    ),
    family = rep(c("first", "last", "freeze-free"), each = 2L),
    product = c("observed-day", "departure", "observed-day", "departure", "length", "departure"),
    stringsAsFactors = FALSE
  )
}

refresh_retained_prism_freeze_maps <- function(
    products = read_map_product_config(),
    maps_dir = swc_paths$maps,
    processed_dir = swc_paths$processed,
    aoi_id = swc_prism$aoi_id,
    logo_path = southwest_brand_logo_path(),
    expected_dimensions = c(width = 1998L, height = 1533L),
    quiet = FALSE) {
  specs <- retained_prism_freeze_map_specs()
  specs <- specs[specs$id %in% products$id[products$enabled], , drop = FALSE]
  if (nrow(specs) == 0L) return(invisible(specs))

  records <- list()
  boundaries <- NULL
  for (index in seq_len(nrow(specs))) {
    spec <- specs[index, , drop = FALSE]
    family <- spec$family[[1L]]
    product <- spec$product[[1L]]
    latest <- switch(
      family,
      first = prism_first_freeze_map_path(product, maps_dir = maps_dir),
      last = prism_last_freeze_map_path(product, maps_dir = maps_dir),
      `freeze-free` = prism_freeze_free_map_path(product, maps_dir = maps_dir)
    )
    image <- map_product_png_info(latest)
    if (!file.exists(latest)) next # Nothing from an earlier season to retain.
    if (!image$readable) stop("Retained map is not a readable PNG: ", latest, call. = FALSE)
    if (identical(
      c(image$width, image$height),
      unname(as.integer(expected_dimensions))
    )) next

    companion <- map_product_dated_companion(latest, image$md5)
    if (is.na(companion$date)) {
      stop("No matching dated image for retained map: ", latest, call. = FALSE)
    }
    date <- companion$date
    season_start <- prism_freeze_season_start(date)
    year <- as.integer(format(date, "%Y"))
    raster_path <- switch(
      family,
      first = prism_first_freeze_output_path(product, date, season_start, aoi_id, processed_dir),
      last = prism_last_freeze_output_path(product, date, season_start, aoi_id, processed_dir),
      `freeze-free` = prism_freeze_free_output_path(product, year, date, aoi_id, processed_dir)
    )
    if (!file.exists(raster_path)) {
      stop("Processed grid for retained map is missing: ", raster_path, call. = FALSE)
    }
    if (is.null(boundaries)) {
      boundaries <- list(
        states = southwest_state_boundaries(),
        counties = southwest_county_boundaries(),
        countries = southwest_country_boundaries(),
        cities = southwest_reference_cities()
      )
    }
    if (!quiet) message("Refreshing retained map layout: ", spec$id[[1L]], " (", date, ").")
    args <- c(list(raster = terra::rast(raster_path), product = product, date = date), boundaries)
    plot <- switch(
      family,
      first = do.call(build_prism_first_freeze_map, c(args, list(season_start = season_start))),
      last = do.call(build_prism_last_freeze_map, c(args, list(season_start = season_start))),
      `freeze-free` = do.call(build_prism_freeze_free_map, c(args, list(year = year)))
    )
    footer <- if (product %in% c("observed-day", "length")) {
      "Data source: PRISM Climate Group via RCC-ACIS"
    } else {
      prism_map_footer_text()
    }
    temporary <- tempfile("retained-map-", tmpdir = dirname(latest), fileext = ".png")
    save_southwest_map(plot, temporary, logo_path = logo_path, footer_text = footer)
    updated <- map_product_png_info(temporary)
    if (!updated$readable || !identical(
      c(updated$width, updated$height),
      unname(as.integer(expected_dimensions))
    )) {
      unlink(temporary)
      stop("Refreshed map has unexpected dimensions: ", temporary, call. = FALSE)
    }
    if (!file.copy(temporary, companion$path, overwrite = TRUE) ||
        !file.copy(temporary, latest, overwrite = TRUE)) {
      unlink(temporary)
      stop("Could not replace retained map: ", latest, call. = FALSE)
    }
    unlink(temporary)
    records[[length(records) + 1L]] <- data.frame(
      id = spec$id[[1L]], date = date, raster_path = raster_path,
      map_path = latest, stringsAsFactors = FALSE
    )
  }
  if (length(records) == 0L) {
    return(invisible(data.frame(
      id = character(), date = as.Date(character()), raster_path = character(),
      map_path = character(), stringsAsFactors = FALSE
    )))
  }
  invisible(do.call(rbind, records))
}
