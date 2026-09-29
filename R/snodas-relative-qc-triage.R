# Diagnostic-only second-stage triage of relative SNODAS SWE candidates.
# No daily grid, seasonal map, mask rule, or archive quality status is changed.

snodas_relative_daily_evidence <- function(
    candidates, dates, read_pair, progress_every = 25L) {
  if (!is.data.frame(candidates) ||
      !all(c("cell", "longitude", "latitude", "peak_swe_inches") %in%
           names(candidates)) || !is.function(read_pair) ||
      length(progress_every) != 1L || !is.numeric(progress_every) ||
      !is.finite(progress_every) || progress_every != floor(progress_every) ||
      progress_every < 1L) {
    stop("Invalid SNODAS relative daily-evidence inputs.", call. = FALSE)
  }
  dates <- sort(unique(as.Date(dates)))
  if (!length(dates) || anyNA(dates)) {
    stop("Choose valid daily evidence dates.", call. = FALSE)
  }
  candidates$source_valid_days <- integer(nrow(candidates))
  candidates$peak_date <- rep(NA_character_, nrow(candidates))
  candidates$daily_peak_inches <- rep(NA_real_, nrow(candidates))
  candidates$nearby_valid_days <- integer(nrow(candidates))
  candidates$nearby_near_peak_fraction <- rep(NA_real_, nrow(candidates))
  candidates$map_daily_difference_inches <-
    rep(NA_real_, nrow(candidates))
  candidates$weak_temporal_support <- rep(NA, nrow(candidates))
  candidates$map_daily_mismatch <- rep(NA, nrow(candidates))
  candidates$provenance_needed <- rep(TRUE, nrow(candidates))
  if (!nrow(candidates)) return(candidates)
  swe <- matrix(NA_real_, length(dates), nrow(candidates))
  points <- as.matrix(candidates[, c("longitude", "latitude")])
  for (i in seq_along(dates)) {
    pair <- tryCatch(read_pair(dates[i], points), error = function(e) NULL)
    if (!is.null(pair) && is.list(pair) &&
        all(c("swe", "depth") %in% names(pair)) &&
        is.numeric(pair$swe) && is.numeric(pair$depth) &&
        length(pair$swe) == nrow(candidates) &&
        length(pair$depth) == nrow(candidates)) {
      valid <- is.finite(pair$swe) & is.finite(pair$depth) &
        pair$swe >= 0 & pair$depth >= 0 &
        pair$swe <= pair$depth + 1e-6 &
        pair$swe < 32767 / 25.4 &
        pair$depth < 32767 / 25.4
      swe[i, valid] <- pair$swe[valid]
    }
    if (i %% progress_every == 0L || i == length(dates)) {
      message(sprintf("SNODAS relative daily evidence: %d/%d dates.",
                      i, length(dates)))
    }
  }
  for (j in seq_len(nrow(candidates))) {
    valid <- which(is.finite(swe[, j]))
    candidates$source_valid_days[j] <- length(valid)
    if (!length(valid)) next
    peak_index <- valid[which.max(swe[valid, j])]
    peak_value <- swe[peak_index, j]
    date <- dates[peak_index]
    in_window <- dates >= date - 7L & dates <= date + 7L
    window_values <- swe[in_window, j]
    valid_window <- is.finite(window_values)
    nearby_valid <- sum(valid_window)
    near_peak <- sum(valid_window &
                       window_values >= 0.75 * peak_value)
    difference <- abs(peak_value - candidates$peak_swe_inches[j])
    candidates$peak_date[j] <- as.character(date)
    candidates$daily_peak_inches[j] <- peak_value
    candidates$nearby_valid_days[j] <- nearby_valid
    candidates$nearby_near_peak_fraction[j] <-
      near_peak / nearby_valid
    candidates$map_daily_difference_inches[j] <- difference
    candidates$weak_temporal_support[j] <-
      nearby_valid < 8L || near_peak / nearby_valid < 0.75
    candidates$map_daily_mismatch[j] <- difference > 0.005
    candidates$provenance_needed[j] <- FALSE
  }
  candidates
}

snodas_relative_qc_read_points <- function(
    date, points, processed_dir = swc_paths$processed) {
  swe_path <- snodas_processed_path(date, "swe", processed_dir)
  depth_path <- snodas_processed_path(date, "depth", processed_dir)
  if (!file.exists(swe_path) || !file.exists(depth_path)) return(NULL)
  swe <- terra::rast(swe_path)
  depth <- terra::rast(depth_path)
  if (terra::nlyr(swe) != 1L || terra::nlyr(depth) != 1L ||
      !terra::compareGeom(swe, depth, stopOnError = FALSE) ||
      length(terra::time(swe)) != 1L ||
      length(terra::time(depth)) != 1L ||
      is.na(terra::time(swe)) || is.na(terra::time(depth)) ||
      as.Date(terra::time(swe)) != date ||
      as.Date(terra::time(depth)) != date) return(NULL)
  swe_values <- terra::extract(swe, points)
  depth_values <- terra::extract(depth, points)
  list(swe = as.numeric(swe_values[, ncol(swe_values)]),
       depth = as.numeric(depth_values[, ncol(depth_values)]))
}

