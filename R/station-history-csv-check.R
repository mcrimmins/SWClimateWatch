check_station_history_csv <- function(path, history_root = "data/diagnostics/station-history-integration/custom-history") {
  name <- basename(path)
  match <- regmatches(name, regexec("^station-([0-9]+)-([0-9-]{10})-to-([0-9-]{10})(?: \\([0-9]+\\))?[.]csv$", name))[[1L]]
  if (length(match) != 4L) stop("Choose a station history CSV with its original download filename.")
  uid <- match[2L]; start <- as.Date(match[3L]); end <- as.Date(match[4L])
  catalog <- jsonlite::read_json(file.path(history_root, "catalog.json"), simplifyVector = TRUE)$stations
  station <- catalog[catalog$uid == uid, ]
  if (nrow(station) != 1L) stop("Unknown station in CSV filename.")
  index <- jsonlite::read_json(file.path(history_root, station$index), simplifyVector = TRUE)
  years <- index$years[index$years$end >= start & index$years$start <= end, ]
  nullable <- function(v) if (is.list(v)) vapply(v, function(x) if (is.null(x)) NA_real_ else as.numeric(x), numeric(1)) else as.numeric(v)
  expected <- do.call(rbind, lapply(years$file, function(file) {
    x <- jsonlite::read_json(file.path(history_root, file))
    data.frame(date = as.character(seq.Date(as.Date(x$start), as.Date(x$end), "day")),
      precipitation_inches = nullable(x$pcpn), high_f = nullable(x$maxt), low_f = nullable(x$mint),
      precipitation_status = unlist(x$pcpn_status), high_status = unlist(x$maxt_status), low_status = unlist(x$mint_status))
  }))
  expected <- expected[expected$date >= start & expected$date <= end, ]
  csv <- read.csv(path, colClasses = "character", fileEncoding = "UTF-8-BOM", check.names = FALSE, na.strings = "")
  columns <- c("station_uid", "station_id", "station_name", "date", "precipitation_inches", "high_f", "low_f", "precipitation_status", "high_status", "low_status")
  stopifnot(identical(names(csv), columns), nrow(csv) == as.integer(end-start)+1L,
    identical(csv$date, as.character(seq.Date(start,end,"day"))), all(csv$station_uid == uid),
    all(csv$station_id == station$sid), all(csv$station_name == station$name))
  labels <- c("MISSING", "AVAILABLE", "TRACE", "FLAGGED")
  for (field in c("precipitation_inches", "high_f", "low_f")) stopifnot(identical(as.numeric(csv[[field]]), expected[[field]]))
  for (field in c("precipitation_status", "high_status", "low_status")) stopifnot(identical(csv[[field]], labels[expected[[field]]+1L]))
  data.frame(status = "PASS", file = name, rows = nrow(csv), trace = sum(csv$precipitation_status == "TRACE"),
    missing_values = sum(is.na(csv[c("precipitation_inches","high_f","low_f")])),
    flagged_values = sum(as.matrix(csv[c("precipitation_status","high_status","low_status")]) == "FLAGGED"))
}

validate_station_history_csv_download <- function(path = file.choose()) {
  result <- check_station_history_csv(path)
  print(result, row.names = FALSE)
  invisible(result)
}
