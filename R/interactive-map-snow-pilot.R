# Local-only SNODAS adapter. Reuses operational screening and exact endpoints.
interactive_snow_fields <- function(inputs, percent, change) {
  v <- function(x) terra::values(x, mat = FALSE)
  observed <- v(inputs$observed); median <- v(inputs$median_swe)
  years <- v(inputs$sample_years)
  supported <- is.finite(observed) & is.finite(median) & is.finite(years) & years >= 15
  departure_status <- ifelse(supported, ifelse(median < 1, 2L, 1L), 3L)
  list(observed = observed, median = median, departure = v(inputs$departure),
    percent = v(percent$percent_of_median),
    change = if (is.null(change)) rep(NA_real_, length(observed)) else v(change),
    years = years, percent_status = v(percent$display_status),
    departure_status = departure_status)
}

build_interactive_map_snow_pilot <- function(
    output_dir = "data/diagnostics/interactive-map-snow-pilot",
    base_dir = "data/diagnostics/interactive-map-pilot",
    dates = NULL, processed_dir = swc_paths$processed, published_only = FALSE) {
  if (!file.exists(file.path(base_dir, "manifest.json")))
    stop("Build the existing interactive map pilot first; its local assets are reused.")
  publication <- read.csv("data/diagnostics/snodas-current-site/publication.csv")
  published_date <- as.Date(publication$date[[1L]])
  if (published_only) dates <- published_date else
    if (is.null(dates)) dates <- unique(c(published_date, as.Date("2025-02-15")))
  dates <- as.Date(dates)
  if (!length(dates) || anyNA(dates) || anyDuplicated(dates)) stop("Choose unique valid cached dates.")
  manifest <- jsonlite::read_json(file.path(base_dir, "manifest.json"), simplifyVector = FALSE)
  # This pilot keeps all other existing selections intact, but never stages them.
  assets <- unique(c("boundaries.json", "leaflet.js", "leaflet.css", "leaflet-package-LICENSE",
    vapply(manifest$layers, function(x) x$file, character(1))))
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  for (asset in assets) {
    from <- file.path(base_dir, asset)
    if (grepl("\\.bin$", asset)) {
      receipt <- paste0(from, ".md5")
      if (!file.exists(receipt) || trimws(readLines(receipt, warn = FALSE)[1L]) != unname(tools::md5sum(from)))
        stop("Base viewer payload failed integrity check: ", asset)
    }
    interactive_pilot_copy(from, file.path(output_dir, asset))
    if (grepl("\\.bin$", asset))
      interactive_pilot_copy(paste0(from, ".md5"), file.path(output_dir, paste0(asset, ".md5")))
  }
  for (asset in c("index.html", "pilot.js", "pilot.css"))
    interactive_pilot_copy(file.path("scripts/interactive-map-assets", asset), file.path(output_dir, asset))
  metrics <- list(swe = "Snow water equivalent", departure = "Departure from median",
    percent = "Percent of median", change = "7-day net SWE change")
  periods <- as.list(setNames(paste(format(dates, "%b %d, %Y"),
    if (published_only) "(verified snow snapshot)" else
      ifelse(dates == published_date, "(local published snapshot)", "(historical example)")), as.character(dates)))
  manifest$current$variables$snow <- list(label = "Snow", measures = list(snowpack = list(
    label = "Snowpack water", metrics = metrics, periods = setNames(rep(list(periods), 4L), names(metrics)))))
  assessment <- list()
  for (date_text in as.character(dates)) {
    date <- as.Date(date_text)
    message("Assessing cached snow snapshot: ", date)
    signature <- snodas_current_site_source_signature(date, processed_dir)
    inputs <- load_snodas_swe_map_pilot_inputs(date, processed_dir = processed_dir)
    gate <- assess_snodas_swe_map_quality(inputs, snodas_swe_map_review_summary(
      inputs$observed, inputs$median_swe, inputs$date, inputs$qc))
    require_snodas_swe_map_publishable(gate)
    percent <- snodas_daily_percent_swe(inputs$observed, inputs$median_swe,
      inputs$sample_years, date, min_years = 18L, minimum_median_inches = 1)
    endpoint <- snodas_current_change_endpoint(date - 7L, inputs$observed, processed_dir)
    change <- if (is.null(endpoint$swe)) NULL else snodas_seven_day_swe_change(inputs$observed, endpoint$swe, date)
    if (!is.null(change) && mean(is.finite(terra::values(change, mat = FALSE))) < .8) {
      change <- NULL; endpoint$reason <- "Too little shared valid coverage at exact seven-day endpoints."
    }
    values <- interactive_snow_fields(inputs, percent, change)
    r <- inputs$observed; ex <- as.vector(terra::ext(r)); res <- terra::res(r)
    grid <- list(rows = nrow(r), cols = ncol(r), west = ex[1], east = ex[2], south = ex[3], north = ex[4], dx = res[1], dy = res[2])
    types <- c(rep("float64", 5L), rep("uint8", 3L)); names(types) <- names(values)
    file <- paste0("snow-", date, "-", substr(signature, 1, 16), ".bin.gz")
    con <- gzfile(file.path(output_dir, file), "wb", compression = 6L)
    fields <- list(); offset <- 0L
    tryCatch(for (name in names(values)) {
      type <- types[[name]]; size <- if (type == "float64") 8L else 1L
      v <- values[[name]]
      fields[[name]] <- list(type = type, offset = offset)
      if (size == 8L) writeBin(as.double(v), con, size = 8L, endian = "little") else {
        v[!is.finite(v)] <- 255L
        writeBin(as.raw(v), con)
      }
      offset <- offset + length(v) * size
    }, finally = close(con))
    writeLines(unname(tools::md5sum(file.path(output_dir, file))),
      file.path(output_dir, paste0(file, ".md5")))
    # Lossless round trip checks every cell, including zero and missing masks.
    con <- gzfile(file.path(output_dir, file), "rb")
    tryCatch(for (name in names(values)) {
      actual <- if (types[[name]] == "float64") readBin(con, "double", length(values[[name]]), size = 8L, endian = "little") else
        as.numeric(readBin(con, "raw", length(values[[name]])))
      if (types[[name]] == "uint8") actual[actual == 255] <- NA_real_
      expected <- values[[name]]
      stopifnot(identical(is.finite(actual), is.finite(expected)),
        identical(actual[is.finite(actual)], as.double(expected[is.finite(expected)])))
    }, finally = close(con))
    if (!identical(signature, snodas_current_site_source_signature(date, processed_dir))) stop("Snow inputs changed during build.")
    id <- paste0("snow-", date)
    historical <- date != published_date
    reference <- paste0("NOAA/NSIDC SNODAS modeled SWE; WY2005-WY2025 centered five-day median. ",
      "Departure reference: at least 15 years; percentage: at least 18 years and median at least 1 inch. ",
      if (published_only) "Latest verified Current Snow snapshot; use its displayed date." else
        if (historical) "Historical cached example, not current conditions." else "Local published snapshot; not a claim of today's availability.")
    manifest$layers[[id]] <- list(file = file, compression = "gzip", bytes = offset,
      transfer_bytes = unname(file.info(file.path(output_dir, file))$size), fields = fields,
      date = date_text, start_date = date_text, grid = grid, reference = reference,
      source_signature = signature, md5 = unname(tools::md5sum(file.path(output_dir, file))),
      change_start_date = as.character(date - 7L),
      change_available = !is.null(change), change_note = endpoint$reason)
    for (metric in names(metrics)) {
      product <- paste("snow", metric, date, sep = "-")
      manifest$current$products[[product]] <- list(variable = "snow", measure = "snowpack", metric = metric,
        period = date_text, period_label = periods[[date_text]], title = metrics[[metric]],
        layer_id = id, available = metric != "change" || !is.null(change), note = endpoint$reason,
        description = reference, date = date_text)
      if (published_only) {
        manifest$current$products[[product]]$product_page <- "../pages/snow-conditions.html"
        manifest$current$products[[product]]$public_url <- "https://cales.arizona.edu/climate/watch/pages/snow-conditions.html"
      }
    }
    assessment[[date_text]] <- data.frame(date = date_text, cells = terra::ncell(r),
      cell_arcseconds = res[1] * 3600, decoded_mib = offset / 2^20,
      transfer_mib = file.info(file.path(output_dir, file))$size / 2^20,
      observed_cells = sum(is.finite(values$observed)), zero_swe_cells = sum(values$observed == 0, na.rm = TRUE),
      percent_cells = sum(values$percent_status == 1), low_typical_cells = sum(values$percent_status == 2),
      unavailable_ratio_cells = sum(values$percent_status == 3),
      change_available = !is.null(change), quality = gate$status, lossless = TRUE)
    message("  Native cells preserved; compressed payload: ", round(tail(assessment, 1)[[1]]$transfer_mib, 2), " MiB.")
  }
  manifest$snow_mode <- if (published_only) "verified_current" else "review"
  manifest$initial_selection <- if (published_only) NULL else list(frequency = "current", variable = "snow", measure = "snowpack", metric = "swe", period = as.character(dates[1]))
  jsonlite::write_json(manifest, file.path(output_dir, "manifest.json"), auto_unbox = TRUE, pretty = TRUE, digits = 16, null = "null")
  assessment <- do.call(rbind, assessment)
  write.csv(assessment, file.path(output_dir, "snow-payload-assessment.csv"), row.names = FALSE)
  invisible(list(assessment = assessment, manifest = manifest))
}
