# Read-only SNODAS availability and raster quality checks. Source config.R and
# snodas.R first. This does not download the historical daily raster archive.

snodas_missing_file_url <- paste0(
  "https://noaadata.apps.nsidc.org/NOAA/G02158/",
  "G02158_missing_files.txt"
)
snodas_repair_mask_url <- paste0(
  "https://noaadata.apps.nsidc.org/NOAA/G02158/ancillary/",
  "SNODAS_Zero_Repair_Mask.tif"
)

read_snodas_missing_days <- function(path) {
  if (!file.exists(path)) stop("Missing NSIDC errata list: ", path, call. = FALSE)
  lines <- trimws(readLines(path, warn = FALSE))
  masked_start <- match("MISSING MASKED FILES", lines)
  unmasked_start <- match("MISSING UNMASKED FILES", lines)
  if (is.na(masked_start) || is.na(unmasked_start) ||
      masked_start >= unmasked_start) {
    stop("Could not locate masked SNODAS errata section.", call. = FALSE)
  }
  masked <- lines[seq.int(masked_start + 1L, unmasked_start - 1L)]
  individual_start <- grep("missing individual files", masked, ignore.case = TRUE)
  if (length(individual_start) != 1L) {
    stop("Could not locate individual-file errata section.", call. = FALSE)
  }
  whole <- masked[seq_len(individual_start - 1L)]
  all_missing <- as.Date(grep("^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
                              whole, value = TRUE))
  bad_swe <- as.Date(sub(" .*", "", grep(
    "^[0-9]{4}-[0-9]{2}-[0-9]{2}.*(SWE file|missing one file)",
    masked, value = TRUE
  )))
  list(all_missing = sort(unique(all_missing)),
       bad_swe = sort(unique(bad_swe)),
       source_path = path)
}

snodas_availability_calendar <- function(
    start = as.Date("2004-10-01"), end = as.Date("2025-09-30"),
    errata = read_snodas_missing_days(file.path(
      swc_paths$raw, "snodas", "reference", "G02158_missing_files.txt"
    ))) {
  start <- snodas_date(start)
  end <- snodas_date(end)
  if (start > end) stop("SNODAS audit start must not follow end.", call. = FALSE)
  dates <- seq(start, end, by = "day")
  year <- as.integer(format(dates, "%Y"))
  month <- as.integer(format(dates, "%m"))
  status <- rep("not_flagged", length(dates))
  status[dates %in% errata$bad_swe] <- "bad_swe"
  status[dates %in% errata$all_missing] <- "missing_all"
  data.frame(
    date = dates,
    water_year = year + as.integer(month >= 10L),
    snow_season = month %in% c(11L, 12L, 1L, 2L, 3L, 4L),
    status = status,
    stringsAsFactors = FALSE
  )
}

summarize_snodas_availability <- function(calendar) {
  if (!all(c("date", "water_year", "snow_season", "status") %in%
           names(calendar))) {
    stop("Invalid SNODAS availability calendar.", call. = FALSE)
  }
  result <- lapply(split(calendar, calendar$water_year), function(x) {
    data.frame(
      water_year = x$water_year[1L],
      days = nrow(x),
      known_missing_all = sum(x$status == "missing_all"),
      known_bad_swe = sum(x$status == "bad_swe"),
      snow_season_days = sum(x$snow_season),
      snow_season_flagged = sum(x$snow_season & x$status != "not_flagged"),
      unflagged_fraction = mean(x$status == "not_flagged")
    )
  })
  do.call(rbind, result)
}

snodas_month_listing_url <- function(month) {
  month <- as.Date(format(snodas_date(month), "%Y-%m-01"))
  paste0(swc_snodas$base_url, "/", format(month, "%Y"), "/",
         format(month, "%m"), "_",
         month.abb[as.integer(format(month, "%m"))], "/")
}

