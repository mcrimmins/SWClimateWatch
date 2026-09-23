# Cache historical rolling precipitation samples by duration and calendar date.

prism_accumulation_cache_version <- 2L

prism_accumulation_cache_manifest_path <- function(processed_dir = swc_paths$processed) {
  file.path(processed_dir, "prism", "accumulation-cache-manifest.csv")
}

prism_accumulation_cache_path <- function(
    accumulation_days,
    target_date,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed) {
  accumulation_days <- as.integer(accumulation_days)
  if (length(accumulation_days) != 1L || is.na(accumulation_days) || accumulation_days < 1L) {
    stop("`accumulation_days` must be a positive integer.", call. = FALSE)
  }
  window_days <- validate_prism_window(window_days)
  target_date <- as.Date(target_date)
  if (length(target_date) != 1L || is.na(target_date)) {
    stop("`target_date` must be one valid date.", call. = FALSE)
  }
  baseline_label <- paste0(
    format(as.Date(baseline_start), "%Y%m%d"), "-",
    format(as.Date(baseline_end), "%Y%m%d")
  )
  file.path(
    processed_dir, "prism", aoi_id, "climatology", baseline_label,
    "rolling-samples", "pcpn",
    paste0(sprintf("%03d", accumulation_days), "day"),
    sprintf("centered-%02dday", window_days),
    paste0(format(target_date, "%m-%d"), ".tif")
  )
}

prism_accumulation_source_signature <- function(selection, processed_manifest) {
  paths <- unique(selection$path)
  manifest <- processed_manifest[!duplicated(processed_manifest$path, fromLast = TRUE), , drop = FALSE]
  rows <- match(paths, manifest$path)
  if (anyNA(rows)) {
    stop("One or more selected precipitation sources are absent from the processed manifest.", call. = FALSE)
  }
  checksums <- manifest$md5[rows]
  missing <- is.na(checksums) | !nzchar(checksums)
  if (any(missing)) {
    if (any(!file.exists(paths[missing]))) {
      stop("Cannot checksum one or more missing precipitation sources.", call. = FALSE)
    }
    checksums[missing] <- unname(tools::md5sum(paths[missing]))
  }
  digest::digest(sort(paste(paths, checksums, sep = "=")), algo = "sha256")
}

read_prism_accumulation_cache <- function(path, expected_end_dates = NULL) {
  if (!file.exists(path)) stop("Accumulation cache does not exist: ", path, call. = FALSE)
  raster <- terra::rast(path)
  dates <- as.Date(terra::time(raster))
  if (length(dates) != terra::nlyr(raster) || anyNA(dates) || anyDuplicated(dates)) {
    stop("Accumulation cache must have one unique valid date per layer: ", path, call. = FALSE)
  }
  if (!is.null(expected_end_dates)) {
    expected_end_dates <- sort(unique(as.Date(expected_end_dates)))
    dates_match <- length(dates) == length(expected_end_dates) &&
      all(dates == expected_end_dates)
    if (!dates_match) {
      stop("Accumulation cache dates do not match the requested reference sample.", call. = FALSE)
    }
  }
  raster
}

