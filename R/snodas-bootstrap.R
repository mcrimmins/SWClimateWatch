# Bounded, resumable October-May SNODAS storage/quality pilot.
# Source config.R, snodas.R, audit-snodas.R, and snodas-inventory.R first.

plan_snodas_cool_season <- function(
    water_year = 2024L,
    inventory_path = file.path("data", "diagnostics", "snodas-audit",
                               "monthly-directory-inventory.csv"),
    raw_dir = swc_paths$raw,
    errata = read_snodas_missing_days(file.path(
      raw_dir, "snodas", "reference", "G02158_missing_files.txt"
    ))) {
  if (length(water_year) != 1L || !is.numeric(water_year) ||
      is.na(water_year) || water_year != floor(water_year) ||
      water_year < 2005L || water_year > 2025L) {
    stop("Water year must be one of 2005-2025.", call. = FALSE)
  }
  start <- as.Date(sprintf("%d-10-01", water_year - 1L))
  end <- as.Date(sprintf("%d-05-31", water_year))
  calendar <- snodas_inventory_calendar(
    read_snodas_inventory(inventory_path), start, end, errata
  )
  allowed <- c("listed", "known_missing_all")
  if (any(!calendar$status %in% allowed)) {
    problem <- unique(calendar$status[!calendar$status %in% allowed])
    stop("SNODAS season inventory is not ready: ",
         paste(problem, collapse = ", "), call. = FALSE)
  }
  plan <- plan_snodas_download(calendar$date[calendar$status == "listed"],
                               raw_dir = raw_dir)
  attr(plan, "known_missing_dates") <- calendar$date[
    calendar$status == "known_missing_all"
  ]
  plan
}

snodas_cool_season_processed <- function(
    plan, processed_dir = swc_paths$processed) {
  if (!is.data.frame(plan) ||
      !all(c("date", "path", "complete") %in% names(plan))) {
    stop("Invalid SNODAS cool-season plan.", call. = FALSE)
  }
  paths <- lapply(swc_snodas$variables, function(variable) {
    vapply(plan$date, snodas_processed_path, character(1),
           variable = variable, processed_dir = processed_dir)
  })
  manifest <- read_snodas_manifest(
    snodas_manifest_path("processed", processed_dir)
  )
  complete <- matrix(FALSE, nrow = nrow(plan),
                     ncol = length(swc_snodas$variables))
  if (nrow(manifest) &&
      all(c("date", "variable", "path", "bytes", "md5",
            "source_md5") %in% names(manifest))) {
    keys <- paste(manifest$date, manifest$variable)
    for (column in seq_along(swc_snodas$variables)) {
      expected <- paths[[column]]
      matched <- match(paste(plan$date, swc_snodas$variables[column]), keys)
      present <- !is.na(matched) & file.exists(expected)
      sizes <- file.info(expected)$size
      valid <- present & manifest$path[matched] == expected &
        manifest$bytes[matched] == sizes & sizes > 0 &
        !is.na(manifest$md5[matched]) & nzchar(manifest$md5[matched]) &
        !is.na(manifest$source_md5[matched]) &
        nzchar(manifest$source_md5[matched])
      valid[is.na(valid)] <- FALSE
      complete[, column] <- valid
    }
  }
  list(paths = paths, complete = rowSums(complete) == ncol(complete))
}

snodas_cool_season_status <- function(plan,
                                      processed_dir = swc_paths$processed) {
  processed <- snodas_cool_season_processed(plan, processed_dir)
  bytes <- function(paths) {
    present <- paths[file.exists(paths)]
    if (!length(present)) return(0)
    sum(file.info(present)$size)
  }
  data.frame(
    water_year = as.integer(format(max(plan$date), "%Y")),
    listed_dates = nrow(plan),
    known_missing_dates = length(attr(plan, "known_missing_dates")),
    raw_cached = sum(plan$complete),
    raw_pending = sum(!plan$complete),
    paired_processed = sum(processed$complete),
    processing_pending = sum(!processed$complete),
    raw_mb = round(bytes(plan$path) / 1024^2, 1),
    processed_mb = round(bytes(unlist(processed$paths, use.names = FALSE)) /
                           1024^2, 1),
    raw_gb = round(bytes(plan$path) / 1024^3, 3),
    processed_gb = round(bytes(unlist(processed$paths, use.names = FALSE)) /
                           1024^3, 3)
  )
}

snodas_verify_processed_pair <- function(date, archive,
                                          processed_dir = swc_paths$processed) {
  date <- snodas_date(date)
  plan <- data.frame(date = date, path = archive, complete = TRUE)
  if (!snodas_cool_season_processed(plan, processed_dir)$complete) {
    stop("SNODAS processed SWE/depth pair is incomplete for ", date,
         "; retaining the source archive.", call. = FALSE)
  }
  manifest <- read_snodas_manifest(
    snodas_manifest_path("processed", processed_dir)
  )
  source_md5 <- unname(tools::md5sum(archive))
  for (variable in swc_snodas$variables) {
    row <- manifest[manifest$date == as.character(date) &
                      manifest$variable == variable, , drop = FALSE]
    if (nrow(row) != 1L) {
      stop("SNODAS processed ", variable, " failed verification for ", date,
           "; retaining the source archive.", call. = FALSE)
    }
    grid <- terra::rast(row$path)
    if (!identical(row$source_md5, source_md5) ||
        !identical(unname(tools::md5sum(row$path)), row$md5) ||
        terra::nlyr(grid) != 1L ||
        length(terra::time(grid)) != 1L ||
        is.na(terra::time(grid)) ||
        as.Date(terra::time(grid)) != date) {
      stop("SNODAS processed ", variable, " failed verification for ", date,
           "; retaining the source archive.", call. = FALSE)
    }
  }
  invisible(TRUE)
}

