# Separate, capped October-May SNODAS update. Source the SNODAS core,
# audit, inventory, and bootstrap modules before this file.

snodas_update_season <- function(today = Sys.Date()) {
  today <- snodas_date(today)
  year <- as.integer(format(today, "%Y"))
  month <- as.integer(format(today, "%m"))
  # Give May's last days time to arrive after the nominal season ends.
  closeout <- month == 6L && as.integer(format(today, "%d")) <= 14L
  if (month %in% 7:9 || (month == 6L && !closeout)) return(NULL)
  water_year <- year + as.integer(month >= 10L)
  list(water_year = water_year,
       start = as.Date(sprintf("%d-10-01", water_year - 1L)),
       end = if (closeout) as.Date(sprintf("%d-05-31", year)) else today,
       current_month = if (closeout) as.Date(sprintf("%d-05-01", year))
                       else as.Date(format(today, "%Y-%m-01")))
}

refresh_snodas_update_inventory <- function(
    today = Sys.Date(),
    cache_path = file.path("data", "diagnostics", "snodas-update",
                           "monthly-directory-inventory.csv"),
    max_requests = 2L,
    delay_seconds = swc_snodas$request_delay_seconds,
    fetch_lines = function(url) readLines(url, warn = FALSE)) {
  season <- snodas_update_season(today)
  cache <- read_snodas_inventory(cache_path)
  if (is.null(season)) {
    return(list(cache = cache, checked_this_run = 0L,
                months_pending = 0L, in_season = FALSE))
  }
  if (length(max_requests) != 1L || !is.numeric(max_requests) ||
      !is.finite(max_requests) || max_requests != floor(max_requests) ||
      max_requests < 0L || max_requests > 2L) {
    stop("SNODAS update allows 0-2 monthly listing requests.", call. = FALSE)
  }
  if (length(delay_seconds) != 1L || !is.numeric(delay_seconds) ||
      !is.finite(delay_seconds) || delay_seconds < 0) {
    stop("`delay_seconds` must be nonnegative.", call. = FALSE)
  }
  months <- seq(season$start, season$current_month, by = "month")
  next_month <- seq(season$start, by = "month",
                    length.out = length(months) + 1L)[-1L]
  stale_months <- function(rows) {
    matched <- match(as.character(months), rows$month)
    checked <- as.Date(substr(rows$checked_utc[matched], 1L, 10L))
    is.na(matched) | (months < season$current_month &
      (is.na(checked) | checked < next_month))
  }
  older <- months[stale_months(cache) & months < season$current_month]
  # Always check the current month; use the second slot for the oldest
  # unchecked or pre-month-end listing.
  selected <- if (max_requests == 1L && length(older)) {
    head(older, 1L)
  } else {
    unique(c(head(older, max(0L, max_requests - 1L)),
             if (max_requests > 0L) season$current_month))
  }
  checked_this_run <- 0L
  for (month_value in selected) {
    month <- as.Date(month_value, origin = "1970-01-01")
    Sys.sleep(delay_seconds)
    # The new month's directory may not exist until its first archive posts.
    # Only an explicit current-month 404 is treated as an empty listing.
    not_found <- FALSE
    listing_text <- tryCatch(
      withCallingHandlers(
        fetch_lines(snodas_month_listing_url(month)),
        warning = function(warning) {
          if (month == season$current_month &&
              grepl("404|not found", conditionMessage(warning),
                    ignore.case = TRUE)) {
            not_found <<- TRUE
            invokeRestart("muffleWarning")
          }
        }),
      error = function(error) {
        if (month == season$current_month &&
            (not_found || grepl("404|not found", conditionMessage(error),
                                ignore.case = TRUE))) {
          return(character())
        }
        stop(error)
      })
    if (not_found) listing_text <- character()
    listed <- snodas_parse_month_listing(
      listing_text, month)
    checked_this_run <- checked_this_run + 1L
    if (!length(listed)) {
      if (month == season$current_month) {
        message("No SNODAS archives listed yet for ", format(month, "%Y-%m"),
                "; checking again next run.")
        next
      }
      stop("No SNODAS archives parsed for completed month ",
           format(month, "%Y-%m"), "; prior inventory is intact.",
           call. = FALSE)
    }
    row <- data.frame(
      month = as.character(month),
      checked_utc = format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC", tz = "UTC"),
      listed_dates = paste(listed, collapse = ","),
      stringsAsFactors = FALSE
    )
    cache <- cache[cache$month != row$month, , drop = FALSE]
    cache <- rbind(cache, row)
    cache <- cache[order(cache$month), , drop = FALSE]
    dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
    temporary <- tempfile("snodas-update-inventory-",
                          tmpdir = dirname(cache_path), fileext = ".csv")
    tryCatch({
      utils::write.csv(cache, temporary, row.names = FALSE)
      if (!file.copy(temporary, cache_path, overwrite = TRUE)) {
        stop("Could not save SNODAS update inventory: ", cache_path)
      }
    }, finally = unlink(temporary))
    message("SNODAS listing ", format(month, "%Y-%m"), ": ",
            length(listed), " archives.")
  }
  list(cache = cache, checked_this_run = checked_this_run,
       months_pending = sum(stale_months(cache)), in_season = TRUE)
}

