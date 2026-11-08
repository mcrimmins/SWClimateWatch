# True monthly PRISM inputs, isolated from daily PRISM caches and manifests.
# Source helpers: config.R, acis-prism.R, process-prism.R.

swc_monthly_prism <- list(
  endpoint = swc_prism$monthly_endpoint, grid = swc_prism$monthly_grid,
  start_month = "1895-01", variables = c("maxt", "mint", "pcpn"),
  early_month_days = 1:5 # Proposed retry window; not wired into production yet.
)

prism_monthly_month <- function(x) {
  x <- as.character(x)
  if (!length(x) || anyNA(x) || any(!grepl("^[0-9]{4}-[0-9]{2}$", x))) {
    stop("Months must use YYYY-MM.", call. = FALSE)
  }
  dates <- as.Date(paste0(x, "-01"), format = "%Y-%m-%d")
  if (anyNA(dates) || any(format(dates, "%Y-%m") != x)) {
    stop("Invalid calendar month.", call. = FALSE)
  }
  dates
}

prism_monthly_latest_complete <- function(today = Sys.Date()) {
  format(as.Date(format(as.Date(today), "%Y-%m-01")) - 1L, "%Y-%m")
}

prism_monthly_cache_dir <- function() {
  file.path(swc_paths$processed, "prism-monthly", swc_prism$aoi_id)
}

prism_monthly_payload <- function(item) {
  list(grid = swc_monthly_prism$grid,
    bbox = as.numeric(strsplit(item$bbox, ",", fixed = TRUE)[[1L]]),
    date = item$month,
    elems = list(list(name = item$variable, interval = "mly", duration = "mly",
      reduce = if (item$variable == "pcpn") "sum" else "mean",
      units = item$native_units, maxmissing = 0L)), output = "geotiff")
}

validate_prism_monthly_grid <- function(path, item, reference = NULL) {
  r <- terra::rast(path)
  if (terra::nlyr(r) != 1L || !terra::is.lonlat(r) ||
      any(abs(terra::res(r) - 1 / 24) > 1e-5)) {
    stop("Monthly input must be one geographic 4-km PRISM layer.", call. = FALSE)
  }
  date_lines <- grep("^[[:space:]]*Date=", terra::describe(path), value = TRUE)
  stamp <- sub("^[[:space:]]*Date=", "", date_lines)
  if (!length(stamp)) {
    time <- terra::time(r)
    stamp <- if (inherits(time, "Date") || inherits(time, "POSIXt")) format(time, "%Y-%m") else ""
  }
  if (length(stamp) != 1L || !identical(substr(stamp, 1L, 7L), item$month)) {
    stop("Monthly input date does not match the requested month.", call. = FALSE)
  }
  box <- as.numeric(strsplit(item$bbox, ",", fixed = TRUE)[[1L]])
  e <- as.vector(terra::ext(r))
  tolerance <- 1e-4
  if (e[1] > box[1] + tolerance || e[2] < box[3] - tolerance ||
      e[3] > box[2] + tolerance || e[4] < box[4] - tolerance ||
      any(abs(e - box[c(1, 3, 2, 4)]) > 2 / 24)) {
    stop("Monthly grid does not match the requested regional extent.", call. = FALSE)
  }
  if (!is.null(reference) && !terra::compareGeom(r, reference, stopOnError = FALSE)) {
    stop("Monthly geometry differs from the cache reference grid.", call. = FALSE)
  }
  values <- validate_prism_native_values(r, item$variable)
  fraction <- terra::global(!is.na(r), "mean", na.rm = TRUE)[1, 1]
  if (!is.finite(fraction) || fraction < 0.5) {
    stop("Less than half of the regional monthly grid has usable data.", call. = FALSE)
  }
  list(raster = r, minimum = values[1], maximum = values[2], valid_fraction = fraction)
}

plan_prism_monthly_download <- function(
    months = NULL, start = "1895-01", end = prism_monthly_latest_complete(),
    variables = swc_monthly_prism$variables, cache_dir = prism_monthly_cache_dir(),
    bbox = swc_region$bbox, today = Sys.Date(), verify_grids = TRUE) {
  if (is.null(months)) {
    bounds <- prism_monthly_month(c(start, end))
    if (bounds[1] > bounds[2]) stop("Start month follows end month.", call. = FALSE)
    months <- format(seq(bounds[1], bounds[2], by = "month"), "%Y-%m")
  }
  dates <- sort(unique(prism_monthly_month(months)))
  if (any(dates < prism_monthly_month(swc_monthly_prism$start_month)) ||
      any(dates > prism_monthly_month(prism_monthly_latest_complete(today)))) {
    stop("Only complete calendar months from 1895 onward can be requested.", call. = FALSE)
  }
  if (!length(variables) || anyNA(variables) ||
      any(!variables %in% swc_monthly_prism$variables)) {
    stop("Monthly source variables must be maxt, mint or pcpn.", call. = FALSE)
  }
  bbox <- normalize_prism_bbox(bbox)
  plan <- expand.grid(variable = unique(variables), month = format(dates, "%Y-%m"),
    stringsAsFactors = FALSE)
  plan$native_units <- unname(swc_prism$native_units[plan$variable])
  plan$bbox <- paste(bbox, collapse = ",")
  plan$path <- file.path(cache_dir, plan$variable, paste0(plan$month, ".tif"))
  plan$request_signature <- vapply(seq_len(nrow(plan)), function(i) {
    digest::digest(list(endpoint = swc_monthly_prism$endpoint,
      payload = prism_monthly_payload(plan[i, ])), algo = "sha256")
  }, character(1))
  manifest_path <- file.path(cache_dir, "manifest.csv")
  manifest <- if (file.exists(manifest_path)) read.csv(manifest_path, stringsAsFactors = FALSE) else data.frame()
  plan$complete <- FALSE
  plan$md5 <- NA_character_
  for (i in seq_len(nrow(plan))) {
    if (!nrow(manifest) || !file.exists(plan$path[i])) next
    j <- match(plan$path[i], manifest$path)
    if (is.na(j) || !identical(manifest$request_signature[j], plan$request_signature[i])) next
    plan$md5[i] <- unname(tools::md5sum(plan$path[i]))
    plan$complete[i] <- identical(plan$md5[i], manifest$md5[j]) &&
      (!isTRUE(verify_grids) || isTRUE(tryCatch({
        validate_prism_monthly_grid(plan$path[i], plan[i, ]); TRUE
      }, error = function(e) FALSE)))
  }
  attr(plan, "manifest_path") <- manifest_path
  plan
}

