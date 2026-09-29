# Read-only, event-level QC pilot for completed SNODAS seasonal peak maps.
# This does not mask data or change the archive quality gate.

snodas_qc_pilot_neighbors <- function(values, cell, nrow, ncol) {
  row <- (cell - 1L) %/% ncol + 1L
  col <- (cell - 1L) %% ncol + 1L
  rr <- rep(row + (-1L:1L), each = 3L)
  cc <- rep(col + (-1L:1L), times = 3L)
  keep <- rr >= 1L & rr <= nrow & cc >= 1L & cc <= ncol &
    !(rr == row & cc == col)
  values[(rr[keep] - 1L) * ncol + cc[keep]]
}

snodas_qc_pilot_reference <- function(peaks, years, archive_dir,
                                      template) {
  result <- rep(NA_real_, nrow(peaks))
  if (!nrow(peaks)) return(result)
  reference <- matrix(NA_real_, nrow(peaks), length(years))
  for (i in seq_along(years)) {
    path <- file.path(archive_dir, sprintf("wy%04d", years[i]),
                      "peak_swe.tif")
    if (!file.exists(path)) next
    raster <- terra::rast(path)
    if (terra::nlyr(raster) != 1L ||
        !terra::compareGeom(raster, template, stopOnError = FALSE)) next
    reference[, i] <- terra::values(raster, mat = FALSE)[peaks$cell]
  }
  for (i in seq_len(nrow(peaks))) {
    other <- reference[i, years != peaks$water_year[i]]
    other <- other[is.finite(other)]
    if (length(other) >= 10L) {
      result[i] <- as.numeric(stats::quantile(other, 0.95, type = 8))
    }
  }
  result
}

