# Research crosswalk between a Climate Perspectives CSV export and ACIS.
# Source acis-station-inventory.R first. Nothing in this module publishes maps.

acis_reference_read <- function(path) {
  if (!file.exists(path)) stop("Reference export does not exist: ", path, call. = FALSE)
  lines <- readLines(path, warn = FALSE)
  header <- grep('^"Station","Name",', lines)
  if (length(header) != 1L) {
    stop("Expected one Climate Perspectives station header in ", path, call. = FALSE)
  }
  source <- read.csv(path, skip = header - 1L, colClasses = "character",
                     check.names = FALSE, stringsAsFactors = FALSE)
  required <- c("Station", "Name", "State", "Lat", "Lon")
  if (!all(required %in% names(source))) {
    stop("Reference export is missing station identity or coordinates: ", path,
         call. = FALSE)
  }
  if (anyNA(source$Station) || any(!nzchar(source$Station)) ||
      anyDuplicated(source$Station)) {
    stop("Reference export has missing or repeated station IDs: ", path,
         call. = FALSE)
  }
  result <- data.frame(
    reference_id = source$Station,
    reference_name = source$Name,
    state = source$State,
    reference_longitude = suppressWarnings(as.numeric(source$Lon)),
    reference_latitude = suppressWarnings(as.numeric(source$Lat)),
    stringsAsFactors = FALSE
  )
  if (anyNA(result$reference_longitude) || anyNA(result$reference_latitude)) {
    stop("Reference export has missing or invalid station coordinates: ", path,
         call. = FALSE)
  }
  result
}

acis_reference_roster <- function(paths, bbox = swc_region$bbox) {
  if (!length(paths) || anyNA(paths) || any(!nzchar(paths))) {
    stop("Provide at least one Climate Perspectives CSV export.", call. = FALSE)
  }
  exports <- lapply(paths, acis_reference_read)
  ids <- unique(unlist(lapply(exports, `[[`, "reference_id"), use.names = FALSE))
  combined <- do.call(rbind, exports)
  combined <- combined[match(ids, combined$reference_id), , drop = FALSE]
  combined$exports_present <- vapply(ids, function(id) {
    sum(vapply(exports, function(x) id %in% x$reference_id, logical(1)))
  }, integer(1))
  for (id in ids) {
    occurrences <- do.call(rbind, lapply(exports, function(x)
      x[x$reference_id == id, c("state", "reference_longitude",
                                  "reference_latitude"), drop = FALSE]))
    if (length(unique(occurrences$state)) != 1L ||
        diff(range(occurrences$reference_longitude)) > 0.01 ||
        diff(range(occurrences$reference_latitude)) > 0.01) {
      stop("Reference exports disagree on identity or location for ", id,
           call. = FALSE)
    }
  }
  inside <- with(combined,
                 reference_longitude >= bbox[["west"]] &
                   reference_longitude <= bbox[["east"]] &
                   reference_latitude >= bbox[["south"]] &
                   reference_latitude <= bbox[["north"]])
  combined <- combined[inside, , drop = FALSE]
  combined <- combined[order(combined$state, combined$reference_name,
                             combined$reference_id), , drop = FALSE]
  rownames(combined) <- NULL
  combined
}

acis_reference_match <- function(station, metadata) {
  possible <- which(vapply(metadata, function(record) {
    station$reference_id %in% sub(" [0-9]+$", "",
      as.character(unlist(record$sids, use.names = FALSE))) &&
      identical(as.character(record$state), as.character(station$state))
  }, logical(1)))
  if (!length(possible)) return(list(uid = NA_integer_, method = "NO_ACIS_MATCH"))
  if (length(possible) == 1L) {
    return(list(uid = as.integer(metadata[[possible]]$uid), method = "ID_AND_STATE"))
  }
  distance <- vapply(possible, function(index) {
    ll <- as.numeric(unlist(metadata[[index]]$ll, use.names = FALSE))
    if (length(ll) < 2L || anyNA(ll)) return(Inf)
    sqrt(((ll[[1L]] - station$reference_longitude) *
            cos(station$reference_latitude * pi / 180))^2 +
           (ll[[2L]] - station$reference_latitude)^2)
  }, numeric(1))
  if (all(!is.finite(distance)) || min(distance) > 0.05 ||
      sum(abs(distance - min(distance)) < 1e-8) != 1L) {
    return(list(uid = NA_integer_, method = "AMBIGUOUS_ACIS_ID"))
  }
  list(uid = as.integer(metadata[[possible[[which.min(distance)]]]]$uid),
       method = "ID_STATE_AND_COORDINATES")
}

