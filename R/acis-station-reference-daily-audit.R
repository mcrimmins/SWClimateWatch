# Resumable daily-quality review for the broad ACIS reference network.
# Source acis-station-inventory.R, acis-station-daily-pilot.R, and
# acis-station-reference-network.R first. No public product is changed.

acis_reference_daily_stations <- function(network, metadata) {
  required <- c("acis_uid", "reference_id", "annual_audit")
  if (!all(required %in% names(network))) {
    stop("The reference network report is missing ACIS identity columns.")
  }
  matched <- network[!is.na(network$acis_uid) &
                       network$annual_audit == "AUDITED", , drop = FALSE]
  uids <- unique(as.integer(matched$acis_uid))
  if (!length(uids)) stop("No annually audited ACIS records in the reference network.")
  candidates <- acis_station_candidates(metadata)
  index <- match(uids, candidates$uid)
  if (anyNA(index)) stop("Reference UID missing from cached ACIS metadata.")
  stations <- candidates[index, , drop = FALSE]
  stations$role <- ifelse(stations$threadex, "threadex_comparison", "fixed")
  stations$reference_ids <- vapply(uids, function(uid) {
    paste(matched$reference_id[matched$acis_uid == uid], collapse = ",")
  }, character(1))
  rownames(stations) <- NULL
  stations
}

acis_reference_daily_cache <- function(path) {
  if (!file.exists(path)) return(NULL)
  value <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!is.list(value) || !identical(value$schema_version, 1L) ||
      !all(c("summary", "annual", "monthly", "sources", "flags", "checks") %in%
           names(value))) return(NULL)
  value
}

run_acis_reference_daily_audit <- function(
    max_new_stations = 5L, today = Sys.Date(),
    directory = swc_acis_station_dir,
    fetch = acis_station_fetch, refresh_uids = integer()) {
  stopifnot(inherits(today, "Date"), length(max_new_stations) == 1L,
            is.finite(max_new_stations), max_new_stations >= 0L)
  network_path <- file.path(directory, "reference-network", "network.csv")
  metadata_path <- file.path(directory, "metadata.rds")
  if (!file.exists(network_path) || !file.exists(metadata_path)) {
    stop("Complete the ACIS reference-network annual audit first.")
  }
  network <- read.csv(network_path, stringsAsFactors = FALSE)
  metadata <- readRDS(metadata_path)
  extra_path <- file.path(directory, "reference-network", "extra-metadata.rds")
  if (file.exists(extra_path)) metadata <- c(metadata, readRDS(extra_path))
  stations <- acis_reference_daily_stations(network, metadata)
  output_dir <- file.path(directory, "reference-network", "daily-audit")
  cache_dir <- file.path(output_dir, "station-summaries")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  pilot_dir <- file.path(directory, "daily-pilot", "station-summaries")
  paths <- file.path(cache_dir, paste0(stations$uid, ".rds"))
  pilot_paths <- file.path(pilot_dir, paste0(stations$uid, ".rds"))
  cached <- lapply(seq_len(nrow(stations)), function(index) {
    value <- acis_reference_daily_cache(paths[[index]])
    if (is.null(value)) value <- acis_reference_daily_cache(pilot_paths[[index]])
    value
  })
  pending <- which(vapply(cached, is.null, logical(1)) |
                     stations$uid %in% refresh_uids)
  scheduled <- head(pending, as.integer(max_new_stations))
  message(sprintf("ACIS reference daily audit: %d unique records; %d pending; %d scheduled.",
                  nrow(stations), length(pending), length(scheduled)))
  failures <- character()
  for (index in scheduled) {
    station <- stations[index, , drop = FALSE]
    message(sprintf("Daily review %s (%s).", station$name, station$sid))
    tryCatch({
      daily <- acis_station_daily_values(station, today, fetch)
      value <- acis_station_daily_summaries(daily, station, today)
      value$schema_version <- 1L
      saveRDS(value, paths[[index]])
      cached[[index]] <- value
      rm(daily, value)
    }, error = function(e) {
      failures <<- c(failures, sprintf("%s: %s", station$sid, conditionMessage(e)))
      message("  Audit failed: ", conditionMessage(e))
    })
  }
  present <- which(!vapply(cached, is.null, logical(1)))
  for (table in c("summary", "annual", "monthly", "sources", "flags", "checks")) {
    value <- if (length(present)) do.call(rbind, lapply(cached[present], `[[`, table))
      else data.frame()
    write.csv(value, file.path(output_dir, paste0(table, ".csv")), row.names = FALSE)
  }
  stations$daily_status <- ifelse(seq_len(nrow(stations)) %in% present,
                                  "AUDITED", "PENDING")
  stations$summary_as_of <- vapply(seq_len(nrow(stations)), function(index) {
    if (is.null(cached[[index]])) return(NA_character_)
    as.character(cached[[index]]$summary$as_of[[1L]])
  }, character(1))
  write.csv(stations, file.path(output_dir, "stations.csv"), row.names = FALSE)
  list(stations = stations, pending = sum(stations$daily_status == "PENDING"),
       audited_this_run = length(scheduled) - length(failures), failures = failures,
       directory = output_dir)
}
