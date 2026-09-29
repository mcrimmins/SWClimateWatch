# Resumable, metadata-only inventory of masked SNODAS monthly directories.
# Source config.R, snodas.R, and audit-snodas.R before this file.

snodas_inventory_months <- function(start = as.Date("2004-10-01"),
                                    end = as.Date("2025-09-30")) {
  start <- snodas_date(start)
  end <- snodas_date(end)
  if (start > end) stop("Inventory start must not follow end.", call. = FALSE)
  seq(as.Date(format(start, "%Y-%m-01")),
      as.Date(format(end, "%Y-%m-01")), by = "month")
}

read_snodas_inventory <- function(path) {
  empty <- data.frame(month = character(), checked_utc = character(),
                      listed_dates = character(), stringsAsFactors = FALSE)
  if (!file.exists(path)) return(empty)
  rows <- utils::read.csv(path, stringsAsFactors = FALSE,
                          colClasses = "character")
  if (!identical(names(rows), names(empty)) || anyNA(rows) ||
      anyDuplicated(rows$month) ||
      anyNA(as.Date(rows$month)) ||
      any(format(as.Date(rows$month), "%Y-%m-01") != rows$month)) {
    stop("Invalid SNODAS inventory cache: ", path, call. = FALSE)
  }
  rows
}

snodas_inventory_batch <- function(
    months = snodas_inventory_months(),
    cache_path = file.path("data", "diagnostics", "snodas-audit",
                           "monthly-directory-inventory.csv"),
    max_requests = 12L,
    delay_seconds = swc_snodas$request_delay_seconds,
    fetch_lines = function(url) readLines(url, warn = FALSE)) {
  months <- sort(unique(as.Date(format(as.Date(months), "%Y-%m-01"))))
  if (anyNA(months) || !length(months) ||
      !is.numeric(max_requests) || length(max_requests) != 1L ||
      !is.finite(max_requests) || max_requests < 0L ||
      max_requests > 12L || max_requests != floor(max_requests)) {
    stop("SNODAS inventory is limited to 0-12 monthly requests per run.",
         call. = FALSE)
  }
  if (!is.numeric(delay_seconds) || length(delay_seconds) != 1L ||
      !is.finite(delay_seconds) || delay_seconds < 0) {
    stop("`delay_seconds` must be nonnegative.", call. = FALSE)
  }
  cache <- read_snodas_inventory(cache_path)
  pending <- head(months[!as.character(months) %in% cache$month], max_requests)
  if (!length(pending)) return(list(cache = cache, checked_this_run = 0L,
                                    remaining = sum(!as.character(months) %in%
                                                      cache$month)))
  dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
  for (index in seq_along(pending)) {
    # Pause before every request, including the first request of a rerun.
    Sys.sleep(delay_seconds)
    month <- pending[index]
    listed <- snodas_parse_month_listing(
      fetch_lines(snodas_month_listing_url(month)), month
    )
    # A blank listing could instead be an HTTP error page or a changed server
    # layout. Do not record it as a verified empty month.
    if (!length(listed)) {
      stop("No SNODAS archives parsed for ", format(month, "%Y-%m"),
           "; inventory cache was saved through the prior month.",
           call. = FALSE)
    }
    cache <- rbind(cache, data.frame(
      month = as.character(month),
      checked_utc = format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC", tz = "UTC"),
      listed_dates = paste(listed, collapse = ","),
      stringsAsFactors = FALSE
    ))
    cache <- cache[order(cache$month), , drop = FALSE]
    utils::write.csv(cache, cache_path, row.names = FALSE)
    message(sprintf("SNODAS listing %d/%d: %s (%d archives)",
                    index, length(pending), format(month, "%Y-%m"),
                    length(listed)))
  }
  list(cache = cache, checked_this_run = length(pending),
       remaining = sum(!as.character(months) %in% cache$month))
}

snodas_inventory_calendar <- function(
    cache, start = as.Date("2004-10-01"), end = as.Date("2025-09-30"),
    errata = read_snodas_missing_days(file.path(
      swc_paths$raw, "snodas", "reference", "G02158_missing_files.txt"
    ))) {
  dates <- seq(snodas_date(start), snodas_date(end), by = "day")
  month <- format(dates, "%Y-%m-01")
  listed <- rep(FALSE, length(dates))
  for (index in seq_len(nrow(cache))) {
    entries <- strsplit(cache$listed_dates[index], ",", fixed = TRUE)[[1L]]
    parsed <- as.Date(entries)
    if (anyNA(parsed) || any(format(parsed, "%Y-%m-01") !=
                         cache$month[index])) {
      stop("Invalid listed dates in SNODAS inventory cache.", call. = FALSE)
    }
    listed[dates %in% parsed] <- TRUE
  }
  checked <- month %in% cache$month
  known_missing <- dates %in% errata$all_missing
  known_bad_swe <- dates %in% errata$bad_swe
  status <- ifelse(!checked, "not_checked",
                   ifelse(listed, "listed", "unlisted_unexplained"))
  status[checked & known_missing & !listed] <- "known_missing_all"
  status[checked & known_missing & listed] <- "listed_but_errata_missing"
  status[checked & known_bad_swe & listed] <- "listed_bad_swe"
  status[checked & known_bad_swe & !listed] <- "unlisted_bad_swe"
  year <- as.integer(format(dates, "%Y"))
  month_number <- as.integer(format(dates, "%m"))
  data.frame(date = dates, month = month,
             water_year = year + as.integer(month_number >= 10L),
             snow_season = month_number %in% c(11L, 12L, 1L, 2L, 3L, 4L),
             status = status, stringsAsFactors = FALSE)
}

summarize_snodas_inventory <- function(calendar) {
  result <- lapply(split(calendar, calendar$month), function(x) {
    checked <- all(x$status != "not_checked")
    count_checked <- function(condition) {
      if (checked) sum(condition) else NA_integer_
    }
    data.frame(month = x$month[1L], water_year = x$water_year[1L],
               expected_days = nrow(x),
               checked = checked,
               listed_days = count_checked(x$status %in% c(
                 "listed", "listed_bad_swe", "listed_but_errata_missing")),
               known_missing_all = count_checked(x$status == "known_missing_all"),
               unexplained_unlisted = count_checked(
                 x$status == "unlisted_unexplained"),
               errata_conflicts = count_checked(
                 x$status == "listed_but_errata_missing"),
               bad_swe = count_checked(x$status %in% c(
                 "listed_bad_swe", "unlisted_bad_swe")),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, result)
}

summarize_snodas_inventory_water_year <- function(month_summary) {
  result <- lapply(split(month_summary, month_summary$water_year), function(x) {
    months_checked <- sum(x$checked)
    count_checked <- function(column) {
      if (months_checked) sum(column, na.rm = TRUE) else NA_integer_
    }
    data.frame(water_year = x$water_year[1L],
               status = if (months_checked == 0L) "NOT_CHECKED" else if (
                 months_checked == nrow(x)) "COMPLETE" else "PARTIAL",
               months_checked = months_checked,
               months_total = nrow(x),
               listed_days = count_checked(x$listed_days),
               known_missing_all = count_checked(x$known_missing_all),
               unexplained_unlisted = count_checked(x$unexplained_unlisted),
               errata_conflicts = count_checked(x$errata_conflicts),
               bad_swe = count_checked(x$bad_swe),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, result)
}