acis_reference_network <- function(roster, metadata, shortlist_uids = integer(),
                                   pilot_uids = integer(), coverage_dir,
                                   today = Sys.Date(), recent_within_days = 730L) {
  stopifnot(inherits(today, "Date"), recent_within_days > 0L)
  min_years <- 20L
  through_year <- as.integer(format(today, "%Y")) - 1L
  candidates <- acis_station_candidates(metadata, today = today)
  output <- lapply(seq_len(nrow(roster)), function(index) {
    station <- roster[index, , drop = FALSE]
    matched <- acis_reference_match(station, metadata)
    candidate <- candidates[match(matched$uid, candidates$uid), , drop = FALSE]
    known <- !is.na(matched$uid) && nrow(candidate) == 1L &&
      !is.na(candidate$uid[[1L]])
    threadex <- if (known) candidate$threadex[[1L]] else NA
    result <- cbind(station, data.frame(
      acis_uid = matched$uid, match_method = matched$method,
      acis_sid = if (known) candidate$sid[[1L]] else NA_character_,
      acis_name = if (known) candidate$name[[1L]] else NA_character_,
      threadex = threadex,
      map_longitude = if (known && !threadex) candidate$longitude[[1L]] else NA_real_,
      map_latitude = if (known && !threadex) candidate$latitude[[1L]] else NA_real_,
      in_long_record_shortlist = known && matched$uid %in% shortlist_uids,
      in_daily_pilot = known && matched$uid %in% pilot_uids,
      stringsAsFactors = FALSE
    ))
    coverage <- NULL
    if (known) {
      path <- file.path(coverage_dir, paste0(matched$uid, ".csv"))
      if (acis_station_coverage_cache_current(path, through_year)) {
        coverage <- read.csv(path, stringsAsFactors = FALSE)
      }
    }
    result$annual_audit <- if (!known) "UNMATCHED" else if (is.null(coverage))
      "PENDING" else "AUDITED"
    for (variable in swc_acis_station_variables) {
      dates <- if (known) as.Date(c(candidate[[paste0(variable, "_start")]],
                                     candidate[[paste0(variable, "_end")]])) else
        as.Date(c(NA_character_, NA_character_))
      span <- as.numeric(diff(dates)) / 365.25
      recent <- as.numeric(today - dates[[2L]]) <= recent_within_days
      result[[paste0(variable, "_metadata_20year_screen")]] <-
        known && is.finite(span) && span >= min_years && !is.na(recent) && recent
      part <- if (!is.null(coverage)) coverage[coverage$variable == variable &
                                                coverage$coverage >= 0.9, ] else NULL
      result[[paste0(variable, "_years_90pct")]] <-
        if (is.null(part)) NA_integer_ else nrow(part)
      result[[paste0(variable, "_20year_annual_screen")]] <-
        if (!result[[paste0(variable, "_metadata_20year_screen")]]) FALSE else
          if (is.null(part)) NA else nrow(part) >= min_years
      result[[paste0(variable, "_normal_years_90pct")]] <-
        if (is.null(part)) NA_integer_ else sum(part$year >= 1991L & part$year <= 2020L)
      result[[paste0(variable, "_recent10_years_90pct")]] <-
        if (is.null(part)) NA_integer_ else sum(part$year >= through_year - 9L &
                                                  part$year <= through_year)
    }
    result
  })
  result <- do.call(rbind, output)
  rownames(result) <- NULL
  result
}