build_snodas_relative_qc_triage <- function(
    years = 2005:2025,
    archive_dir = file.path("data", "diagnostics", "snodas-seasonal-archive"),
    output_dir = file.path("data", "diagnostics", "snodas-relative-qc-triage"),
    processed_dir = swc_paths$processed) {
  relative <- build_snodas_relative_qc_pilot(
    years, archive_dir, file.path(output_dir, "discovery"), processed_dir)
  reference_review <- build_snodas_seasonal_review_queue(
    2005:2025, archive_dir, file.path(output_dir, "reference-review"))
  verified <- reference_review$years$water_year[
    reference_review$years$archive_state == "OUTPUTS_VERIFIED"]
  pieces <- vector("list", nrow(relative$summary))
  for (i in seq_len(nrow(relative$summary))) {
    year <- relative$summary$water_year[i]
    year_candidates <- relative$candidates[
      relative$candidates$water_year == year, , drop = FALSE]
    if (!nrow(year_candidates)) next
    dates <- seq(as.Date(sprintf("%d-10-01", year - 1L)),
                 as.Date(sprintf("%d-05-31", year)), by = "day")
    message(sprintf("SNODAS relative triage: WY%d, %d candidates.",
                    year, nrow(year_candidates)))
    pieces[[i]] <- snodas_relative_daily_evidence(
      year_candidates, dates,
      function(date, points) snodas_relative_qc_read_points(
        date, points, processed_dir))
  }
  peaks <- if (any(lengths(pieces))) {
    do.call(rbind, pieces[lengths(pieces) > 0L])
  } else data.frame()
  if (nrow(peaks)) {
    template <- terra::rast(file.path(
      archive_dir, sprintf("wy%04d", peaks$water_year[1L]),
      "peak_swe.tif"))
    historical <- snodas_qc_pilot_reference(
      peaks, verified, archive_dir, template)
    peaks$sharp_local_contrast <- TRUE
    read_day <- function(date) {
      swe <- terra::rast(snodas_processed_path(
        date, "swe", processed_dir))
      depth <- terra::rast(snodas_processed_path(
        date, "depth", processed_dir))
      if (length(terra::time(swe)) != 1L ||
          length(terra::time(depth)) != 1L ||
          is.na(terra::time(swe)) || is.na(terra::time(depth)) ||
          as.Date(terra::time(swe)) != date ||
          as.Date(terra::time(depth)) != date) {
        stop("SNODAS relative triage source date mismatch: ", date,
             call. = FALSE)
      }
      pair <- screen_snodas_analysis_pair(swe, depth)
      list(swe = snodas_align_common_grid(pair$swe, template),
           depth = snodas_align_common_grid(pair$depth, template))
    }
    peaks <- snodas_qc_pilot_peaks(
      peaks, read_day, historical, strict_spatial = TRUE)
  }
  # One connected patch can contain cells that peak weeks apart. Split by
  # peak date before grouping nearby dates into review episodes.
  events <- snodas_qc_pilot_events(peaks, split_peak_date = TRUE)
  episodes <- snodas_qc_pilot_episodes(events)
  summary <- relative$summary
  # Bind the diagnostic result to the exact seasonal outputs it screened.
  # Site staging must not reuse an old zero-flag scan after a map revision.
  markers <- lapply(summary$water_year, function(year) {
    path <- file.path(archive_dir, sprintf("wy%04d", year),
                      "complete.csv")
    if (!file.exists(path)) return(NULL)
    tryCatch(utils::read.csv(path, stringsAsFactors = FALSE),
             error = function(e) NULL)
  })
  summary$source_signature <- vapply(markers, function(marker) {
    if (is.null(marker) || nrow(marker) != 1L ||
        !"source_signature" %in% names(marker)) NA_character_ else
          as.character(marker$source_signature[[1L]])
  }, character(1L))
  summary$peak_swe_md5 <- unname(tools::md5sum(file.path(
    archive_dir, sprintf("wy%04d", summary$water_year), "peak_swe.tif")))
  summary$quality_md5 <- unname(tools::md5sum(file.path(
    archive_dir, sprintf("wy%04d", summary$water_year),
    "quality-summary.csv")))
  summary$review_events <- vapply(summary$water_year, function(year) sum(
    events$water_year == year & events$pilot_priority == "REVIEW_EVENT"),
    integer(1))
  summary$review_episodes <- vapply(summary$water_year, function(year) sum(
    episodes$water_year == year &
      episodes$pilot_priority == "REVIEW_EPISODE"), integer(1))
  summary$missing_evidence_episodes <- vapply(
    summary$water_year, function(year) sum(
      episodes$water_year == year &
        episodes$missing_evidence_patches > 0L), integer(1))
  summary[summary$archive_state != "OUTPUTS_VERIFIED",
          c("review_events", "review_episodes",
            "missing_evidence_episodes")] <- NA_integer_
  benchmark <- relative$benchmarks
  if (nrow(benchmark)) {
    key <- paste(peaks$water_year, peaks$cell)
    benchmark$triage_priority <- peaks$pilot_priority[
      match(paste(benchmark$water_year, benchmark$cell), key)]
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c(summary = file.path(output_dir, "year-summary.csv"),
             episodes = file.path(output_dir, "episodes.csv"),
             events = file.path(output_dir, "events.csv"),
             candidates = file.path(output_dir, "candidate-evidence.csv"),
             benchmarks = file.path(output_dir, "known-mask-benchmarks.csv"))
  utils::write.csv(summary, paths[["summary"]], row.names = FALSE)
  utils::write.csv(episodes, paths[["episodes"]], row.names = FALSE)
  utils::write.csv(events, paths[["events"]], row.names = FALSE)
  utils::write.csv(peaks, paths[["candidates"]], row.names = FALSE)
  utils::write.csv(benchmark, paths[["benchmarks"]], row.names = FALSE)
  message("SNODAS relative triage: ", nrow(peaks), " candidates, ",
          nrow(episodes), " flagged episodes; no maps or masks changed.")
  list(summary = summary, peaks = peaks, events = events,
       episodes = episodes, benchmarks = benchmark, paths = paths)
}
