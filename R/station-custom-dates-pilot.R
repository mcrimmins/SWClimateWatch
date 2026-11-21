# Static annual chunks for a selected-station-only local pilot. No downloads.
station_custom_pilot_root <- function() "data/diagnostics/station-custom-dates-pilot"
station_custom_codes <- c(MISSING = 0L, AVAILABLE = 1L, TRACE = 2L, FLAGGED = 3L)
station_custom_values <- function(value) {
  if (is.list(value)) vapply(value, function(x) if (is.null(x)) NA_real_ else as.numeric(x), numeric(1)) else as.numeric(value)
}
station_custom_year_signature <- function(raw, cutoff, policy) {
  rownames(raw) <- NULL
  raw$date <- as.numeric(raw$date)
  digest::digest(list(policy, raw, as.numeric(cutoff)))
}

station_custom_write_json <- function(value, path) {
  bytes <- jsonlite::toJSON(value, auto_unbox = TRUE, digits = NA, na = "null", null = "null")
  hash <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!file.exists(path) || !identical(readLines(path, warn = FALSE), as.character(bytes)))
    writeLines(bytes, path, useBytes = TRUE)
  list(hash = hash, bytes = unname(file.info(path)$size))
}

station_custom_chunk <- function(station, cache, year) {
  end <- min(cache$as_of, as.Date(sprintf("%d-12-31", year)))
  start <- max(min(cache$daily$date), as.Date(sprintf("%d-01-01", year)))
  if (start > end) stop("Invalid station year.")
  cache$daily <- cache$daily[cache$daily$date >= start & cache$daily$date <= end, ]
  detail <- acis_station_explorer_daily_detail(station, cache, end, full_record = TRUE)$daily
  # Trace observations have zero measured inches, but keep their explicit status.
  traces <- cache$daily[cache$daily$variable == "pcpn" & cache$daily$trace %in% TRUE, "date"]
  detail$pcpn_status[detail$date %in% as.character(traces) & detail$pcpn_status == "AVAILABLE"] <- "TRACE"
  if (!identical(detail$date, as.character(seq.Date(start, end, "day")))) stop("Annual station dates are misaligned.")
  fields <- c("pcpn", "maxt", "mint")
  result <- list(schema = 1L, uid = as.integer(station$uid), year = as.integer(year),
    start = as.character(start), end = as.character(end), n = nrow(detail))
  for (field in fields) {
    result[[field]] <- unname(detail[[field]])
    result[[paste0(field, "_status")]] <- unname(station_custom_codes[detail[[paste0(field, "_status")]]])
  }
  result
}

station_custom_summary <- function(chunks, start, end) {
  days <- do.call(rbind, lapply(chunks, function(chunk) data.frame(
    date = seq.Date(as.Date(chunk$start), as.Date(chunk$end), "day"),
    pcpn = station_custom_values(chunk$pcpn), maxt = station_custom_values(chunk$maxt), mint = station_custom_values(chunk$mint),
    pcpn_status = unlist(chunk$pcpn_status), maxt_status = unlist(chunk$maxt_status), mint_status = unlist(chunk$mint_status))))
  days <- days[days$date >= as.Date(start) & days$date <= as.Date(end), ]
  if (nrow(days) != as.integer(as.Date(end) - as.Date(start)) + 1L || anyDuplicated(days$date)) stop("Incomplete custom period input.")
  paired <- is.finite(days$maxt) & is.finite(days$mint)
  list(days = nrow(days), precipitation = if (any(is.finite(days$pcpn))) sum(days$pcpn, na.rm = TRUE) else NA_real_,
    precipitation_valid = sum(is.finite(days$pcpn)), precipitation_flagged = sum(days$pcpn_status == 3L),
    precipitation_trace = sum(days$pcpn_status == 2L), paired_days = sum(paired),
    mean_temperature = if (any(paired)) mean((days$maxt[paired] + days$mint[paired]) / 2) else NA_real_)
}