snodas_qc_pilot_peaks <- function(peaks, read_day,
                                  historical_p95_inches = NULL,
                                  progress_every = 10L,
                                  strict_spatial = FALSE,
                                  isolation_inches = 30,
                                  isolation_ratio = 2) {
  if (!is.data.frame(peaks) ||
      !all(c("water_year", "cell", "peak_date", "peak_swe_inches",
             "patch_id", "sharp_local_contrast",
             "weak_temporal_support", "map_daily_mismatch",
             "provenance_needed") %in% names(peaks)) ||
      !is.function(read_day) || length(progress_every) != 1L ||
      !is.numeric(progress_every) || !is.finite(progress_every) ||
      progress_every != floor(progress_every) || progress_every < 1L ||
      length(strict_spatial) != 1L || is.na(strict_spatial) ||
      !is.logical(strict_spatial) ||
      length(isolation_inches) != 1L ||
      !is.numeric(isolation_inches) ||
      !is.finite(isolation_inches) || isolation_inches <= 0 ||
      length(isolation_ratio) != 1L ||
      !is.numeric(isolation_ratio) ||
      !is.finite(isolation_ratio) || isolation_ratio <= 1) {
    stop("Invalid SNODAS QC-pilot inputs.", call. = FALSE)
  }
  if (is.null(historical_p95_inches)) {
    historical_p95_inches <- rep(NA_real_, nrow(peaks))
  }
  if (!is.numeric(historical_p95_inches) ||
      length(historical_p95_inches) != nrow(peaks)) {
    stop("Invalid historical SNODAS reference.", call. = FALSE)
  }
  peaks$historical_p95_inches <- historical_p95_inches
  peaks$same_day_neighbor_median_inches <- NA_real_
  peaks$same_day_valid_neighbors <- NA_integer_
  peaks$same_day_supporting_neighbors <- NA_integer_
  peaks$same_day_sharp_contrast <- NA
  peaks$swe_depth_ratio <- NA_real_
  peaks$neighbor_median_swe_depth_ratio <- NA_real_
  peaks$density_contrast <- NA
  peaks$strong_spatial_isolation <- NA
  peaks$historical_extreme <- is.finite(historical_p95_inches) &
    peaks$peak_swe_inches >= historical_p95_inches + 20 &
    peaks$peak_swe_inches >= 1.5 * historical_p95_inches
  peaks$pilot_priority <- rep("NEEDS_EVIDENCE", nrow(peaks))
  if (!nrow(peaks)) return(peaks)
  dates <- as.Date(peaks$peak_date)
  peak_dates <- as.character(sort(unique(dates[!is.na(dates)])))
  for (date_index in seq_along(peak_dates)) {
    date_text <- peak_dates[date_index]
    date <- as.Date(date_text)
    index <- which(dates == date)
    pair <- tryCatch(read_day(date), error = function(e) NULL)
    if (is.null(pair) || !is.list(pair) ||
        !all(c("swe", "depth") %in% names(pair)) ||
        !inherits(pair$swe, "SpatRaster") ||
        !inherits(pair$depth, "SpatRaster") ||
        terra::nlyr(pair$swe) != 1L || terra::nlyr(pair$depth) != 1L ||
        !terra::compareGeom(pair$swe, pair$depth,
                            stopOnError = FALSE)) next
    swe <- terra::values(pair$swe, mat = FALSE)
    depth <- terra::values(pair$depth, mat = FALSE)
    nrow <- terra::nrow(pair$swe)
    ncol <- terra::ncol(pair$swe)
    for (i in index) {
      cell <- peaks$cell[i]
      if (is.na(cell) || cell < 1L || cell > length(swe) ||
          !is.finite(swe[cell]) || !is.finite(depth[cell]) ||
          depth[cell] <= 0) next
      nearby_swe <- snodas_qc_pilot_neighbors(swe, cell, nrow, ncol)
      nearby_depth <- snodas_qc_pilot_neighbors(depth, cell, nrow, ncol)
      # Snow-free neighbors (SWE = depth = 0) still provide valid spatial
      # SWE context. Only density ratios require positive snow depth.
      valid <- is.finite(nearby_swe) & is.finite(nearby_depth) &
        nearby_swe >= 0 & nearby_depth >= 0 &
        nearby_swe <= nearby_depth + 1e-6
      if (sum(valid) < 5L) next
      nearby_swe <- nearby_swe[valid]
      nearby_depth <- nearby_depth[valid]
      density_valid <- nearby_depth > 0
      nearby_density <- nearby_swe[density_valid] /
        nearby_depth[density_valid]
      median_swe <- stats::median(nearby_swe)
      median_density <- if (length(nearby_density))
        stats::median(nearby_density) else NA_real_
      density <- swe[cell] / depth[cell]
      peaks$same_day_valid_neighbors[i] <- sum(valid)
      peaks$same_day_neighbor_median_inches[i] <- median_swe
      peaks$same_day_supporting_neighbors[i] <- sum(
        nearby_swe >= 0.75 * swe[cell])
      peaks$same_day_sharp_contrast[i] <-
        swe[cell] >= median_swe + 15 &&
        swe[cell] >= 1.5 * median_swe
      peaks$swe_depth_ratio[i] <- density
      peaks$neighbor_median_swe_depth_ratio[i] <- median_density
      peaks$density_contrast[i] <- if (is.finite(median_density))
        density >= median_density + 0.15 &&
          density >= 1.5 * median_density else NA
    }
    if (date_index %% progress_every == 0L ||
        date_index == length(peak_dates)) {
      message(sprintf("SNODAS QC pilot: %d/%d peak dates checked.",
                      date_index, length(peak_dates)))
    }
  }
  for (i in seq_len(nrow(peaks))) {
    if (isTRUE(peaks$provenance_needed[i]) ||
        is.na(peaks$same_day_sharp_contrast[i])) next
    if (isTRUE(peaks$map_daily_mismatch[i])) {
      peaks$pilot_priority[i] <- "REVIEW_EVENT"
      next
    }
    low_support <- peaks$same_day_supporting_neighbors[i] < 2L
    contrast <- isTRUE(peaks$same_day_sharp_contrast[i])
    strong_isolation <- low_support &&
      peaks$peak_swe_inches[i] >=
        peaks$same_day_neighbor_median_inches[i] + isolation_inches &&
      peaks$peak_swe_inches[i] >=
        isolation_ratio * peaks$same_day_neighbor_median_inches[i]
    peaks$strong_spatial_isolation[i] <- strong_isolation
    corroboration <- (low_support &&
                        (!strict_spatial || strong_isolation)) ||
      isTRUE(peaks$density_contrast[i]) ||
      isTRUE(peaks$weak_temporal_support[i])
    peaks$pilot_priority[i] <- if (contrast && corroboration) {
      "REVIEW_EVENT"
    } else if (contrast ||
               isTRUE(peaks$sharp_local_contrast[i]) ||
               isTRUE(peaks$historical_extreme[i]) ||
               isTRUE(peaks$weak_temporal_support[i])) {
      "CONTEXT_FLAG"
    } else "COHERENT_EXTREME"
  }
  peaks
}