plan_snodas_daily_update <- function(
    today = Sys.Date(),
    cache = read_snodas_inventory(file.path(
      "data", "diagnostics", "snodas-update",
      "monthly-directory-inventory.csv")),
    raw_dir = swc_paths$raw,
    processed_dir = swc_paths$processed) {
  season <- snodas_update_season(today)
  if (is.null(season)) return(data.frame())
  if (!is.data.frame(cache) ||
      !all(c("month", "listed_dates") %in% names(cache))) {
    stop("Invalid SNODAS update inventory.", call. = FALSE)
  }
  months <- seq(season$start, season$current_month, by = "month")
  rows <- cache[cache$month %in% as.character(months), , drop = FALSE]
  dates <- if (nrow(rows)) {
    as.Date(unlist(strsplit(rows$listed_dates, ",", fixed = TRUE)))
  } else as.Date(character())
  if (anyNA(dates)) stop("Invalid dates in SNODAS update inventory.",
                         call. = FALSE)
  dates <- sort(unique(dates[dates >= season$start & dates <= season$end]))
  plan <- plan_snodas_download(dates, raw_dir = raw_dir)
  plan$processed <- snodas_cool_season_processed(
    plan, processed_dir)$complete
  plan
}

preview_snodas_daily_update <- function(
    plan, max_requests = swc_snodas$max_requests_per_run,
    max_dates = 5L) {
  if (!is.data.frame(plan) ||
      !all(c("date", "url", "path", "complete", "processed") %in%
           names(plan))) {
    stop("Invalid SNODAS daily update plan.", call. = FALSE)
  }
  preview_snodas_download(plan[!plan$processed, , drop = FALSE],
                          max_requests)
  if (length(max_dates) != 1L || !is.numeric(max_dates) ||
      !is.finite(max_dates) || max_dates != floor(max_dates) ||
      max_dates < 0L || max_dates > 5L) {
    stop("SNODAS update allows 0-5 processing dates per run.",
         call. = FALSE)
  }
  cached <- sum(plan$complete & !plan$processed)
  to_process <- min(cached, max_dates)
  to_download <- min(sum(!plan$complete & !plan$processed),
                     max_requests, max_dates - to_process)
  result <- data.frame(
    listed = nrow(plan), processed = sum(plan$processed),
    cached_to_process = to_process, downloads = to_download,
    deferred = sum(!plan$processed) - to_process - to_download
  )
  message(sprintf(paste0("SNODAS update: %d listed; %d processed; ",
                         "%d cached to process; %d downloads; %d deferred."),
                  result$listed, result$processed, result$cached_to_process,
                  result$downloads, result$deferred))
  result
}

run_snodas_daily_update <- function(
    today = Sys.Date(),
    cache_path = file.path("data", "diagnostics", "snodas-update",
                           "monthly-directory-inventory.csv"),
    raw_dir = swc_paths$raw,
    processed_dir = swc_paths$processed,
    max_requests = swc_snodas$max_requests_per_run,
    max_dates = 5L,
    retain_raw = FALSE,
    fetch_lines = function(url) readLines(url, warn = FALSE),
    fetch_archive = function(url, destination) {
      utils::download.file(url, destination, mode = "wb", quiet = TRUE,
                           method = "libcurl")
    }) {
  season <- snodas_update_season(today)
  if (is.null(season)) {
    message("SNODAS update skipped outside October-May and June closeout.")
    return(list(in_season = FALSE, inventory = NULL,
                plan = data.frame(), summary = NULL))
  }
  if (length(retain_raw) != 1L || !is.logical(retain_raw) ||
      is.na(retain_raw)) stop("`retain_raw` must be TRUE or FALSE.",
                             call. = FALSE)
  # Validate the caps before making a listing request.
  preview_snodas_download(plan_snodas_download(as.Date(character()),
                                                raw_dir = raw_dir),
                          max_requests)
  if (length(max_dates) != 1L || !is.numeric(max_dates) ||
      !is.finite(max_dates) || max_dates != floor(max_dates) ||
      max_dates < 0L || max_dates > 5L) {
    stop("SNODAS update allows 0-5 processing dates per run.",
         call. = FALSE)
  }
  inventory <- refresh_snodas_update_inventory(
    today, cache_path = cache_path, fetch_lines = fetch_lines)
  plan <- plan_snodas_daily_update(today, inventory$cache, raw_dir,
                                    processed_dir)
  summary <- preview_snodas_daily_update(plan, max_requests, max_dates)
  cached <- head(which(plan$complete & !plan$processed),
                 summary$cached_to_process)
  pending <- head(which(!plan$complete & !plan$processed),
                  summary$downloads)
  if (length(pending)) {
    download_snodas_plan(
      plan[pending, , drop = FALSE], max_requests = length(pending),
      fetch = fetch_archive, raw_dir = raw_dir)
  }
  selected <- c(cached, pending)
  for (index in selected) {
    date <- plan$date[index]
    archive <- snodas_archive_path(date, raw_dir)
    snodas_archive_members(archive, date, "swe")
    snodas_archive_members(archive, date, "depth")
    process_snodas_date(date, swc_snodas$variables, archive = archive,
                        processed_dir = processed_dir)
    if (!retain_raw) snodas_release_archive(date, raw_dir, processed_dir)
    message("Processed SNODAS SWE and depth ", date)
  }
  after <- plan_snodas_daily_update(today, inventory$cache, raw_dir,
                                     processed_dir)
  list(in_season = TRUE, inventory = inventory, plan = after,
       summary = data.frame(water_year = season$water_year,
                            listed = nrow(after),
                            processed = sum(after$processed),
                            processed_this_run = length(selected),
                            downloaded_this_run = length(pending),
                            remaining = sum(!after$processed),
                            months_pending = inventory$months_pending))
}