build_station_custom_dates_pilot <- function(stations = acis_reference_station_table(),
    cache_dir = "data/processed/acis-stations/reference-network/daily", output_dir = station_custom_pilot_root()) {
  started <- proc.time()[["elapsed"]]
  if (!nrow(stations) || anyNA(stations$uid) || anyDuplicated(stations$uid) || any(!grepl("^[0-9]+$", as.character(stations$uid)))) stop("Supply unique numeric station UIDs.")
  parent <- normalizePath(dirname(output_dir), winslash = "/", mustWork = TRUE)
  root <- file.path(parent, basename(output_dir))
  allowed <- paste0(tolower(normalizePath("data/diagnostics", winslash = "/", mustWork = TRUE)), "/")
  if (basename(output_dir) %in% c(".", "..") || !startsWith(tolower(root), allowed)) stop("Pilot output must remain within data/diagnostics.")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  lock <- filelock::lock(file.path(root, "build.lock"), timeout = 0)
  if (is.null(lock)) stop("Another custom-date pilot build is running.")
  on.exit(filelock::unlock(lock), add = TRUE)
  write.csv(data.frame(status = "BUILDING"), file.path(root, "update-summary.csv"), row.names = FALSE)
  # Source-reference environments differ between RStudio, Rscript and the
  # isolated daily loader. Hash code text so an unchanged policy reuses data.
  policy <- station_custom_policy_signature()
  records <- list(); reports <- list()
  for (i in seq_len(nrow(stations))) {
    station <- stations[i, ]; uid <- station$uid
    path <- acis_station_daily_cache_path(uid, cache_dir)
    if (!file.exists(path)) stop("Missing station cache: ", uid)
    source_hash <- unname(tools::md5sum(path))
    folder <- file.path(root, "history", uid); dir.create(folder, recursive = TRUE, showWarnings = FALSE)
    marker <- file.path(folder, "build.rds")
    old <- if (file.exists(marker)) tryCatch(readRDS(marker), error = function(e) NULL) else NULL
    metadata <- as.list(station[c("uid", "sid", "name", "state", "role")])
    same <- is.list(old) && identical(old$policy, policy) && identical(old$source_hash, source_hash) && identical(old$metadata, metadata)
    if (same && all(file.exists(file.path(root, old$files))) && identical(unname(tools::md5sum(file.path(root, old$files))), old$md5)) {
      # Earlier local pilot markers used Date's storage representation. Upgrade
      # only metadata; the verified annual payload bytes remain unchanged.
      if (!identical(old$hash_version, 3L)) {
        cache <- acis_station_read_daily_cache(path, uid)
        if (is.null(cache)) stop("Invalid station cache: ", uid)
        raw_years <- as.integer(format(cache$daily$date, "%Y"))
        for (j in seq_len(nrow(old$years))) {
          year <- old$years$year[j]
          old$years$signature[j] <- station_custom_year_signature(cache$daily[raw_years == year, ],
            min(cache$as_of, as.Date(sprintf("%d-12-31", year))), policy)
        }
        old$hash_version <- 3L; saveRDS(old, marker)
      }
      records[[i]] <- old$catalog
      reports[[i]] <- data.frame(uid = uid, years = nrow(old$years), built = 0L, reused = nrow(old$years), source_reused = TRUE)
      message("[", i, "/", nrow(stations), "] ", station$name, ": cached ", nrow(old$years), " years")
      next
    }
    cache <- acis_station_read_daily_cache(path, uid)
    if (is.null(cache)) stop("Invalid daily cache: ", uid)
    if (is.list(old$catalog) && (min(cache$daily$date) > as.Date(old$catalog$first) || cache$as_of < as.Date(old$catalog$last)))
      stop("Refusing to shorten an existing historical station record: ", uid)
    raw_years <- as.integer(format(cache$daily$date, "%Y"))
    years <- seq.int(as.integer(format(min(cache$daily$date), "%Y")), as.integer(format(cache$as_of, "%Y")))
    rows <- list(); built <- reused <- 0L
    for (year in years) {
      raw <- cache$daily[raw_years == year, ]
      # Appending a Date can change integer storage to double without changing
      # any historical day. Hash semantic dates, not that storage detail.
      signature <- station_custom_year_signature(raw, min(cache$as_of, as.Date(sprintf("%d-12-31", year))), policy)
      saved <- if (is.list(old) && is.data.frame(old$years)) old$years[old$years$year == year, ] else data.frame()
      if (nrow(saved) == 1L && identical(saved$signature, signature) && file.exists(file.path(root, saved$file)) &&
          identical(unname(tools::md5sum(file.path(root, saved$file))), saved$md5)) {
        rows[[length(rows) + 1L]] <- saved; reused <- reused + 1L; next
      }
      chunk <- station_custom_chunk(station, cache, year)
      json <- jsonlite::toJSON(chunk, auto_unbox = TRUE, digits = NA, na = "null")
      hash <- substr(digest::digest(json, serialize = FALSE, algo = "sha256"), 1, 16)
      relative <- paste0("history/", uid, "/", year, "-", hash, ".json")
      if (!file.exists(file.path(root, relative)) || !identical(readLines(file.path(root, relative), warn = FALSE), as.character(json)))
        writeLines(json, file.path(root, relative), useBytes = TRUE)
      rows[[length(rows) + 1L]] <- data.frame(year = year, start = chunk$start, end = chunk$end, days = chunk$n,
        file = relative, bytes = unname(file.info(file.path(root, relative))$size), signature = signature,
        md5 = unname(tools::md5sum(file.path(root, relative))))
      built <- built + 1L
    }
    rows <- do.call(rbind, rows)
    if (!identical(unname(tools::md5sum(path)), source_hash)) stop("Station cache changed during the build: ", uid, ". Rerun the pilot.")
    index <- c(metadata, list(first = min(rows$start), last = max(rows$end), cutoff = as.character(cache$as_of),
      status_codes = as.list(station_custom_codes), years = rows[c("year", "start", "end", "days", "file", "bytes", "md5")]))
    json <- jsonlite::toJSON(index, auto_unbox = TRUE, dataframe = "rows", digits = NA)
    index_file <- paste0("history/", uid, "/index-", substr(digest::digest(json, serialize = FALSE), 1, 16), ".json")
    writeLines(json, file.path(root, index_file), useBytes = TRUE)
    catalog <- c(metadata, list(first = index$first, last = index$last, index = index_file,
      years = nrow(rows), bytes = sum(rows$bytes)))
    files <- c(rows$file, index_file)
    saveRDS(list(policy = policy, hash_version = 3L, source_hash = source_hash, metadata = metadata, years = rows, catalog = catalog,
      files = files, md5 = unname(tools::md5sum(file.path(root, files)))), marker)
    # Prune only obsolete generated JSON files inside this station's pilot folder.
    existing <- list.files(folder, pattern = "^([0-9]{4}-|index-)[a-f0-9]+[.]json$", full.names = TRUE)
    obsolete <- existing[!basename(existing) %in% basename(files)]
    if (length(obsolete)) unlink(obsolete)
    records[[i]] <- catalog
    reports[[i]] <- data.frame(uid = uid, years = nrow(rows), built = built, reused = reused, source_reused = FALSE)
    message("[", i, "/", nrow(stations), "] ", station$name, ": ", built, " years built, ", reused, " reused")
  }
  station_custom_write_json(list(schema = 1L, stations = records), file.path(root, "catalog.json"))
  for (file in c("index.html", "model.js", "worker.js", "app.js", "styles.css")) {
    from <- file.path("scripts/station-custom-dates-assets", file); to <- file.path(root, file)
    if (!file.exists(to) || !identical(unname(tools::md5sum(from)), unname(tools::md5sum(to)))) file.copy(from, to, overwrite = TRUE)
  }
  reports <- do.call(rbind, reports)
  write.csv(reports, file.path(root, "last-batch.csv"), row.names = FALSE)
  summary <- data.frame(status = "READY", stations = nrow(reports), years = sum(reports$years), built = sum(reports$built),
    reused = sum(reports$reused), requests = 0L, payload_bytes = sum(vapply(records, function(x) x$bytes, numeric(1))),
    catalog_bytes = file.info(file.path(root, "catalog.json"))$size, seconds = round(proc.time()[["elapsed"]] - started, 3))
  write.csv(summary, file.path(root, "update-summary.csv"), row.names = FALSE)
  list(summary = summary, root = root)
}

station_custom_policy_signature <- function() {
  code <- lapply(list(acis_station_explorer_daily_detail, station_custom_chunk),
    function(f) paste(deparse(body(f),width.cutoff=500L),collapse="\n"))
  digest::digest(list("station-history-code-policy-v2",code,station_custom_codes))
}
