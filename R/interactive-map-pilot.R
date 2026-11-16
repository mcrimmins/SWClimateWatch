# Static, local-only raster exploration. Reads completed monthly products only.
interactive_pilot_definitions <- function() {
  end <- "2026-10"
  rank_root <- file.path("data/diagnostics/prism-monthly-ranking-pilots", end)
  definitions <- list()
  for (family in c("precipitation", "temperature", "spi")) for (duration in c(1L, 3L, 6L, 12L)) {
    first <- seq(as.Date(paste0(end, "-01")), by = "-1 month", length.out = duration)[duration]
    period <- if (duration == 1L) "October 2026" else paste(format(first, "%B %Y"), "to October 2026")
    fields <- switch(family,
      precipitation = c(total_precipitation_inches = "float32", percentile = "float32", departure_inches = "float32",
        wet_rank = "float32", sample_years = "uint16", record = "uint8"),
      temperature = c(mean_temperature_f = "float32", percentile = "float32", departure_f = "float32",
        warm_rank = "float32", sample_years = "uint16", record = "uint8"),
      spi = c(spi = "float32", spi_status = "uint8", sample_years = "uint16"))
    id <- sprintf("%s-%02dmonth", family, duration)
    definitions[[id]] <- list(family = family, duration = duration, period = period,
      folder = if (family == "spi") file.path("data/diagnostics/prism-monthly-spi-pilots", end, sprintf("%02dmonth", duration)) else
        file.path(rank_root, family, sprintf("%02dmonth", duration)), fields = fields,
      reference = if (family == "spi") "Fixed 1895-2020 calibration; gamma maximum likelihood with zero-precipitation adjustment" else
        "Rankings: matching complete monthly windows in the available record beginning in 1895. Departures: matching 1991-2020 windows (at least 27 years).")
  }
  definitions
}

interactive_pilot_copy <- function(from, to) {
  dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
  if (!file.exists(to) || unname(tools::md5sum(from)) != unname(tools::md5sum(to))) {
    if (!file.copy(from, to, overwrite = TRUE)) stop("Cannot copy ", from)
  }
}

