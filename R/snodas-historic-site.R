# Stage reviewed, already-rendered SNODAS seasonal PNGs for Historic Years.
# No download, seasonal recalculation, Quarto render, or remote deployment.

snodas_historic_source_paths <- function(
    water_year,
    archive_root = file.path("data", "diagnostics", "snodas-seasonal-archive")) {
  if (length(water_year) != 1L || is.na(water_year) ||
      water_year != floor(water_year) ||
      water_year < 2005L || water_year > 2025L) {
    stop("Choose a SNODAS water year from 2005-2025.", call. = FALSE)
  }
  directory <- file.path(archive_root, sprintf("wy%04d", water_year))
  c(peak_swe = file.path(directory, "peak_swe.tif"),
    snow_days = file.path(directory, "snow_days.tif"),
    coverage = file.path(directory, "coverage.tif"),
    peak_map = file.path(directory, "peak_swe.png"),
    snow_days_map = file.path(directory, "snow_days.png"),
    quality = file.path(directory, "quality-summary.csv"),
    complete = file.path(directory, "complete.csv"))
}

snodas_historic_verify_output <- function(
    water_year,
    archive_root = file.path("data", "diagnostics", "snodas-seasonal-archive")) {
  paths <- snodas_historic_source_paths(water_year, archive_root)
  if (!all(file.exists(paths))) {
    stop("Missing SNODAS WY", water_year, " seasonal output(s).",
         call. = FALSE)
  }
  marker <- utils::read.csv(paths[["complete"]], stringsAsFactors = FALSE)
  quality <- utils::read.csv(paths[["quality"]], stringsAsFactors = FALSE)
  required <- paste0(names(paths)[names(paths) != "complete"], "_md5")
  if (nrow(marker) != 1L || nrow(quality) != 1L ||
      !all(c("source_signature", required) %in% names(marker)) ||
      !all(c("water_year", "source_signature", "status") %in%
           names(quality)) ||
      quality$water_year != water_year ||
      !identical(as.character(marker$source_signature),
                 as.character(quality$source_signature)) ||
      is.na(quality$status) || quality$status == "FAIL" ||
      !quality$status %in% c("PASS", "REVIEW")) {
    stop("SNODAS WY", water_year, " completion or quality is invalid.",
         call. = FALSE)
  }
  actual <- unname(tools::md5sum(paths[names(paths) != "complete"]))
  expected <- unname(unlist(marker[1L, required]))
  if (anyNA(actual) || anyNA(expected) || !identical(actual, expected)) {
    stop("SNODAS WY", water_year, " seasonal checksums differ from ",
         "the completion marker.", call. = FALSE)
  }
  list(paths = paths, marker = marker, quality = quality)
}

