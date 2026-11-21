source("scripts/load-station-custom-dates-pilot.R")
root <- station_custom_pilot_root()
summary <- read.csv(file.path(root, "update-summary.csv"))
if (!identical(summary$status, "READY")) stop("Complete the pilot build before checking it.")
catalog <- jsonlite::read_json(file.path(root, "catalog.json"), simplifyVector = FALSE)
fixtures <- list(); maximum_bytes <- 0; checked <- 0L
for (station in catalog$stations) {
  marker <- readRDS(file.path(root, "history", station$uid, "build.rds"))
  if (!identical(unname(tools::md5sum(file.path(root, marker$files))), marker$md5)) stop("Pilot file checksum mismatch: ", station$uid)
  index <- jsonlite::read_json(file.path(root, station$index), simplifyVector = TRUE)
  if (index$uid != station$uid || anyDuplicated(index$years$year) ||
      !identical(index$years$year, seq.int(as.integer(substr(index$first, 1, 4)), as.integer(substr(index$last, 1, 4))))) stop("Station year coverage is inconsistent.")
  for (i in seq_len(nrow(index$years))) {
    row <- index$years[i, ]; chunk <- jsonlite::read_json(file.path(root, row$file), simplifyVector = TRUE)
    if (chunk$uid != index$uid || chunk$start != row$start || chunk$end != row$end ||
        chunk$n != as.integer(as.Date(chunk$end) - as.Date(chunk$start)) + 1L) stop("Annual chunk dates differ from the index.")
    for (field in c("pcpn", "maxt", "mint")) {
      value <- station_custom_values(chunk[[field]]); status <- unlist(chunk[[paste0(field, "_status")]])
      if (length(value) != chunk$n || length(status) != chunk$n || any(!status %in% 0:3) ||
          !identical(is.finite(value), status %in% 1:2)) stop("Invalid annual observation/status pairs.")
    }
    maximum_bytes <- max(maximum_bytes, row$bytes); checked <- checked + 1L
  }
  # Real-date agreement cases: recent event, annual, decade and full record.
  for (days in c(7L, 365L, 3653L, Inf)) {
    end <- index$last; start <- as.character(max(as.Date(index$first), as.Date(end) - days + 1))
    rows <- index$years[index$years$end >= start & index$years$start <= end, ]
    chunks <- lapply(rows$file, function(file) jsonlite::read_json(file.path(root, file), simplifyVector = TRUE))
    expected <- station_custom_summary(chunks, start, end)
    fixtures[[length(fixtures) + 1L]] <- list(uid = index$uid, start = start, end = end, files = unname(rows$file), expected = expected)
  }
}
dir.create(file.path(root, "checks"), showWarnings = FALSE)
jsonlite::write_json(fixtures, file.path(root, "checks/fixtures.json"), auto_unbox = TRUE, digits = NA, na = "null")
result <- data.frame(status = "PASS", stations = length(catalog$stations), annual_chunks = checked,
  payload_mb = summary$payload_bytes / 1024^2, catalog_kb = summary$catalog_bytes / 1024,
  largest_annual_kb = maximum_bytes / 1024, comparison_cases = length(fixtures))
write.csv(result, file.path(root, "checks/summary.csv"), row.names = FALSE)
print(result, row.names = FALSE)
node <- getOption("swc.station.custom.node", unname(Sys.which("node")))
if (nzchar(node) && file.exists(node)) {
  code <- system2(node, c("tests/station-custom-dates.cjs", shQuote(root)))
  if (code != 0L) stop("Station custom-date JavaScript agreement checks failed.")
} else message("R integrity checks passed. Node was not found; JavaScript checks have not run in this R session. Browser review and the built-in benchmark remain available.")
