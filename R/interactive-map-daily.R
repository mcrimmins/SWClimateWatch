# Daily adapters reuse the Daily Explorer source precedence and verified caches.
interactive_daily_normal <- function(variable, date, template, climatology_manifest, hashes) {
  path <- daily_explorer_reference_path(variable, "mean")
  rows <- climatology_manifest[climatology_manifest$path == path &
    climatology_manifest$aoi_id == swc_prism$aoi_id & climatology_manifest$variable == variable &
    climatology_manifest$statistic == "mean" & climatology_manifest$start_date == swc_prism$normal_start &
    climatology_manifest$end_date == swc_prism$normal_end & climatology_manifest$window_days == swc_prism$centered_window_days, , drop = FALSE]
  if (!nrow(rows) || !file.exists(path) || is.na(hashes[path]) ||
      !identical(tail(rows$md5, 1), unname(hashes[path]))) return(NULL)
  daily_explorer_reference(path, date, template)
}

interactive_daily_export <- function(id, date, family, values, template, hashes, normal_available, output_dir) {
  types <- setNames(rep(if (family == "pcpn") "float32" else "float64", length(values)), names(values))
  fields <- list(); offset <- 0L; n <- terra::ncell(template)
  for (name in names(values)) {
    fields[[name]] <- list(type = types[[name]], offset = offset)
    offset <- offset + n * if (types[[name]] == "float64") 8L else 4L
  }
  g <- list(west = terra::xmin(template), east = terra::xmax(template), south = terra::ymin(template), north = terra::ymax(template),
    dx = terra::res(template)[1], dy = terra::res(template)[2], rows = terra::nrow(template), cols = terra::ncol(template))
  signature <- digest::digest(list(policy = "daily-native-cells-v1", date = date, family = family,
    fields = fields, grid = g, sources = hashes, normal_available = normal_available), algo = "sha256")
  filename <- paste0(id, "-", substr(signature, 1, 16), ".bin")
  path <- file.path(output_dir, filename); receipt <- paste0(path, ".md5")
  reused <- file.exists(path) && file.info(path)$size == offset && file.exists(receipt) &&
    identical(readLines(receipt), unname(tools::md5sum(path)))
  if (!reused) {
    con <- file(path, "wb")
    tryCatch(for (name in names(values)) writeBin(as.numeric(values[[name]]), con,
      size = if (types[[name]] == "float64") 8 else 4, endian = "little"), finally = close(con))
    writeLines(unname(tools::md5sum(path)), receipt)
  }
  checks <- list(); decoded <- list(); con <- file(path, "rb")
  tryCatch(for (name in names(values)) {
    v <- readBin(con, "numeric", n = n, size = if (types[[name]] == "float64") 8 else 4, endian = "little")
    original <- values[[name]]
    ok <- length(v) == length(original) && identical(is.na(v), is.na(original)) &&
      all(v[!is.na(original)] == original[!is.na(original)])
    if (!ok) stop("Daily payload mismatch: ", id, " ", name)
    checks[[name]] <- data.frame(layer = id, field = name, cells = n, passed = ok)
    decoded[[name]] <- v
  }, finally = close(con))
  if (family != "pcpn") {
    expected <- values$observed - values$normal
    actual <- decoded$observed - decoded$normal
    stopifnot(identical(is.na(expected), is.na(actual)), all(expected[!is.na(expected)] == actual[!is.na(actual)]))
    checks$departure <- data.frame(layer = id, field = "departure", cells = n, passed = TRUE)
  }
  list(entry = list(frequency = "daily", family = family, date = date, period = date,
    file = filename, fields = fields, grid = g, bytes = offset, normal_available = normal_available,
    derived_departure = family != "pcpn", source_md5 = as.list(hashes),
    reference = if (family == "pcpn") "Daily PRISM precipitation total; reporting periods may differ from local calendar days. Recent values may be revised." else
      paste0("Daily PRISM temperatures; departures use ", format(swc_prism$normal_start, "%Y"), "-", format(swc_prism$normal_end, "%Y"),
        " centered ", swc_prism$centered_window_days, "-day reference. Mean temperature requires paired high/low cells. Recent values may be revised.")),
    summary = data.frame(layer = id, bytes = offset, reused = reused), checks = do.call(rbind, checks))
}

