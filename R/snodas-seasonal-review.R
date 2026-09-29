# Read-only triage of completed SNODAS seasonal maps. The report does not
# change source grids, archive maps, quality statuses, or peak-QC rules.

snodas_peak_neighbor_context <- function(values, cells, nrow, ncol,
                                         min_neighbors = 5L,
                                         contrast_inches = 15,
                                         contrast_ratio = 1.5) {
  if (!is.numeric(values) || length(values) != nrow * ncol ||
      anyNA(cells) || any(cells < 1L | cells > length(values)) ||
      length(min_neighbors) != 1L || min_neighbors < 1L ||
      min_neighbors > 8L || contrast_inches <= 0 ||
      contrast_ratio <= 1) {
    stop("Invalid SNODAS peak-neighbor inputs.", call. = FALSE)
  }
  result <- data.frame(
    cell = as.integer(cells), neighbor_count = integer(length(cells)),
    neighbor_median_inches = rep(NA_real_, length(cells)),
    neighbor_max_inches = rep(NA_real_, length(cells)),
    above_neighbor_median_inches = rep(NA_real_, length(cells)),
    peak_to_neighbor_median = rep(NA_real_, length(cells)),
    sharp_local_contrast = rep(FALSE, length(cells)),
    limited_neighbor_context = rep(FALSE, length(cells))
  )
  for (i in seq_along(cells)) {
    row <- (cells[i] - 1L) %/% ncol + 1L
    col <- (cells[i] - 1L) %% ncol + 1L
    rr <- rep(row + (-1L:1L), each = 3L)
    cc <- rep(col + (-1L:1L), times = 3L)
    keep <- rr >= 1L & rr <= nrow & cc >= 1L & cc <= ncol &
      !(rr == row & cc == col)
    neighbors <- values[(rr[keep] - 1L) * ncol + cc[keep]]
    neighbors <- neighbors[is.finite(neighbors)]
    result$neighbor_count[i] <- length(neighbors)
    result$limited_neighbor_context[i] <- length(neighbors) < min_neighbors
    if (!length(neighbors)) next
    median_value <- stats::median(neighbors)
    result$neighbor_median_inches[i] <- median_value
    result$neighbor_max_inches[i] <- max(neighbors)
    result$above_neighbor_median_inches[i] <- values[cells[i]] - median_value
    if (median_value > 0) {
      result$peak_to_neighbor_median[i] <- values[cells[i]] / median_value
    }
    result$sharp_local_contrast[i] <-
      !result$limited_neighbor_context[i] &&
      result$above_neighbor_median_inches[i] >= contrast_inches &&
      median_value <= values[cells[i]] / contrast_ratio
  }
  result
}

snodas_read_seasonal_review_csv <- function(path, required) {
  if (!file.exists(path)) return(NULL)
  value <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE),
                    error = function(e) NULL)
  if (is.null(value) || !all(required %in% names(value))) return(NULL)
  value
}

snodas_current_peak_provenance <- function(year_dir, marker, cells,
                                           peak_values) {
  summary <- snodas_read_seasonal_review_csv(
    file.path(year_dir, "peak-provenance-summary.csv"),
    c("source_signature", "peak_swe_md5", "threshold_inches",
      "radius_days", "high_peak_cells"))
  evidence <- snodas_read_seasonal_review_csv(
    file.path(year_dir, "peak-provenance-cells.csv"),
    c("cell", "map_peak_inches", "peak_date", "patch_id", "patch_cells",
      "nearby_valid_days", "nearby_near_peak_fraction",
      "peak_difference_inches"))
  if (is.null(summary) || nrow(summary) != 1L || is.null(evidence) ||
      !identical(as.character(summary$source_signature),
                 as.character(marker$source_signature)) ||
      !identical(as.character(summary$peak_swe_md5),
                 as.character(marker$peak_swe_md5)) ||
      is.na(summary$threshold_inches) || summary$threshold_inches != 50 ||
      is.na(summary$radius_days) || summary$radius_days != 7L ||
      is.na(summary$high_peak_cells) ||
      summary$high_peak_cells != length(cells) ||
      nrow(evidence) != length(cells) ||
      anyNA(evidence$cell) || anyDuplicated(evidence$cell) ||
      !setequal(as.integer(evidence$cell), as.integer(cells))) return(NULL)
  evidence <- evidence[match(cells, evidence$cell), , drop = FALSE]
  if (any(!is.finite(evidence$map_peak_inches)) ||
      any(abs(evidence$map_peak_inches - peak_values[cells]) > 0.005) ||
      anyNA(evidence[, c("peak_date", "patch_id", "patch_cells",
                        "nearby_valid_days",
                        "nearby_near_peak_fraction",
                        "peak_difference_inches")])) return(NULL)
  evidence
}