snodas_parse_month_listing <- function(lines, month) {
  month <- as.Date(format(snodas_date(month), "%Y-%m-01"))
  text <- paste(lines, collapse = "\n")
  matches <- regmatches(text, gregexpr("SNODAS_[0-9]{8}[.]tar", text))[[1L]]
  if (!length(matches)) return(as.Date(character()))
  dates <- as.Date(sub("^SNODAS_([0-9]{4})([0-9]{2})([0-9]{2})[.]tar$",
                       "\\1-\\2-\\3", unique(matches)))
  sort(dates[!is.na(dates) & format(dates, "%Y-%m") == format(month, "%Y-%m")])
}

snodas_probe_months <- function(months, max_requests = 3L,
                                delay_seconds = swc_snodas$request_delay_seconds,
                                fetch_lines = function(url) readLines(url, warn = FALSE)) {
  months <- sort(unique(as.Date(format(as.Date(months), "%Y-%m-01"))))
  if (anyNA(months) || !is.numeric(max_requests) ||
      length(max_requests) != 1L || !is.finite(max_requests) ||
      max_requests < 0 || max_requests > 3 || max_requests != floor(max_requests)) {
    stop("A month probe is limited to 0-3 requests.", call. = FALSE)
  }
  if (!is.numeric(delay_seconds) || length(delay_seconds) != 1L ||
      !is.finite(delay_seconds) || delay_seconds < 0) {
    stop("`delay_seconds` must be nonnegative.", call. = FALSE)
  }
  selected <- head(months, max_requests)
  if (!length(selected)) return(data.frame())
  rows <- lapply(seq_along(selected), function(index) {
    if (index > 1L) Sys.sleep(delay_seconds)
    month <- selected[index]
    listed <- snodas_parse_month_listing(
      fetch_lines(snodas_month_listing_url(month)), month
    )
    expected <- seq(month, seq(month, by = "month", length.out = 2L)[2L] - 1L,
                    by = "day")
    data.frame(month = as.character(month),
               listed_days = length(listed), expected_days = length(expected),
               unlisted_dates = paste(setdiff(expected, listed), collapse = ","),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

snodas_raster_quality <- function(raster, date, variable = "swe",
                                  repair_mask_path = NULL) {
  date <- snodas_date(date)
  if (!inherits(raster, "SpatRaster") || terra::nlyr(raster) != 1L) {
    stop("Expected a one-layer SNODAS raster.", call. = FALSE)
  }
  if (!variable %in% swc_snodas$variables) {
    stop("SNODAS variable must be 'swe' or 'depth'.", call. = FALSE)
  }
  values <- as.vector(terra::values(raster))
  valid <- is.finite(values)
  repaired_cells <- NA_integer_
  repaired_zero_cells <- NA_integer_
  repair_period <- date >= as.Date("2014-10-09") &&
    date <= as.Date("2019-10-10")
  if (repair_period && !is.null(repair_mask_path)) {
    if (!file.exists(repair_mask_path)) {
      stop("Missing SNODAS repair mask: ", repair_mask_path, call. = FALSE)
    }
    mask <- terra::resample(terra::rast(repair_mask_path), raster,
                            method = "near")
    affected <- as.vector(terra::values(mask)) == 1
    affected[is.na(affected)] <- FALSE
    repaired_cells <- sum(affected)
    repaired_zero_cells <- sum(affected & valid & values == 0)
  }
  data.frame(
    date = as.character(date), variable = variable,
    cells = length(values), valid_fraction = mean(valid),
    snow_fraction_valid = if (any(valid)) mean(values[valid] > 0) else NA_real_,
    max_inches = if (any(valid)) max(values[valid]) else NA_real_,
    negative_cells = sum(valid & values < 0),
    saturated_cells = sum(valid & values >= 32767 / 25.4),
    repair_period = repair_period,
    repair_mask_cells = repaired_cells,
    repair_zero_cells = repaired_zero_cells,
    stringsAsFactors = FALSE
  )
}