download_prism_monthly_plan <- function(plan, max_requests = 12L, refresh = FALSE,
    timeout_seconds = 180, delay_seconds = 1, fetch = NULL) {
  if (length(max_requests) != 1L || is.na(max_requests) || max_requests < 1 ||
      (!is.infinite(max_requests) && max_requests != floor(max_requests))) {
    stop("max_requests must be a positive whole number or Inf.", call. = FALSE)
  }
  if (length(delay_seconds) != 1L || !is.finite(delay_seconds) || delay_seconds < 0) {
    stop("delay_seconds must be nonnegative.", call. = FALSE)
  }
  manifest_path <- attr(plan, "manifest_path")
  if (is.null(manifest_path)) stop("Use plan_prism_monthly_download() first.", call. = FALSE)
  reference <- NULL
  for (i in which(plan$complete)) {
    r <- terra::rast(plan$path[i])
    if (is.null(reference)) reference <- r else if (!terra::compareGeom(r, reference, stopOnError = FALSE)) {
      stop("Existing monthly cache contains different geometries.", call. = FALSE)
    }
  }
  queue <- which(!plan$complete | isTRUE(refresh))
  queue <- head(queue, min(length(queue), max_requests))
  message("Monthly PRISM: ", nrow(plan), " inputs; ", sum(plan$complete),
    " verified cached; ", length(queue), " scheduled.")
  if (is.null(fetch)) fetch <- function(item, destination) {
    httr2::request(swc_monthly_prism$endpoint) |>
      httr2::req_body_json(prism_monthly_payload(item), auto_unbox = TRUE) |>
      httr2::req_timeout(timeout_seconds) |>
      httr2::req_retry(max_tries = 3L, retry_on_failure = TRUE) |>
      httr2::req_perform(path = destination)
  }
  results <- list()
  for (k in seq_along(queue)) {
    i <- queue[k]; item <- plan[i, ]
    message("[", k, "/", length(queue), "] Monthly ", item$variable, " ", item$month)
    started <- proc.time()[["elapsed"]]
    record <- tryCatch((function() {
      dir.create(dirname(item$path), recursive = TRUE, showWarnings = FALSE)
      temporary <- tempfile("monthly-", tmpdir = dirname(item$path), fileext = ".tif")
      compressed <- tempfile("monthly-compressed-", tmpdir = dirname(item$path), fileext = ".tif")
      on.exit(unlink(c(temporary, compressed)), add = TRUE)
      fetch(item, temporary)
      checked <- validate_prism_monthly_grid(temporary, item, reference)
      source_md5 <- unname(tools::md5sum(temporary))
      transferred <- file.info(temporary)$size
      r <- checked$raster
      terra::time(r) <- prism_monthly_month(item$month)
      names(r) <- paste(item$variable, item$month, sep = "_")
      terra::writeRaster(r, compressed, datatype = "FLT4S", gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3"))
      validate_prism_monthly_grid(compressed, item, reference)
      # Validate and compress before replacing an existing verified grid.
      r <- NULL; checked$raster <- NULL
      replace_file_atomically(compressed, item$path)
      row <- data.frame(start_date = paste0(item$month, "-01"), month = item$month,
        variable = item$variable, native_units = item$native_units, bbox = item$bbox,
        endpoint = swc_monthly_prism$endpoint, grid = swc_monthly_prism$grid,
        request_signature = item$request_signature, source_md5 = source_md5,
        md5 = unname(tools::md5sum(item$path)), bytes = file.info(item$path)$size,
        transferred_bytes = transferred, minimum = checked$minimum, maximum = checked$maximum,
        valid_fraction = checked$valid_fraction,
        checked_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), path = item$path)
      write_prism_manifest(row, manifest_path)
      data.frame(month = item$month, variable = item$variable, status = "CACHED",
        transferred_bytes = transferred, saved_bytes = row$bytes, note = "")
    })(), error = function(e) data.frame(month = item$month, variable = item$variable,
      status = "FAILED", transferred_bytes = NA_real_, saved_bytes = NA_real_, note = conditionMessage(e)))
    record$elapsed_seconds <- proc.time()[["elapsed"]] - started
    results[[k]] <- record
    if (record$status == "CACHED" && is.null(reference)) reference <- terra::rast(item$path)
    if (k < length(queue)) Sys.sleep(delay_seconds)
  }
  if (length(results)) do.call(rbind, results) else data.frame()
}