add_interactive_daily_maps <- function(pilot, days = getOption("swc.interactive.daily_days", 30L), output_dir = "data/diagnostics/interactive-map-pilot") {
  if (length(days) != 1L || !is.finite(days) || days != as.integer(days) || days < 1 || days > 90) stop("Daily retention must be 1-90 calendar days.")
  m <- read_prism_manifest(prism_processed_manifest_path())
  rows <- m[m$product == "daily" & m$aoi_id == swc_prism$aoi_id & m$variable %in% c("pcpn", "maxt", "mint") & file.exists(m$path), , drop = FALSE]
  if (!nrow(rows)) stop("No cached daily PRISM inputs. Refresh the laptop cache first.")
  last <- max(rows$end_date); first <- last - as.integer(days) + 1L
  index <- daily_explorer_index(first, last, m)
  paths <- unique(index$path); hashes <- tools::md5sum(paths)
  cm <- read_prism_manifest(prism_climatology_manifest_path())
  normals <- vapply(c("maxt", "mint"), daily_explorer_reference_path, character(1), statistic = "mean")
  normal_hashes <- tools::md5sum(normals[file.exists(normals)])
  verified <- vapply(paths, function(path) {
    r <- rows[rows$path == path, , drop = FALSE]
    expected <- tail(r$md5, 1)
    !is.na(hashes[path]) && length(expected) == 1 && !is.na(expected) && identical(expected, unname(hashes[path]))
  }, logical(1))
  skipped <- list(); summaries <- list(); checks <- list(); entries <- list()
  reject <- function(date, variable, note) skipped[[length(skipped) + 1L]] <<- data.frame(date = date, variable = variable, note = note)
  for (date in as.character(seq(first, last, by = "day"))) {
    inputs <- list(); sources <- index[index$date == date, , drop = FALSE]
    for (v in c("pcpn", "maxt", "mint")) {
      source <- sources[sources$variable == v, , drop = FALSE]
      if (!nrow(source)) { reject(date, v, "Exact daily source missing"); next }
      path <- source$path[[1]]
      if (!verified[[path]]) { reject(date, v, "Processed-manifest checksum mismatch"); next }
      if (!identical(tail(rows$native_units[rows$path == path], 1), unname(swc_prism$native_units[[v]]))) {
        reject(date, v, "Unexpected processed source units"); next
      }
      inputs[[v]] <- tryCatch({
        r <- terra::rast(path)[[source$layer[[1]]]]
        if (!identical(as.character(prism_raster_dates(path)[source$layer[[1]]]), date)) stop("Daily layer date mismatch")
        if (!terra::is.lonlat(r) || !grepl("4326", terra::crs(r))) stop("Daily source is not WGS84")
        validate_prism_native_values(r, v)
        list(raster = r, path = path)
      }, error = function(e) { reject(date, v, conditionMessage(e)); NULL })
    }
    if (!is.null(inputs$maxt) && !is.null(inputs$mint)) {
      pair_ok <- terra::compareGeom(inputs$maxt$raster, inputs$mint$raster, stopOnError = FALSE)
      if (pair_ok) pair_ok <- !any(terra::values(inputs$maxt$raster, mat = FALSE) < terra::values(inputs$mint$raster, mat = FALSE), na.rm = TRUE)
      if (!pair_ok) {
        reject(date, "temperature", "High/low geometry or paired temperature check failed")
        inputs$maxt <- NULL; inputs$mint <- NULL
      }
    }
    for (family in c("pcpn", "maxt", "mint", "tmean")) {
      required <- if (family == "tmean") c("maxt", "mint") else family
      if (!all(required %in% names(inputs)) || any(vapply(inputs[required], is.null, logical(1)))) next
      template <- inputs[[required[1]]]$raster
      observed <- if (family == "tmean") (terra::values(inputs$maxt$raster, mat = FALSE) + terra::values(inputs$mint$raster, mat = FALSE)) / 2 else terra::values(template, mat = FALSE)
      normal_rasters <- if (family == "pcpn") list() else lapply(required, function(v) tryCatch(
        interactive_daily_normal(v, date, template, cm, normal_hashes), error = function(e) NULL))
      normal_ok <- family != "pcpn" && !any(vapply(normal_rasters, is.null, logical(1)))
      if (family != "pcpn" && !normal_ok) reject(date, paste0(family, "_departure"), "Exact-date normal missing, unverified or misaligned; departure withheld")
      normal <- if (!normal_ok) rep(NA_real_, length(observed)) else Reduce(`+`, lapply(normal_rasters, function(r) terra::values(r, mat = FALSE))) / length(required)
      vals <- if (family == "pcpn") list(observed = observed) else list(observed = observed, normal = normal)
      source_paths <- vapply(inputs[required], `[[`, character(1), "path")
      source_hashes <- hashes[source_paths]
      if (family != "pcpn") source_hashes <- c(source_hashes, normal_hashes[normals[required][normals[required] %in% names(normal_hashes)]])
      id <- paste0("daily-", family, "-", date)
      result <- interactive_daily_export(id, date, family, vals, template, source_hashes, normal_ok, output_dir)
      entries[[id]] <- result$entry; summaries[[id]] <- result$summary; checks[[id]] <- result$checks
    }
    message("Interactive daily maps: ", date, "; ", sum(vapply(entries, function(x) identical(x$date, date), logical(1))), " verified bundles.")
  }
  if (!length(entries)) stop("No daily inputs passed verification; monthly snapshot retained.")
  pilot$manifest$schema <- 3L
  pilot$manifest$daily <- list(first_date = as.character(first), latest_date = as.character(last), retained_days = as.integer(days),
    variables = list(precipitation = list(label = "Precipitation", metrics = list(total = "Daily total")),
      temperature = list(label = "Temperature", metrics = list(mean = "Daily mean", high = "Daily high", low = "Daily low",
        mean_departure = "Mean departure", high_departure = "High departure", low_departure = "Low departure"))))
  pilot$manifest$layers <- c(pilot$manifest$layers, entries)
  temporary <- tempfile(fileext = ".json")
  jsonlite::write_json(pilot$manifest, temporary, auto_unbox = TRUE, pretty = TRUE, digits = 16)
  interactive_pilot_copy(temporary, file.path(output_dir, "manifest.json")); unlink(temporary)
  pilot$summary <- rbind(pilot$summary, do.call(rbind, summaries)); pilot$checks <- rbind(pilot$checks, do.call(rbind, checks))
  missing <- if (length(skipped)) do.call(rbind, skipped) else data.frame(date = character(), variable = character(), note = character())
  write.csv(missing, file.path(dirname(output_dir), "interactive-daily-input-status.csv"), row.names = FALSE)
  write.csv(do.call(rbind, checks), file.path(dirname(output_dir), "interactive-daily-checks.csv"), row.names = FALSE)
  message("Daily preview ready: ", first, " through ", last, "; ", length(entries), " bundles. No downloads or publication.")
  pilot
}