snodas_historic_validate_triage <- function(
    triage_dir = file.path("data", "diagnostics", "snodas-relative-qc-triage"),
    decisions_path = file.path("config", "snodas-seasonal-review-decisions.csv"),
    archive_root = file.path("data", "diagnostics", "snodas-seasonal-archive")) {
  files <- file.path(triage_dir, c("year-summary.csv",
                                  "candidate-evidence.csv",
                                  "known-mask-benchmarks.csv"))
  if (!all(file.exists(files)) || !file.exists(decisions_path)) {
    stop("Full SNODAS triage and tracked review decisions are required ",
         "before site staging.", call. = FALSE)
  }
  summary <- utils::read.csv(files[1L], stringsAsFactors = FALSE)
  peaks <- utils::read.csv(files[2L], stringsAsFactors = FALSE)
  benchmarks <- utils::read.csv(files[3L], stringsAsFactors = FALSE)
  decisions <- utils::read.csv(decisions_path, stringsAsFactors = FALSE)
  required_summary <- c("water_year", "archive_state",
                        "missing_evidence_episodes", "source_signature",
                        "peak_swe_md5", "quality_md5")
  required_peaks <- c("water_year", "cell", "peak_date",
                      "peak_swe_inches", "pilot_priority")
  required_benchmarks <- c("water_year", "cell", "rule_id",
                           "source_matched", "relative_detected",
                           "triage_priority")
  required_decisions <- c("water_year", "cell", "peak_date",
                          "peak_swe_inches", "source_signature",
                          "decision")
  if (!all(required_summary %in% names(summary)) ||
      !all(required_peaks %in% names(peaks)) ||
      !all(required_benchmarks %in% names(benchmarks)) ||
      !all(required_decisions %in% names(decisions)) ||
      !identical(sort(summary$water_year), 2005:2025) ||
      anyDuplicated(summary$water_year) ||
      anyNA(summary[, required_summary]) ||
      any(summary$archive_state != "OUTPUTS_VERIFIED") ||
      any(summary$missing_evidence_episodes != 0L)) {
    stop("Run the current full WY2005-WY2025 SNODAS relative triage ",
         "before site staging.", call. = FALSE)
  }
  verified <- lapply(2005:2025, snodas_historic_verify_output,
                     archive_root = archive_root)
  for (i in seq_along(verified)) {
    row <- summary[summary$water_year == i + 2004L, , drop = FALSE]
    marker <- verified[[i]]$marker
    if (!identical(row$source_signature, marker$source_signature) ||
        !identical(row$peak_swe_md5, marker$peak_swe_md5) ||
        !identical(row$quality_md5, marker$quality_md5)) {
      stop("SNODAS WY", i + 2004L,
           " changed after the triage scan; rerun it.", call. = FALSE)
    }
  }
  if (anyNA(benchmarks[, required_benchmarks]) ||
      !all(benchmarks$source_matched & benchmarks$relative_detected &
             benchmarks$triage_priority == "REVIEW_EVENT")) {
    stop("A documented SNODAS mask failed its triage benchmark.",
         call. = FALSE)
  }
  known_keys <- paste(benchmarks$water_year, benchmarks$cell)
  if (anyDuplicated(known_keys)) {
    stop("Duplicate SNODAS known-mask benchmark.", call. = FALSE)
  }
  for (i in seq_len(nrow(benchmarks))) {
    year <- benchmarks$water_year[i]
    rules <- snodas_seasonal_peak_qc_rules(year)
    if (!benchmarks$rule_id[i] %in% rules$rule_id) {
      stop("Unrecognized documented SNODAS mask rule.", call. = FALSE)
    }
    peak <- terra::rast(verified[[year - 2004L]]$paths[["peak_swe"]])
    if (!is.na(terra::values(peak, mat = FALSE)[benchmarks$cell[i]])) {
      stop("Documented SNODAS mask is absent from the seasonal map.",
           call. = FALSE)
    }
  }
  flagged <- peaks[peaks$pilot_priority %in%
                     c("REVIEW_EVENT", "NEEDS_EVIDENCE"), , drop = FALSE]
  if (any(flagged$pilot_priority == "NEEDS_EVIDENCE")) {
    stop("SNODAS triage still has missing-evidence cells.", call. = FALSE)
  }
  flagged_keys <- paste(flagged$water_year, flagged$cell)
  if (anyDuplicated(flagged_keys) ||
      !setequal(known_keys, flagged_keys[flagged_keys %in% known_keys])) {
    stop("Documented SNODAS masks do not match current review flags.",
         call. = FALSE)
  }
  unclassified <- flagged[!flagged_keys %in% known_keys, , drop = FALSE]
  decision_keys <- paste(decisions$water_year, decisions$cell)
  if (anyNA(decisions[, required_decisions]) ||
      anyDuplicated(decision_keys) ||
      !setequal(decision_keys,
                paste(unclassified$water_year, unclassified$cell)) ||
      any(decisions$decision != "retain")) {
    stop("Tracked SNODAS review decisions do not cover exactly the ",
         "current unclassified flags.", call. = FALSE)
  }
  index <- match(paste(unclassified$water_year, unclassified$cell),
                 decision_keys)
  signatures <- summary$source_signature[match(unclassified$water_year,
                                               summary$water_year)]
  if (any(decisions$peak_date[index] != unclassified$peak_date) ||
      any(abs(decisions$peak_swe_inches[index] -
                unclassified$peak_swe_inches) > 0.005) ||
      any(decisions$source_signature[index] != signatures)) {
    stop("A retained SNODAS cell changed since the reviewed decision.",
         call. = FALSE)
  }
  list(summary = summary, peaks = peaks, benchmarks = benchmarks,
       decisions = decisions, verified = verified)
}

snodas_historic_page_section <- function(water_year) {
  path <- paste0("../../maps/generated/snodas/seasonal-archive/wy",
                 water_year, "/")
  card <- function(label, filename, description) c(
    "::: {.dashboard-map-card}",
    paste0("![", label, "](", path, filename, ")"), "",
    "::: {.archive-map-description}", description, ":::", "",
    "::: {.dashboard-card-actions}",
    paste0("[Open full-resolution PNG](", path, filename,
           "){.btn .btn-sm .btn-outline-primary}"),
    ":::", ":::", "")
  c("<!-- BEGIN GENERATED SNODAS SNOW MAPS -->", "", "## Snow season", "",
    "October-May SNODAS model estimates. Peak SWE is the highest daily ",
    "snow-water equivalent; snow-covered days count dates with at least ",
    "0.1 inch SWE. Source gaps or screened cells may leave blank areas.", "",
    "::: {.dashboard-map-grid}",
    card("Peak snow water equivalent", "peak_swe.png",
         "Maximum daily SWE during October-May, in inches."),
    card("Snow-covered days", "snow_days.png",
         "Number of October-May days with SWE at least 0.1 inch."),
    ":::", "", "<!-- END GENERATED SNODAS SNOW MAPS -->")
}