snodas_qc_pilot_events <- function(peaks, split_peak_date = FALSE) {
  empty <- data.frame(
    water_year = integer(), patch_id = integer(), peak_cells = integer(),
    peak_date_first = character(), peak_date_last = character(),
    maximum_swe_inches = numeric(), review_cells = integer(),
    context_cells = integer(), needs_evidence_cells = integer(),
    pilot_priority = character())
  if (!nrow(peaks)) return(empty)
  key <- ifelse(is.na(peaks$patch_id),
                paste(peaks$water_year, "cell", peaks$cell),
                paste(peaks$water_year, "patch", peaks$patch_id))
  if (split_peak_date) {
    key <- paste(key, ifelse(is.na(peaks$peak_date),
                            paste0("missing-", peaks$cell),
                            peaks$peak_date))
  }
  groups <- split(seq_len(nrow(peaks)), key)
  rows <- lapply(groups, function(index) {
    part <- peaks[index, , drop = FALSE]
    dates <- as.Date(part$peak_date)
    priority <- if (any(part$pilot_priority == "REVIEW_EVENT")) {
      "REVIEW_EVENT"
    } else if (any(part$pilot_priority == "NEEDS_EVIDENCE")) {
      "NEEDS_EVIDENCE"
    } else if (any(part$pilot_priority == "CONTEXT_FLAG")) {
      "CONTEXT_FLAG"
    } else "COHERENT_EXTREME"
    data.frame(
      water_year = part$water_year[1L], patch_id = part$patch_id[1L],
      peak_cells = nrow(part),
      peak_date_first = if (all(is.na(dates))) NA_character_ else
        as.character(min(dates, na.rm = TRUE)),
      peak_date_last = if (all(is.na(dates))) NA_character_ else
        as.character(max(dates, na.rm = TRUE)),
      maximum_swe_inches = max(part$peak_swe_inches),
      review_cells = sum(part$pilot_priority == "REVIEW_EVENT"),
      context_cells = sum(part$pilot_priority == "CONTEXT_FLAG"),
      needs_evidence_cells = sum(part$pilot_priority == "NEEDS_EVIDENCE"),
      pilot_priority = priority)
  })
  events <- do.call(rbind, rows)
  events <- events[order(match(events$pilot_priority,
                               c("NEEDS_EVIDENCE", "REVIEW_EVENT",
                                 "CONTEXT_FLAG", "COHERENT_EXTREME")),
                         -events$maximum_swe_inches), , drop = FALSE]
  rownames(events) <- NULL
  events
}

snodas_qc_pilot_episodes <- function(events, gap_days = 2L) {
  if (length(gap_days) != 1L || !is.numeric(gap_days) ||
      !is.finite(gap_days) || gap_days != floor(gap_days) ||
      gap_days < 0L) {
    stop("`gap_days` must be a nonnegative whole number.", call. = FALSE)
  }
  empty <- data.frame(
    water_year = integer(), start_date = character(),
    end_date = character(), flagged_patches = integer(),
    flagged_cells = integer(), maximum_swe_inches = numeric(),
    review_patches = integer(), missing_evidence_patches = integer(),
    pilot_priority = character())
  if (!nrow(events)) return(empty)
  flagged <- events$pilot_priority %in%
    c("REVIEW_EVENT", "NEEDS_EVIDENCE")
  events <- events[flagged, , drop = FALSE]
  if (!nrow(events)) return(empty)
  dates <- as.Date(events$peak_date_first)
  order_index <- order(events$water_year, dates, na.last = TRUE)
  events <- events[order_index, , drop = FALSE]
  dates <- dates[order_index]
  groups <- integer(nrow(events))
  group <- 0L
  episode_start <- as.Date(NA)
  previous_year <- NA_integer_
  for (i in seq_len(nrow(events))) {
    new_group <- i == 1L || is.na(dates[i]) || is.na(episode_start) ||
        events$water_year[i] != previous_year ||
        as.integer(dates[i] - episode_start) > gap_days
    if (new_group) {
      group <- group + 1L
      episode_start <- dates[i]
    }
    groups[i] <- group
    previous_year <- events$water_year[i]
  }
  rows <- lapply(split(seq_len(nrow(events)), groups), function(index) {
    part <- events[index, , drop = FALSE]
    start <- as.Date(part$peak_date_first)
    end <- as.Date(part$peak_date_last)
    data.frame(
      water_year = part$water_year[1L],
      start_date = if (all(is.na(start))) NA_character_ else
        as.character(min(start, na.rm = TRUE)),
      end_date = if (all(is.na(end))) NA_character_ else
        as.character(max(end, na.rm = TRUE)),
      flagged_patches = nrow(part),
      flagged_cells = sum(part$peak_cells),
      maximum_swe_inches = max(part$maximum_swe_inches),
      review_patches = sum(part$pilot_priority == "REVIEW_EVENT"),
      missing_evidence_patches = sum(
        part$pilot_priority == "NEEDS_EVIDENCE"),
      pilot_priority = if (any(part$pilot_priority == "REVIEW_EVENT"))
        "REVIEW_EPISODE" else "NEEDS_EVIDENCE")
  })
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}