snodas_release_archive <- function(date, raw_dir = swc_paths$raw,
                                   processed_dir = swc_paths$processed) {
  archive <- snodas_archive_path(date, raw_dir)
  snodas_verify_processed_pair(date, archive, processed_dir)
  unlink(archive)
  if (file.exists(archive)) {
    stop("Could not release processed SNODAS archive: ", archive,
         call. = FALSE)
  }
  message("Released full-domain SNODAS archive ", date)
  invisible(TRUE)
}

run_snodas_cool_season_batch <- function(
    water_year = 2024L,
    max_requests = swc_snodas$max_requests_per_run,
    inventory_path = file.path("data", "diagnostics", "snodas-audit",
                               "monthly-directory-inventory.csv"),
    raw_dir = swc_paths$raw,
    processed_dir = swc_paths$processed,
    retain_raw = FALSE) {
  plan <- plan_snodas_cool_season(water_year, inventory_path, raw_dir)
  if (!is.logical(retain_raw) || length(retain_raw) != 1L ||
      is.na(retain_raw)) {
    stop("`retain_raw` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("The terra package is required for SNODAS processing.", call. = FALSE)
  }
  repair_mask_path <- file.path(raw_dir, "snodas", "reference",
                                "SNODAS_Zero_Repair_Mask.tif")
  processed <- snodas_cool_season_processed(plan, processed_dir)$complete
  cached_pending <- which(plan$complete & !processed)
  downloaded_dates <- as.Date(character())
  if (length(cached_pending)) {
    preview_snodas_download(plan[!processed, , drop = FALSE], max_requests)
    # Recover an interrupted prior batch before making more network requests.
    dates <- head(plan$date[cached_pending], max_requests)
    message(sprintf("Processing %d already downloaded SNODAS dates first.",
                    length(dates)))
  } else {
    pending <- plan[!processed, , drop = FALSE]
    downloaded <- download_snodas_plan(pending, max_requests = max_requests,
                                       raw_dir = raw_dir)
    dates <- as.Date(downloaded$date)
    downloaded_dates <- dates
  }
  for (index in seq_along(dates)) {
    date <- dates[index]
    snodas_archive_members(snodas_archive_path(date, raw_dir), date, "swe")
    snodas_archive_members(snodas_archive_path(date, raw_dir), date, "depth")
    process_snodas_date(date, swc_snodas$variables,
                        archive = snodas_archive_path(date, raw_dir),
                        processed_dir = processed_dir,
                        repair_mask_path = repair_mask_path)
    if (!retain_raw && date %in% downloaded_dates) {
      snodas_release_archive(date, raw_dir, processed_dir)
    }
    message("Processed SNODAS SWE and depth ", date)
  }
  snodas_cool_season_status(
    plan_snodas_cool_season(water_year, inventory_path, raw_dir),
    processed_dir
  )
}

run_snodas_cool_season_stage <- function(
    water_year = 2024L, max_batches = 4L,
    inventory_path = file.path("data", "diagnostics", "snodas-audit",
                               "monthly-directory-inventory.csv"),
    raw_dir = swc_paths$raw,
    processed_dir = swc_paths$processed,
    retain_raw = FALSE) {
  if (length(max_batches) != 1L || !is.numeric(max_batches) ||
      is.na(max_batches) || max_batches != floor(max_batches) ||
      max_batches < 1L || max_batches > 4L) {
    stop("A SNODAS stage must contain 1-4 five-request batches.",
         call. = FALSE)
  }
  status <- snodas_cool_season_status(
    plan_snodas_cool_season(water_year, inventory_path, raw_dir),
    processed_dir
  )
  for (batch in seq_len(max_batches)) {
    if (status$processing_pending == 0L) break
    if (batch > 1L) {
      Sys.sleep(swc_snodas$request_delay_seconds +
                  stats::runif(1L, 0, swc_snodas$request_jitter_seconds))
    }
    before <- status
    message(sprintf("SNODAS stage batch %d/%d", batch, max_batches))
    status <- run_snodas_cool_season_batch(
      water_year, max_requests = min(5L, swc_snodas$max_requests_per_run),
      inventory_path = inventory_path, raw_dir = raw_dir,
      processed_dir = processed_dir, retain_raw = retain_raw
    )
    if (status$raw_cached == before$raw_cached &&
        status$paired_processed == before$paired_processed) {
      stop("SNODAS stage made no progress; inspect the local manifests.",
           call. = FALSE)
    }
  }
  status
}
