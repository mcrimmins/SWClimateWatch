# Publication adapter. Climate inputs and RDS caches stay outside the website.
daily_explorer_site_window <- function(manifest, window_days = NULL) {
  # NULL grows the current water year, retaining September for October grids.
  # An explicit day count is only a bounded pilot/diagnostic override.
  if (!is.null(window_days) && (length(window_days) != 1L || !is.numeric(window_days) ||
      !is.finite(window_days) || window_days < 1L || window_days != as.integer(window_days)))
    stop("window_days must be a positive integer.")
  rows <- manifest[manifest$product == "daily" & manifest$aoi_id == swc_prism$aoi_id &
    manifest$variable %in% c("pcpn", "maxt", "mint") & file.exists(manifest$path), , drop = FALSE]
  if (!nrow(rows)) stop("No cached daily PRISM grids are available for Daily Explorer.")
  end <- max(as.Date(rows$end_date))
  start <- if (is.null(window_days)) {
    as.Date(sprintf("%d-09-01", daily_explorer_water_year(end) - 1L))
  } else end - as.integer(window_days) + 1L
  list(start_date = start, end_date = end,
       water_years = seq(daily_explorer_water_year(start), daily_explorer_water_year(end)))
}

validate_daily_explorer_assets <- function(directory) {
  needed <- file.path(directory, c("index.html", "explorer.js", "explorer.css", "daily-data.json"))
  if (!all(file.exists(needed)) || any(file.info(needed)$size <= 0))
    stop("Daily Explorer resources are missing; publication stopped.")
  data <- jsonlite::read_json(file.path(directory, "daily-data.json"), simplifyVector = FALSE)
  if (!identical(data$schema_version, 1L) || !length(data$days))
    stop("Daily Explorer data are invalid; publication stopped.")
  dates <- vapply(data$days, function(day) day$date, character(1))
  if (anyNA(as.Date(dates)) || anyDuplicated(dates) || is.unsorted(dates, strictly = TRUE) ||
      tail(dates, 1L) != data$latest_cached_date)
    stop("Daily Explorer dates are invalid or stale; publication stopped.")
  images <- unlist(lapply(data$days, function(day) unlist(day$images, use.names = FALSE)), use.names = FALSE)
  if (!length(images) || anyNA(images) ||
      any(!grepl("^maps/[0-9]{4}-[0-9]{2}-[0-9]{2}-(pcpn|maxt|mint|tmean)-(observed|departure)\\.png$", images)))
    stop("Daily Explorer image references are invalid; publication stopped.")
  paths <- file.path(directory, images)
  if (!all(file.exists(paths)) || any(file.info(paths)$size <= 0))
    stop("Daily Explorer images are missing; publication stopped.")
  invisible(list(days = length(dates), maps = length(images), start_date = dates[[1L]],
    end_date = tail(dates, 1L), images = images))
}

stage_daily_explorer_site <- function(window_days = NULL,
    output_dir = file.path("site", "daily-explorer"),
    work_dir = file.path("data", "diagnostics", "daily-explorer-site"),
    manifest = read_prism_manifest(prism_processed_manifest_path()),
    builder = build_daily_explorer) {
  started <- Sys.time()
  window <- daily_explorer_site_window(manifest, window_days)
  build <- builder(water_years = window$water_years,
    start_date = window$start_date, end_date = window$end_date,
    output_dir = work_dir, manifest = manifest, publication_mode = TRUE)
  checked <- validate_daily_explorer_assets(work_dir)
  dir.create(file.path(output_dir, "maps"), recursive = TRUE, showWarnings = FALSE)
  files <- c("index.html", "explorer.js", "explorer.css", "daily-data.json", checked$images)
  for (relative in files) {
    from <- file.path(work_dir, relative); to <- file.path(output_dir, relative)
    # Unchanged bytes keep their mtime and avoid needless S3 transfers.
    if (file.exists(to) && identical(unname(tools::md5sum(from)), unname(tools::md5sum(to)))) next
    if (!file.copy(from, to, overwrite = TRUE)) stop("Could not stage Daily Explorer: ", relative)
  }
  # Prune only generated PNGs in this adapter's exact maps directory. No raw
  # data, work caches, or remote S3 objects are removed.
  old <- list.files(file.path(output_dir, "maps"),
    pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}-(pcpn|maxt|mint|tmean)-(observed|departure)\\.png$",
    full.names = TRUE)
  obsolete <- old[!paste0("maps/", basename(old)) %in% checked$images]
  if (length(obsolete) && any(!file.remove(obsolete))) stop("Could not prune old Daily Explorer images.")
  checked <- validate_daily_explorer_assets(output_dir)
  result <- c(list(status = "STAGED", built = build$built, reused = build$reused,
    elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))), checked)
  message(sprintf("Daily Explorer: %d days, %d maps; %d dates rebuilt, %d reused (%.1fs).",
    result$days, result$maps, result$built, result$reused, result$elapsed_seconds))
  invisible(result)
}