acis_reference_missing_threadex <- function(roster, metadata,
                                             fetch = acis_station_fetch) {
  unmatched <- roster$reference_id[vapply(seq_len(nrow(roster)), function(index) {
    is.na(acis_reference_match(roster[index, , drop = FALSE], metadata)$uid)
  }, logical(1))]
  ids <- unmatched[grepl("thr$", unmatched, ignore.case = TRUE)]
  if (!length(ids)) return(list())
  fields <- c("uid", "name", "state", "ll", "elev", "sids", "valid_daterange")
  response <- fetch("StnMeta", list(sids = paste(ids, "9"),
                                     elems = swc_acis_station_variables,
                                     meta = fields))
  records <- response$meta
  if (is.null(records)) stop("ACIS did not return ThreadEx metadata.", call. = FALSE)
  records
}

run_acis_reference_network <- function(reference_paths, max_new_stations = 0L,
                                       today = Sys.Date(),
                                       directory = swc_acis_station_dir,
                                       fetch = acis_station_fetch,
                                       refresh_missing_threadex = FALSE) {
  stopifnot(inherits(today, "Date"), length(max_new_stations) == 1L,
            is.finite(max_new_stations), max_new_stations >= 0L)
  metadata_path <- file.path(directory, "metadata.rds")
  if (!file.exists(metadata_path)) stop("Run the ACIS station inventory first.")
  metadata <- readRDS(metadata_path)
  roster <- acis_reference_roster(reference_paths)
  output_dir <- file.path(directory, "reference-network")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  extra_path <- file.path(output_dir, "extra-metadata.rds")
  extra <- if (file.exists(extra_path)) readRDS(extra_path) else list()
  metadata <- c(metadata, extra)
  if (refresh_missing_threadex) {
    found <- acis_reference_missing_threadex(roster, metadata, fetch)
    if (length(found)) {
      existing_uids <- vapply(metadata, function(x) as.character(x$uid), character(1))
      found <- found[!vapply(found, function(x) as.character(x$uid) %in% existing_uids,
                              logical(1))]
      extra <- c(extra, found)
      saveRDS(extra, extra_path)
      metadata <- c(metadata, found)
    }
  }
  coverage_dir <- file.path(directory, "annual-coverage")
  dir.create(coverage_dir, recursive = TRUE, showWarnings = FALSE)
  shortlist_path <- file.path(directory, "station-shortlist.csv")
  pilot_path <- file.path(directory, "daily-pilot", "pilot-stations.csv")
  shortlist_uids <- if (file.exists(shortlist_path))
    read.csv(shortlist_path)$uid else integer()
  pilot_uids <- if (file.exists(pilot_path))
    read.csv(pilot_path)$uid else integer()
  report <- acis_reference_network(roster, metadata, shortlist_uids, pilot_uids,
                                   coverage_dir, today)
  pending <- unique(report$acis_uid[report$annual_audit == "PENDING"])
  scheduled <- head(pending, as.integer(max_new_stations))
  message(sprintf("ACIS reference network: %d footprint IDs; %d matched; %d annual audits pending; %d scheduled.",
                  nrow(report), sum(!is.na(report$acis_uid)), length(pending),
                  length(scheduled)))
  candidates <- acis_station_candidates(metadata, today = today)
  failures <- character()
  through_year <- as.integer(format(today, "%Y")) - 1L
  for (uid in scheduled) {
    station <- candidates[candidates$uid == uid, , drop = FALSE]
    message(sprintf("Auditing reference station %s (%s).", station$name, station$sid))
    tryCatch({
      coverage <- acis_station_annual_coverage(station, through_year, fetch)
      write.csv(coverage, file.path(coverage_dir, paste0(uid, ".csv")),
                row.names = FALSE)
    }, error = function(e) {
      failures <<- c(failures, sprintf("%s: %s", station$sid, conditionMessage(e)))
      message("  Audit failed: ", conditionMessage(e))
    })
  }
  if (length(scheduled)) {
    report <- acis_reference_network(roster, metadata, shortlist_uids, pilot_uids,
                                     coverage_dir, today)
  }
  output_path <- file.path(output_dir, "network.csv")
  write.csv(report, output_path, row.names = FALSE)
  list(network = report,
       pending = length(unique(report$acis_uid[report$annual_audit == "PENDING"])),
       audited_this_run = length(scheduled) - length(failures), failures = failures,
       path = output_path)
}