build_interactive_map_pilot <- function(output_dir = "data/diagnostics/interactive-map-pilot") {
  started <- proc.time()[["elapsed"]]
  definitions <- interactive_pilot_definitions()
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  manifest <- list(schema = 2L, source = "PRISM Climate Group via RCC-ACIS", end_month = "2026-10",
    variables = list(
      precipitation = list(label = "Precipitation", metrics = list(total = "Total", ranking = "Percentile ranking", departure = "Departure from normal", spi = "SPI")),
      temperature = list(label = "Temperature", metrics = list(mean = "Mean temperature", ranking = "Percentile ranking", departure = "Departure from normal"))),
    durations = c(1L, 3L, 6L, 12L),
    basemaps = list(
      street = list(title = "Street", url = "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        attribution = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'),
      terrain = list(title = "Terrain", url = "https://services.arcgisonline.com/ArcGIS/rest/services/Elevation/World_Hillshade/MapServer/tile/{z}/{y}/{x}",
        attribution = 'Terrain: <a href="https://services.arcgisonline.com/ArcGIS/rest/services/Elevation/World_Hillshade/MapServer">Esri and elevation data contributors</a>'),
      satellite = list(title = "Satellite", url = "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
        attribution = 'Imagery: <a href="https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer">Esri, Vantor, Earthstar Geographics, GIS User Community</a>')),
    reference_overlays = list(
      roads = list(url = "https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}",
        attribution = 'Roads/labels: <a href="https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer">Esri, HERE, Garmin</a>, &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'),
      places = list(url = "https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}",
        attribution = 'Places: <a href="https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer">Esri, HERE, Garmin, OpenStreetMap contributors, GIS User Community</a>')),
    layers = list())
  checks <- list(); builds <- list()
  for (id in names(definitions)) {
    d <- definitions[[id]]
    marker_file <- file.path(d$folder, "complete.rds")
    if (!file.exists(marker_file)) stop("Build the completed monthly pilots first: ", marker_file)
    marker <- readRDS(marker_file)
    if (!length(marker$files) || length(marker$files) != length(marker$md5) ||
        any(!file.exists(marker$files)) || !identical(unname(tools::md5sum(marker$files)), marker$md5))
      stop("Monthly product integrity check failed: ", d$folder, ". Rebuild that monthly pilot first.")
    input_names <- setdiff(names(d$fields), "record")
    paths <- file.path(d$folder, paste0(input_names, ".tif"))
    if ("record" %in% names(d$fields)) paths <- c(paths, file.path(d$folder,
      paste0(c("record_high", "record_high_tied", "record_low", "record_low_tied"), ".tif")))
    rasters <- lapply(paths, terra::rast)
    r <- rasters[[1]]
    if (!terra::is.lonlat(r) || !grepl("4326", terra::crs(r))) stop("Pilot requires WGS84 geographic source cells.")
    for (other in rasters) if (!terra::compareGeom(r, other, stopOnError = FALSE)) stop("Misaligned source fields.")
    values <- lapply(rasters, function(x) terra::values(x, mat = FALSE))
    names(values) <- tools::file_path_sans_ext(basename(paths))
    if ("record" %in% names(d$fields)) {
      record <- rep(0, terra::ncell(r))
      record[which(values$record_high == 1)] <- 1
      record[which(values$record_high_tied == 1)] <- 2
      record[which(values$record_low == 1)] <- 3
      record[which(values$record_low_tied == 1)] <- 4
      record[!is.finite(values$percentile)] <- NA
      values$record <- record
    }
    fields <- list(); offset <- 0L
    for (name in names(d$fields)) {
      type <- d$fields[[name]]; size <- switch(type, float32 = 4L, uint16 = 2L, uint8 = 1L)
      fields[[name]] <- list(type = type, offset = offset)
      offset <- offset + size * terra::ncell(r)
    }
    # Include policy, geometry and exact source hashes in immutable derivative names.
    version <- substr(digest::digest(list(policy = "interactive-native-cell-v1", fields = fields,
      geometry = c(as.vector(terra::ext(r)), terra::res(r), dim(r)), md5 = unname(tools::md5sum(paths))), algo = "sha256"), 1, 16)
    filename <- paste0(id, "-", version, ".bin"); destination <- file.path(output_dir, filename)
    reused <- file.exists(destination) && file.info(destination)$size == offset
    if (reused) {
      receipt <- paste0(destination, ".md5")
      reused <- file.exists(receipt) && identical(readLines(receipt), unname(tools::md5sum(destination)))
    }
    if (!reused) {
      con <- file(destination, "wb")
      tryCatch(for (name in names(d$fields)) {
        type <- d$fields[[name]]; v <- values[[name]]
        if (type == "float32") writeBin(as.numeric(v), con, size = 4, endian = "little") else {
          sentinel <- if (type == "uint16") 65535L else 255L
          if (any(v >= sentinel | v < 0 | v != floor(v), na.rm = TRUE)) stop("Invalid integer field: ", name)
          v[is.na(v)] <- sentinel
          writeBin(as.integer(v), con, size = if (type == "uint16") 2 else 1, endian = "little")
        }
      }, finally = close(con))
      writeLines(unname(tools::md5sum(destination)), paste0(destination, ".md5"))
    }
    # Read every encoded value back, including all missing cells, before allowing preview.
    con <- file(destination, "rb")
    tryCatch(for (name in names(d$fields)) {
      type <- d$fields[[name]]
      decoded <- readBin(con, if (type == "float32") "numeric" else "integer", n = terra::ncell(r),
        size = switch(type, float32 = 4, uint16 = 2, uint8 = 1), signed = type == "float32", endian = "little")
      if (type != "float32") decoded[decoded == if (type == "uint16") 65535 else 255] <- NA
      original <- values[[name]]
      passed <- length(decoded) == length(original) && identical(is.na(decoded), is.na(original)) &&
        all(decoded[!is.na(original)] == original[!is.na(original)])
      checks[[length(checks) + 1L]] <- data.frame(layer = id, field = name, cells = length(original), passed = passed)
      if (!passed) stop("Binary/source mismatch: ", id, " ", name)
    }, finally = close(con))
    e <- as.vector(terra::ext(r))
    entry <- d[setdiff(names(d), c("folder", "fields"))]
    entry$file <- filename; entry$fields <- fields; entry$bytes <- offset
    entry$grid <- list(west = e[1], east = e[2], south = e[3], north = e[4],
      dx = terra::res(r)[1], dy = terra::res(r)[2], rows = terra::nrow(r), cols = terra::ncol(r))
    entry$source_md5 <- as.list(setNames(unname(tools::md5sum(paths)), basename(paths)))
    manifest$layers[[id]] <- entry
    builds[[id]] <- data.frame(layer = id, bytes = offset, reused = reused)
    message("Interactive pilot: ", id, "; ", if (reused) "reused" else "built", "; all cell values verified.")
  }
  for (file in c("index.html", "pilot.js", "pilot.css")) interactive_pilot_copy(
    file.path("scripts/interactive-map-assets", file), file.path(output_dir, file))
  for (file in c("leaflet.js", "leaflet.css", "leaflet-package-LICENSE")) {
    from <- file.path("site/stations", file)
    if (!file.exists(from)) stop("Missing local Leaflet asset: ", from, ". Build Station Conditions first.")
    interactive_pilot_copy(from, file.path(output_dir, file))
  }
  boundary <- file.path(output_dir, "boundaries.json")
  if (!file.exists(boundary)) {
    states <- sf::st_as_sf(maps::map("state", regions = c("arizona", "new mexico", "colorado", "utah", "nevada", "california", "texas", "oklahoma"), fill = TRUE, plot = FALSE))
    sf::st_write(states, boundary, driver = "GeoJSON", quiet = TRUE)
  }
  temporary <- tempfile(fileext = ".json")
  jsonlite::write_json(manifest, temporary, auto_unbox = TRUE, pretty = TRUE, digits = 16)
  interactive_pilot_copy(temporary, file.path(output_dir, "manifest.json")); unlink(temporary)
  check <- do.call(rbind, checks); summary <- do.call(rbind, builds)
  write.csv(check, file.path(dirname(output_dir), "interactive-map-pilot-checks.csv"), row.names = FALSE)
  write.csv(summary, file.path(dirname(output_dir), "interactive-map-pilot-build.csv"), row.names = FALSE)
  message("Local-only pilot ready: ", output_dir, "; ", round(proc.time()[["elapsed"]] - started, 2), " seconds. No downloads or publication.")
  invisible(list(summary = summary, checks = check, manifest = manifest))
}
