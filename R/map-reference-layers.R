# Download, cache, and read optional geographic context for Southwest maps.

southwest_reference_directory <- function() {
  file.path("reference", "map-layers")
}

southwest_reference_layer_path <- function(
    layer = c("tribal", "rivers", "interstates"),
    reference_dir = southwest_reference_directory()) {
  layer <- match.arg(layer)
  filename <- switch(
    layer,
    tribal = "tribal-areas-census-2025.gpkg",
    rivers = "major-rivers-natural-earth-10m.gpkg",
    interstates = "interstates-census-2025.gpkg"
  )
  file.path(reference_dir, filename)
}

southwest_reference_bbox <- function(padding = 0.25) {
  bbox <- swc_region$bbox
  sf::st_bbox(
    c(
      xmin = unname(bbox[["west"]]) - padding,
      ymin = unname(bbox[["south"]]) - padding,
      xmax = unname(bbox[["east"]]) + padding,
      ymax = unname(bbox[["north"]]) + padding
    ),
    crs = sf::st_crs(4326)
  )
}

.southwest_reference_cache <- new.env(parent = emptyenv())

read_southwest_reference_layer <- function(
    layer = c("tribal", "rivers", "interstates"),
    path = southwest_reference_layer_path(match.arg(layer)),
    required = FALSE) {
  layer <- match.arg(layer)
  if (!file.exists(path)) {
    if (isTRUE(required)) {
      stop(
        "Southwest ", layer, " reference layer is missing: ", path,
        ". Run `build_southwest_reference_layers()` once.",
        call. = FALSE
      )
    }
    return(NULL)
  }
  key <- paste(normalizePath(path, mustWork = TRUE), file.info(path)$mtime, sep = "|")
  if (exists(key, envir = .southwest_reference_cache, inherits = FALSE)) {
    return(get(key, envir = .southwest_reference_cache, inherits = FALSE))
  }
  result <- sf::st_read(path, quiet = TRUE)
  assign(key, result, envir = .southwest_reference_cache)
  result
}

southwest_tribal_boundaries <- function(required = FALSE) {
  read_southwest_reference_layer("tribal", required = required)
}

southwest_major_rivers <- function(required = FALSE) {
  read_southwest_reference_layer("rivers", required = required)
}

southwest_interstates <- function(required = FALSE) {
  read_southwest_reference_layer("interstates", required = required)
}

#' Generalize tribal-area polygons for regional static maps
#'
#' The largest polygon component for every named entity is always retained.
#' Additional detached components are retained only when they meet the area
#' threshold. This preserves representation of small tribal entities while
#' removing parcel-scale detail that obscures regional climate grids.
generalize_southwest_tribal_boundaries <- function(
    tribal_areas,
    minimum_component_km2 = 25,
    area_crs = 5070) {
  if (!inherits(tribal_areas, "sf")) {
    stop("`tribal_areas` must be an sf object.", call. = FALSE)
  }
  if (
    length(minimum_component_km2) != 1L ||
      !is.finite(minimum_component_km2) || minimum_component_km2 < 0
  ) {
    stop("`minimum_component_km2` must be one non-negative number.", call. = FALSE)
  }
  entity_field <- if ("GEOID" %in% names(tribal_areas)) {
    "GEOID"
  } else if ("NAME" %in% names(tribal_areas)) {
    "NAME"
  } else {
    stop("`tribal_areas` must contain `GEOID` or `NAME`.", call. = FALSE)
  }

  parts <- suppressWarnings(
    sf::st_cast(sf::st_make_valid(tribal_areas), "POLYGON")
  )
  component_km2 <- as.numeric(
    sf::st_area(sf::st_transform(parts, area_crs))
  ) / 1e6
  entity_id <- parts[[entity_field]]
  component_rank <- ave(
    -component_km2,
    entity_id,
    FUN = rank,
    ties.method = "first"
  )
  keep <- component_rank == 1L | component_km2 >= minimum_component_km2
  result <- parts[keep, , drop = FALSE]
  result[["component_km2"]] <- component_km2[keep]
  result[["regional_minimum_component_km2"]] <- minimum_component_km2
  result
}