write_snodas_historic_page_section <- function(
    water_year, page_dir = file.path("site", "pages", "archive")) {
  path <- file.path(page_dir, sprintf("wy%04d.qmd", water_year))
  if (!file.exists(path)) {
    stop("Missing Historic Years page: ", path, call. = FALSE)
  }
  lines <- readLines(path, warn = FALSE)
  begin <- which(lines == "<!-- BEGIN GENERATED SNODAS SNOW MAPS -->")
  end <- which(lines == "<!-- END GENERATED SNODAS SNOW MAPS -->")
  if (length(begin) > 1L || length(end) > 1L ||
      length(begin) != length(end) ||
      (length(begin) && begin >= end)) {
    stop("Malformed SNODAS section in ", path, call. = FALSE)
  }
  if (length(begin)) lines <- lines[-seq.int(begin, end)]
  while (length(lines) && !nzchar(trimws(lines[[length(lines)]]))) {
    lines <- lines[-length(lines)]
  }
  updated <- c(lines, "", snodas_historic_page_section(water_year))
  writeLines(updated, path, useBytes = TRUE)
  path
}

plan_snodas_historic_site <- function(
    years = 2005:2025,
    site_maps_root = file.path("site", "maps", "generated", "snodas",
                               "seasonal-archive"),
    page_dir = file.path("site", "pages", "archive"),
    ...) {
  years <- validate_snodas_seasonal_archive_years(years)
  reviewed <- snodas_historic_validate_triage(...)
  rows <- lapply(years, function(year) {
    year_dir <- file.path(site_maps_root, sprintf("wy%04d", year))
    source <- reviewed$verified[[year - 2004L]]
    destinations <- file.path(year_dir, c("peak_swe.png", "snow_days.png"))
    source_paths <- source$paths[c("peak_map", "snow_days_map")]
    current <- file.exists(destinations)
    current[current] <- unname(tools::md5sum(destinations[current])) ==
      unname(tools::md5sum(source_paths[current]))
    data.frame(water_year = year, quality_status = source$quality$status,
               maps_to_copy = sum(!current),
               page_exists = file.exists(file.path(
                 page_dir, sprintf("wy%04d.qmd", year))),
               stringsAsFactors = FALSE)
  })
  plan <- do.call(rbind, rows)
  if (any(!plan$page_exists)) {
    stop("Build the PRISM Historic Years pages before SNODAS staging.",
         call. = FALSE)
  }
  rownames(plan) <- NULL
  plan
}

stage_snodas_historic_site <- function(
    years = 2005:2025, dry_run = TRUE,
    site_maps_root = file.path("site", "maps", "generated", "snodas",
                               "seasonal-archive"),
    page_dir = file.path("site", "pages", "archive"),
    archive_root = file.path("data", "diagnostics", "snodas-seasonal-archive"),
    triage_dir = file.path("data", "diagnostics", "snodas-relative-qc-triage"),
    decisions_path = file.path("config", "snodas-seasonal-review-decisions.csv")) {
  if (!is.logical(dry_run) || length(dry_run) != 1L || is.na(dry_run)) {
    stop("`dry_run` must be TRUE or FALSE.", call. = FALSE)
  }
  plan <- plan_snodas_historic_site(
    years, site_maps_root, page_dir, triage_dir = triage_dir,
    decisions_path = decisions_path, archive_root = archive_root)
  if (dry_run) {
    message("SNODAS Historic Years staging preview only; no files changed.")
    return(plan)
  }
  years <- plan$water_year
  for (year in years) {
    source <- snodas_historic_source_paths(year, archive_root)
    destination_dir <- file.path(site_maps_root,
                                 sprintf("wy%04d", year))
    dir.create(destination_dir, recursive = TRUE, showWarnings = FALSE)
    filenames <- c(peak_map = "peak_swe.png",
                   snow_days_map = "snow_days.png")
    for (key in names(filenames)) {
      from <- source[[key]]
      to <- file.path(destination_dir, filenames[[key]])
      if (!file.exists(to) ||
          !identical(unname(tools::md5sum(from)),
                     unname(tools::md5sum(to)))) {
        if (!file.copy(from, to, overwrite = TRUE) ||
            !identical(unname(tools::md5sum(from)),
                       unname(tools::md5sum(to)))) {
          stop("Could not stage SNODAS image: ", to, call. = FALSE)
        }
      }
    }
    write_snodas_historic_page_section(year, page_dir)
    message("Staged SNODAS Historic Years maps for WY", year, ".")
  }
  plan
}