snodas_empty_peak_review <- function() {
  data.frame(
    water_year = integer(), cell = integer(), longitude = numeric(),
    latitude = numeric(), peak_swe_inches = numeric(), peak_date = character(),
    neighbor_count = integer(), neighbor_median_inches = numeric(),
    neighbor_max_inches = numeric(), above_neighbor_median_inches = numeric(),
    peak_to_neighbor_median = numeric(), patch_id = integer(),
    patch_cells = integer(),
    nearby_valid_days = integer(), nearby_near_peak_fraction = numeric(),
    map_daily_difference_inches = numeric(),
    sharp_local_contrast = logical(), limited_neighbor_context = logical(),
    isolated_moderate_contrast = logical(),
    weak_temporal_support = logical(), map_daily_mismatch = logical(),
    provenance_needed = logical(), review_priority = character()
  )
}

build_snodas_seasonal_review_queue <- function(
    years = 2005:2025,
    archive_dir = file.path("data", "diagnostics", "snodas-seasonal-archive"),
    output_dir = file.path("data", "diagnostics", "snodas-seasonal-review")) {
  if (!is.numeric(years) || !length(years) || anyNA(years) ||
      any(years != floor(years) | years < 2005L | years > 2025L)) {
    stop("Choose SNODAS water years from 2005-2025.", call. = FALSE)
  }
  years <- sort(unique(as.integer(years)))
  summaries <- vector("list", length(years))
  candidates <- vector("list", length(years))
  for (i in seq_along(years)) {
    year <- years[i]
    year_dir <- file.path(archive_dir, sprintf("wy%04d", year))
    peak_path <- file.path(year_dir, "peak_swe.tif")
    quality_path <- file.path(year_dir, "quality-summary.csv")
    marker <- snodas_read_seasonal_review_csv(
      file.path(year_dir, "complete.csv"),
      c("source_signature", "peak_swe_md5", "quality_md5"))
    quality <- snodas_read_seasonal_review_csv(
      quality_path,
      c("water_year", "source_signature", "status", "reasons",
        "known_missing_days", "days_with_pairwise_exclusions",
        "pairwise_excluded_cells", "peak_cells_for_review"))
    state <- "MISSING"
    if (!is.null(marker) && nrow(marker) == 1L &&
        !is.null(quality) && nrow(quality) == 1L &&
        file.exists(peak_path)) {
      state <- "UNVERIFIED"
      if (!anyNA(marker[, c("source_signature", "peak_swe_md5",
                            "quality_md5")]) &&
          !anyNA(quality[, c("water_year", "source_signature",
                             "known_missing_days",
                             "days_with_pairwise_exclusions",
                             "pairwise_excluded_cells",
                             "peak_cells_for_review")]) &&
          quality$water_year == year &&
          identical(as.character(quality$source_signature),
                    as.character(marker$source_signature)) &&
          identical(unname(tools::md5sum(peak_path)),
                    as.character(marker$peak_swe_md5)) &&
          identical(unname(tools::md5sum(quality_path)),
                    as.character(marker$quality_md5))) state <- "OUTPUTS_VERIFIED"
    }
    row <- data.frame(
      water_year = year, archive_state = state,
      quality_status = if (state == "OUTPUTS_VERIFIED") quality$status else NA_character_,
      quality_reasons = if (state == "OUTPUTS_VERIFIED") quality$reasons else NA_character_,
      known_missing_days = if (state == "OUTPUTS_VERIFIED") quality$known_missing_days else NA_integer_,
      days_with_pairwise_exclusions = if (state == "OUTPUTS_VERIFIED") quality$days_with_pairwise_exclusions else NA_integer_,
      pairwise_excluded_cells = if (state == "OUTPUTS_VERIFIED") quality$pairwise_excluded_cells else NA_integer_,
      documented_masked_cells = if (state == "OUTPUTS_VERIFIED" &&
                                    "peak_qc_masked_cells" %in% names(quality)) {
        quality$peak_qc_masked_cells
      } else if (state == "OUTPUTS_VERIFIED") 0L else NA_integer_,
      peak_cells_50in = if (state == "OUTPUTS_VERIFIED") 0L else NA_integer_,
      peak_audit_state = if (state == "OUTPUTS_VERIFIED") "NOT_NEEDED" else NA_character_,
      sharp_local_contrast_cells = if (state == "OUTPUTS_VERIFIED") 0L else NA_integer_,
      isolated_moderate_contrast_cells = if (state == "OUTPUTS_VERIFIED") 0L else NA_integer_,
      limited_neighbor_cells = if (state == "OUTPUTS_VERIFIED") 0L else NA_integer_,
      weak_temporal_support_cells = if (state == "OUTPUTS_VERIFIED") 0L else NA_integer_,
      map_daily_mismatch_cells = if (state == "OUTPUTS_VERIFIED") 0L else NA_integer_,
      provenance_needed_cells = if (state == "OUTPUTS_VERIFIED") 0L else NA_integer_,
      locally_coherent_cells = if (state == "OUTPUTS_VERIFIED") 0L else NA_integer_,
      stringsAsFactors = FALSE
    )
    if (state == "OUTPUTS_VERIFIED") {
      peak <- terra::rast(peak_path)
      if (terra::nlyr(peak) != 1L) {
        row$archive_state <- "UNVERIFIED"
      } else {
        values <- terra::values(peak, mat = FALSE)
        cells <- which(is.finite(values) & values >= 50)
        if (length(cells) != quality$peak_cells_for_review) {
          row$archive_state <- "UNVERIFIED"
        } else {
          row$peak_cells_50in <- length(cells)
          if (length(cells)) {
            evidence <- snodas_current_peak_provenance(
              year_dir, marker, cells, values)
            has_evidence <- !is.null(evidence)
            row$peak_audit_state <- if (has_evidence) "CURRENT" else "MISSING_OR_STALE"
            xy <- terra::xyFromCell(peak, cells)
            spatial <- snodas_peak_neighbor_context(
              values, cells, terra::nrow(peak), terra::ncol(peak))
            detail <- data.frame(
              water_year = rep(year, length(cells)),
              cell = cells, longitude = xy[, 1L], latitude = xy[, 2L],
              peak_swe_inches = values[cells],
              peak_date = if (has_evidence) {
                as.character(evidence$peak_date)
              } else NA_character_,
              spatial[, -1L, drop = FALSE],
              patch_id = if (has_evidence) evidence$patch_id else NA_integer_,
              patch_cells = if (has_evidence) evidence$patch_cells else NA_integer_,
              nearby_valid_days = if (has_evidence) evidence$nearby_valid_days else NA_integer_,
              nearby_near_peak_fraction = if (has_evidence) {
                evidence$nearby_near_peak_fraction
              } else NA_real_,
              map_daily_difference_inches = if (has_evidence) {
                evidence$peak_difference_inches
              } else NA_real_,
              stringsAsFactors = FALSE
            )
            detail$weak_temporal_support <- if (has_evidence) {
              evidence$nearby_valid_days < 8L |
                evidence$nearby_near_peak_fraction < 0.75
            } else NA
            detail$map_daily_mismatch <- if (has_evidence) {
              evidence$peak_difference_inches > 0.005
            } else NA
            detail$provenance_needed <- !has_evidence
            detail$isolated_moderate_contrast <- if (has_evidence) {
              !detail$sharp_local_contrast &
                !detail$limited_neighbor_context &
                detail$patch_cells <= 2L &
                detail$above_neighbor_median_inches >= 10 &
                detail$neighbor_median_inches <=
                  detail$peak_swe_inches / 1.25
            } else NA
            detail$review_priority <- ifelse(
              detail$sharp_local_contrast |
                (!is.na(detail$map_daily_mismatch) & detail$map_daily_mismatch),
              "CHECK_SOURCE", ifelse(
                detail$provenance_needed, "RUN_PEAK_AUDIT", ifelse(
                  detail$isolated_moderate_contrast, "CHECK_CONTEXT", ifelse(
                    detail$limited_neighbor_context, "CHECK_NEIGHBORS", ifelse(
                      detail$weak_temporal_support, "CHECK_TIMING",
                      "LOCALLY_COHERENT")))))
            candidates[[i]] <- detail
            row$sharp_local_contrast_cells <- sum(detail$sharp_local_contrast)
            row$isolated_moderate_contrast_cells <- sum(
              detail$isolated_moderate_contrast, na.rm = TRUE)
            row$limited_neighbor_cells <- sum(detail$limited_neighbor_context)
            row$weak_temporal_support_cells <- sum(detail$weak_temporal_support,
                                                   na.rm = TRUE)
            row$map_daily_mismatch_cells <- sum(detail$map_daily_mismatch,
                                                na.rm = TRUE)
            row$provenance_needed_cells <- sum(detail$provenance_needed)
            row$locally_coherent_cells <- sum(
              detail$review_priority == "LOCALLY_COHERENT")
          }
        }
      }
      if (row$archive_state != "OUTPUTS_VERIFIED") {
        row[1L, 3L:ncol(row)] <- NA
        candidates[[i]] <- NULL
      }
    }
    summaries[[i]] <- row
  }
  summary <- do.call(rbind, summaries)
  detail <- if (any(lengths(candidates))) {
    do.call(rbind, candidates[lengths(candidates) > 0L])
  } else snodas_empty_peak_review()
  detail <- detail[, names(snodas_empty_peak_review()), drop = FALSE]
  priority_order <- c("CHECK_SOURCE", "RUN_PEAK_AUDIT", "CHECK_CONTEXT",
                      "CHECK_TIMING", "CHECK_NEIGHBORS",
                      "LOCALLY_COHERENT")
  if (nrow(detail)) {
    detail <- detail[order(match(detail$review_priority, priority_order),
                           -detail$above_neighbor_median_inches,
                           detail$water_year),
                     , drop = FALSE]
    rownames(detail) <- NULL
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c(years = file.path(output_dir, "year-summary.csv"),
             peaks = file.path(output_dir, "peak-candidates.csv"))
  utils::write.csv(summary, paths[["years"]], row.names = FALSE)
  utils::write.csv(detail, paths[["peaks"]], row.names = FALSE)
  message("SNODAS seasonal review: ", nrow(summary), " years, ",
          nrow(detail), " high-peak cells; no maps or masks changed.")
  list(years = summary, peaks = detail, paths = paths)
}