build_southwest_reference_layers <- function(
    census_year = 2025L,
    reference_dir = southwest_reference_directory(),
    overwrite = FALSE,
    quiet = FALSE) {
  optional_packages <- c("tigris", "rnaturalearth")
  missing <- optional_packages[
    !vapply(optional_packages, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing) > 0L) {
    stop(
      "Install the reference-layer packages before downloading: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  census_year <- as.integer(census_year)
  if (length(census_year) != 1L || is.na(census_year)) {
    stop("`census_year` must be one valid year.", call. = FALSE)
  }
  paths <- vapply(
    c("tribal", "rivers", "interstates"),
    southwest_reference_layer_path,
    character(1),
    reference_dir = reference_dir
  )
  tribal_full_path <- file.path(
    reference_dir, "tribal-areas-census-2025-full.gpkg"
  )
  if (!overwrite && all(file.exists(c(paths, tribal_full_path)))) {
    if (!quiet) message("Using existing Southwest reference layers.")
    return(invisible(paths))
  }

  dir.create(reference_dir, recursive = TRUE, showWarnings = FALSE)
  bbox <- southwest_reference_bbox()
  crop_to_map <- function(x) {
    x <- sf::st_transform(x, 4326)
    suppressWarnings(sf::st_crop(x, bbox))
  }
  old_tigris_cache <- getOption("tigris_use_cache")
  options(tigris_use_cache = FALSE)
  on.exit(options(tigris_use_cache = old_tigris_cache), add = TRUE)

  if (
    overwrite || !file.exists(paths[["tribal"]]) ||
      !file.exists(tribal_full_path)
  ) {
    if (overwrite || !file.exists(tribal_full_path)) {
      if (!quiet) message("Downloading Census tribal-area boundaries for ", census_year, ".")
      tribal_full <- tigris::native_areas(
        cb = TRUE, year = census_year, progress_bar = FALSE
      )
      tribal_full <- crop_to_map(tribal_full)
      tribal_full <- tribal_full[, intersect(
        c("GEOID", "NAME", "NAMELSAD", "LSAD", "geometry"), names(tribal_full)
      )]
      sf::st_write(
        tribal_full, tribal_full_path, delete_dsn = TRUE, quiet = TRUE
      )
    } else {
      tribal_full <- sf::st_read(tribal_full_path, quiet = TRUE)
    }
    tribal_regional <- generalize_southwest_tribal_boundaries(
      tribal_full,
      minimum_component_km2 = 25
    )
    sf::st_write(
      tribal_regional, paths[["tribal"]], delete_dsn = TRUE, quiet = TRUE
    )
  }

  if (overwrite || !file.exists(paths[["rivers"]])) {
    if (!quiet) message("Downloading Natural Earth 10m river centerlines.")
    rivers <- rnaturalearth::ne_download(
      scale = 10,
      type = "rivers_lake_centerlines",
      category = "physical",
      destdir = tempdir(),
      load = TRUE,
      returnclass = "sf"
    )
    rivers <- rivers[
      rivers[["name"]] %in% c(
        "Colorado", "Gila", "Rio Grande", "Pecos", "San Juan", "Canadian"
      ),
    ]
    rivers <- crop_to_map(rivers)
    rivers <- rivers[, intersect(
      c("name", "name_alt", "scalerank", "geometry"), names(rivers)
    )]
    sf::st_write(rivers, paths[["rivers"]], delete_dsn = TRUE, quiet = TRUE)
  }

  if (overwrite || !file.exists(paths[["interstates"]])) {
    if (!quiet) message("Downloading Census primary roads for ", census_year, ".")
    roads <- tigris::primary_roads(year = census_year, progress_bar = FALSE)
    interstate_names <- paste0(
      "I- ", c("8", "10", "11", "15", "17", "19", "20", "25", "40")
    )
    roads <- roads[roads[["FULLNAME"]] %in% interstate_names, ]
    roads <- crop_to_map(roads)
    roads <- roads[, intersect(
      c("LINEARID", "FULLNAME", "RTTYP", "MTFCC", "geometry"), names(roads)
    )]
    sf::st_write(roads, paths[["interstates"]], delete_dsn = TRUE, quiet = TRUE)
  }

  rm(list = ls(envir = .southwest_reference_cache), envir = .southwest_reference_cache)
  if (!quiet) message("Southwest map reference layers are ready in ", reference_dir, ".")
  invisible(paths)
}