build_prism_accumulation_cache <- function(
    accumulation_days,
    target_date,
    baseline_start = swc_prism$percentile_start,
    baseline_end = swc_prism$percentile_end,
    window_days = swc_prism$centered_window_days,
    aoi_id = swc_prism$aoi_id,
    processed_dir = swc_paths$processed,
    processed_manifest = read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    manifest_path = prism_accumulation_cache_manifest_path(processed_dir),
    overwrite = FALSE,
    allow_incremental = TRUE,
    progress_every = 25L,
    quiet = FALSE) {
  accumulation_days <- as.integer(accumulation_days)
  target_date <- as.Date(target_date)
  window_days <- validate_prism_window(window_days)
  reference_groups <- prism_reference_window_dates(
    target_date, baseline_start, baseline_end, window_days
  )
  reference_end_dates <- sort(unique(do.call(c, reference_groups)))
  source_dates <- prism_rolling_source_dates(reference_end_dates, accumulation_days)
  selection <- select_prism_daily_sources(
    "pcpn", source_dates, aoi_id, processed_manifest
  )
  source_signature <- prism_accumulation_source_signature(selection, processed_manifest)
  path <- prism_accumulation_cache_path(
    accumulation_days, target_date, baseline_start, baseline_end,
    window_days, aoi_id, processed_dir
  )

  cache_manifest <- read_prism_manifest(manifest_path)
  existing <- if (nrow(cache_manifest) > 0L &&
      all(c("path", "source_signature", "cache_version", "md5") %in% names(cache_manifest))) {
    cache_manifest[cache_manifest$path == path, , drop = FALSE]
  } else {
    data.frame()
  }
  version_current <- nrow(existing) > 0L &&
    "cache_version" %in% names(existing) &&
    identical(as.integer(tail(existing$cache_version, 1L)), prism_accumulation_cache_version)
  checksum_current <- file.exists(path) && nrow(existing) > 0L &&
    identical(tail(existing$md5, 1L), unname(tools::md5sum(path)))
  current <- file.exists(path) && version_current && checksum_current &&
    identical(tail(existing$source_signature, 1L), source_signature)
  if (current && !overwrite) {
    if (!quiet) message("Using current ", accumulation_days, "-day accumulation cache for ", format(target_date, "%m-%d"), ".")
    return(invisible(list(
      raster = read_prism_accumulation_cache(path, reference_end_dates),
      groups = reference_groups,
      path = path,
      source_signature = source_signature,
      build_method = if ("build_method" %in% names(existing)) {
        tail(existing$build_method, 1L)
      } else {
        "direct"
      },
      refreshed = FALSE
    )))
  }

  totals <- NULL
  build_method <- "direct"
  parent_path <- NA_character_
  parent_md5 <- NA_character_
  previous_date <- target_date - 1L
  target_key <- format(target_date, "%m-%d")
  previous_key <- format(previous_date, "%m-%d")
  can_increment <- isTRUE(allow_incremental) && target_key != "02-29" &&
    previous_key != "02-29"

  if (can_increment) {
    previous_groups <- prism_reference_window_dates(
      previous_date, baseline_start, baseline_end, window_days
    )
    previous_end_dates <- sort(unique(do.call(c, previous_groups)))
    dates_advance_one_day <- length(previous_end_dates) == length(reference_end_dates) &&
      all(previous_end_dates + 1L == reference_end_dates)
    previous_path <- prism_accumulation_cache_path(
      accumulation_days, previous_date, baseline_start, baseline_end,
      window_days, aoi_id, processed_dir
    )
    previous_record <- if (nrow(cache_manifest) > 0L &&
        all(c("path", "source_signature", "cache_version", "md5") %in% names(cache_manifest))) {
      cache_manifest[cache_manifest$path == previous_path, , drop = FALSE]
    } else {
      data.frame()
    }
    if (dates_advance_one_day && file.exists(previous_path) && nrow(previous_record) > 0L &&
        identical(as.integer(tail(previous_record$cache_version, 1L)),
                  prism_accumulation_cache_version)) {
      previous_source_dates <- prism_rolling_source_dates(
        previous_end_dates, accumulation_days
      )
      previous_selection <- select_prism_daily_sources(
        "pcpn", previous_source_dates, aoi_id, processed_manifest
      )
      previous_signature <- prism_accumulation_source_signature(
        previous_selection, processed_manifest
      )
      actual_parent_md5 <- unname(tools::md5sum(previous_path))
      parent_current <- identical(
        tail(previous_record$source_signature, 1L), previous_signature
      ) && identical(tail(previous_record$md5, 1L), actual_parent_md5)
      if (parent_current) {
        if (!quiet) {
          message(
            "Incrementing ", accumulation_days, "-day accumulation cache from ",
            previous_key, " to ", target_key, "."
          )
        }
        previous <- read_prism_accumulation_cache(previous_path, previous_end_dates)
        outgoing_dates <- previous_end_dates - accumulation_days + 1L
        incoming_dates <- reference_end_dates
        edge_dates <- sort(unique(c(outgoing_dates, incoming_dates)))
        edge <- read_prism_best_daily_range(
          "pcpn", edge_dates, aoi_id, processed_manifest
        )
        outgoing <- edge$raster[[match(outgoing_dates, edge$dates)]]
        incoming <- edge$raster[[match(incoming_dates, edge$dates)]]
        terra::compareGeom(previous, outgoing, stopOnError = TRUE)
        terra::compareGeom(previous, incoming, stopOnError = TRUE)
        totals <- previous - outgoing + incoming
        terra::time(totals) <- reference_end_dates
        names(totals) <- paste0(
          "pcpn_total_", sprintf("%03d", accumulation_days),
          "day_", reference_end_dates
        )
        build_method <- "incremental"
        parent_path <- previous_path
        parent_md5 <- actual_parent_md5
      }
    }
  }

  if (is.null(totals)) {
    if (!quiet) {
      message(
        "Building ", accumulation_days, "-day accumulation cache for ",
        format(target_date, "%m-%d"), " from ", length(source_dates),
        " daily layers."
      )
    }
    collection <- read_prism_best_daily_range(
      "pcpn", source_dates, aoi_id, processed_manifest
    )
    totals <- prism_rolling_totals_for_end_dates(
      collection$raster, collection$dates, reference_end_dates,
      accumulation_days, progress_every, quiet
    )
  }
  # Preserve exact ordering and near-ties in empirical ranks. FLT4 rounding can
  # turn two almost-equal accumulation totals into an artificial exact tie.
  write_prism_processed_raster(totals, path, datatype = "FLT8S")

  record <- data.frame(
    product = "rolling_accumulation_sample",
    cache_version = prism_accumulation_cache_version,
    aoi_id = aoi_id,
    variable = "pcpn",
    native_units = "inch",
    storage_datatype = "FLT8S",
    accumulation_days = accumulation_days,
    target_calendar_day = format(target_date, "%m-%d"),
    method = sprintf("centered-%02dday", window_days),
    window_days = window_days,
    start_date = as.Date(baseline_start),
    end_date = as.Date(baseline_end),
    sample_layers = terra::nlyr(totals),
    build_method = build_method,
    parent_path = parent_path,
    parent_md5 = parent_md5,
    source_signature = source_signature,
    built_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    bytes = file.info(path)$size,
    md5 = unname(tools::md5sum(path)),
    path = path,
    stringsAsFactors = FALSE
  )
  write_prism_manifest(record, manifest_path)
  if (!quiet) message("Wrote accumulation cache: ", path)
  invisible(list(
    raster = read_prism_accumulation_cache(path, reference_end_dates),
    groups = reference_groups,
    path = path,
    source_signature = source_signature,
    build_method = build_method,
    refreshed = TRUE
  ))
}