build_snodas_seasonal_qc_pilot <- function(
    years = 2005:2025,
    reference_years = 2005:2025,
    archive_dir = file.path("data", "diagnostics", "snodas-seasonal-archive"),
    output_dir = file.path("data", "diagnostics", "snodas-seasonal-qc-pilot"),
    processed_dir = swc_paths$processed) {
  review <- build_snodas_seasonal_review_queue(
    sort(unique(c(years, reference_years))), archive_dir,
    file.path(output_dir, "review-queue"))
  peaks <- review$peaks[review$peaks$water_year %in% years, , drop = FALSE]
  verified <- review$years$water_year[
    review$years$archive_state == "OUTPUTS_VERIFIED"]
  if (nrow(peaks)) {
    first_path <- file.path(archive_dir,
                            sprintf("wy%04d", peaks$water_year[1L]),
                            "peak_swe.tif")
    template <- terra::rast(first_path)
    reference <- snodas_qc_pilot_reference(
      peaks, verified, archive_dir, template)
    read_day <- function(date) {
      swe_path <- snodas_processed_path(date, "swe", processed_dir)
      depth_path <- snodas_processed_path(date, "depth", processed_dir)
      swe <- terra::rast(swe_path)
      depth <- terra::rast(depth_path)
      if (as.Date(terra::time(swe)) != date ||
          as.Date(terra::time(depth)) != date) {
        stop("SNODAS QC-pilot source date mismatch: ", date,
             call. = FALSE)
      }
      pair <- screen_snodas_analysis_pair(swe, depth)
      list(swe = snodas_align_common_grid(pair$swe, template),
           depth = snodas_align_common_grid(pair$depth, template))
    }
    peaks <- snodas_qc_pilot_peaks(peaks, read_day, reference)
  } else {
    peaks <- snodas_qc_pilot_peaks(peaks, function(date) NULL)
  }
  events <- snodas_qc_pilot_events(peaks)
  episodes <- snodas_qc_pilot_episodes(events)
  years_table <- review$years[review$years$water_year %in% years, ,
                              drop = FALSE]
  years_table$qc_pilot_review_events <- vapply(
    years_table$water_year, function(year) sum(
      events$water_year == year & events$pilot_priority == "REVIEW_EVENT"),
    integer(1))
  years_table$qc_pilot_needs_evidence_events <- vapply(
    years_table$water_year, function(year) sum(
      events$water_year == year & events$pilot_priority == "NEEDS_EVIDENCE"),
    integer(1))
  years_table$qc_pilot_review_episodes <- vapply(
    years_table$water_year, function(year) sum(
      episodes$water_year == year &
        episodes$pilot_priority == "REVIEW_EPISODE"), integer(1))
  years_table$qc_pilot_review_events[
    years_table$archive_state != "OUTPUTS_VERIFIED"] <- NA_integer_
  years_table$qc_pilot_needs_evidence_events[
    years_table$archive_state != "OUTPUTS_VERIFIED"] <- NA_integer_
  years_table$qc_pilot_review_episodes[
    years_table$archive_state != "OUTPUTS_VERIFIED"] <- NA_integer_
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c(years = file.path(output_dir, "years.csv"),
             events = file.path(output_dir, "events.csv"),
             episodes = file.path(output_dir, "episodes.csv"),
             peaks = file.path(output_dir, "peaks.csv"))
  utils::write.csv(years_table, paths[["years"]], row.names = FALSE)
  utils::write.csv(events, paths[["events"]], row.names = FALSE)
  utils::write.csv(episodes, paths[["episodes"]], row.names = FALSE)
  utils::write.csv(peaks, paths[["peaks"]], row.names = FALSE)
  message("SNODAS QC pilot: ", nrow(years_table), " years, ",
          nrow(events), " high-SWE patches; ", nrow(episodes),
          " flagged episodes. No maps or masks changed.")
  list(years = years_table, events = events, episodes = episodes,
       peaks = peaks,
       paths = paths)
}
