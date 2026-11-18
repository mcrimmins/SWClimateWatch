# Local site integration of the reviewed pilot; no deployment or data acquisition.
interactive_map_preview_render_args <- function(full_site = TRUE, site_dir = "site") {
  # A Windows preview server may hold output-dir as its working directory.
  # Update local files in place instead of deleting that served directory.
  c("render", if (isTRUE(full_site)) site_dir else file.path(site_dir, "pages/interactive-maps.qmd"), "--no-clean")
}

stage_interactive_map_site <- function(pilot_dir = "data/diagnostics/interactive-map-pilot", site_dir = "site") {
  manifest_path <- file.path(pilot_dir, "manifest.json")
  if (!file.exists(manifest_path)) stop("Build the interactive map pilot first.")
  manifest <- jsonlite::read_json(manifest_path)
  folder <- file.path(site_dir, "interactive-maps")
  dir.create(folder, recursive = TRUE, showWarnings = FALSE)
  files <- "manifest.json"
  for (entry in manifest$layers) {
    from <- file.path(pilot_dir, entry$file)
    receipt <- paste0(from, ".md5")
    expected_bytes <- if (identical(entry$compression, "gzip")) entry$transfer_bytes else entry$bytes
    if (!identical(basename(entry$file), entry$file) || !length(expected_bytes) ||
        !file.exists(from) || file.info(from)$size != expected_bytes || !file.exists(receipt) ||
        !identical(readLines(receipt), unname(tools::md5sum(from)))) stop("Unverified pilot payload: ", from)
    if (identical(entry$compression, "gzip")) validate_interactive_snow_payload(entry, pilot_dir)
    files <- c(files, entry$file)
  }
  html <- paste(readLines(file.path(pilot_dir, "index.html"), encoding = "UTF-8"), collapse = "\n")
  # Version scripts/styles/libraries so a repeated preview never reuses stale controls.
  for (name in c("pilot.js", "pilot.css", "leaflet.js", "leaflet.css")) {
    from <- file.path(pilot_dir, name)
    hash <- substr(unname(tools::md5sum(from)), 1, 12)
    versioned <- sub("(\\.[^.]+)$", paste0("-", hash, "\\1"), name)
    interactive_pilot_copy(from, file.path(folder, versioned))
    html <- gsub(paste0('"', name, '"'), paste0('"', versioned, '"'), html, fixed = TRUE)
    files <- c(files, versioned)
  }
  html <- gsub("https://cales.arizona.edu/climate/watch/pages/", "../pages/", html, fixed = TRUE)
  files <- c(files, "boundaries.json", "leaflet-package-LICENSE")
  for (name in files[file.exists(file.path(pilot_dir, files))])
    interactive_pilot_copy(file.path(pilot_dir, name), file.path(folder, name))
  temp <- tempfile(fileext = ".html")
  writeLines(enc2utf8(html), temp, useBytes = TRUE)
  interactive_pilot_copy(temp, file.path(folder, "index.html")); unlink(temp)
  files <- c(files, "index.html")
  assets <- list(schema = 1L, files = lapply(files, function(name) list(file = name,
    md5 = unname(tools::md5sum(file.path(folder, name))))))
  temp <- tempfile(fileext = ".json")
  jsonlite::write_json(assets, temp, auto_unbox = TRUE, pretty = TRUE)
  interactive_pilot_copy(temp, file.path(folder, "assets.json")); unlink(temp)
  message("Interactive Maps staged locally: ", folder, ". No publication.")
  checked <- validate_interactive_map_site(site_dir)
  # Keep the managed source folder bounded. Remote old immutable assets remain
  # available because publication does not delete objects absent locally.
  root <- normalizePath(folder,winslash="/",mustWork=TRUE)
  candidates <- list.files(folder,full.names=TRUE)
  managed <- grepl("^(current-[a-z0-9_]+|daily-[a-z]+-[0-9-]+|(precipitation|temperature|spi)-[0-9]{2}month)-[a-f0-9]{16}\\.bin$",basename(candidates)) |
    grepl("^snow-[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-f0-9]{16}\\.bin\\.gz$",basename(candidates)) |
    grepl("^(pilot|leaflet)-[a-f0-9]{12}\\.(js|css)$",basename(candidates))
  obsolete <- candidates[managed & !basename(candidates) %in% c(files,"assets.json")]
  if(length(obsolete)) {
    resolved <- normalizePath(obsolete,winslash="/",mustWork=TRUE)
    if(any(dirname(resolved)!=root)||any(file.info(resolved)$isdir)) stop("Refusing unsafe viewer asset cleanup.")
    unlink(resolved)
  }
  invisible(checked)
}

validate_interactive_map_site <- function(site_dir = "site", rendered = FALSE) {
  root <- if (rendered) file.path(site_dir, "_site") else site_dir
  folder <- file.path(root, "interactive-maps")
  if (!file.exists(file.path(folder, "assets.json"))) stop("Build the Interactive Maps site assets first: ", folder)
  assets <- jsonlite::read_json(file.path(folder, "assets.json"))
  files <- vapply(assets$files, `[[`, character(1), "file")
  expected <- vapply(assets$files, `[[`, character(1), "md5")
  paths <- file.path(folder, files)
  if (any(!file.exists(paths)) || !identical(unname(tools::md5sum(paths)), expected))
    stop("Interactive Maps assets missing or changed: ", folder)
  manifest <- jsonlite::read_json(file.path(folder, "manifest.json"))
  snow <- Filter(function(x) identical(x$compression, "gzip"), manifest$layers)
  if (!is.null(manifest$current$variables$snow) && !length(snow)) stop("Snow catalog has no verified payloads.")
  for (entry in snow) validate_interactive_snow_payload(entry, folder)
  if (length(snow)) {
    products <- Filter(function(x) identical(x$variable, "snow"), manifest$current$products)
    if (length(products) != 4L * length(snow)) stop("Snow metric catalog is incomplete.")
    for (id in names(snow)) {
      entries <- Filter(function(x) identical(x$layer_id, id), products)
      if (!setequal(vapply(entries, `[[`, character(1), "metric"), c("swe", "departure", "percent", "change")) ||
          length(entries) != 4L) stop("Snow metric links are incomplete: ", id)
      for (product in entries) if (!identical(product$period, snow[[id]]$date) ||
          !identical(product$date, snow[[id]]$date) ||
          !identical(isTRUE(product$available), product$metric != "change" || isTRUE(snow[[id]]$change_available)))
        stop("Snow metric date or availability mismatch: ", id)
    }
  }
  if (identical(manifest$snow_mode, "verified_current")) {
    release <- manifest$snow_release
    if (is.null(release) || length(snow) != 1L ||
        !identical(snow[[1L]]$date, release$date) ||
        !identical(snow[[1L]]$source_signature, release$source_signature) ||
        !identical(snow[[1L]]$change_available, release$change_available))
      stop("Snow viewer is not bound to its verified Current Snow release.")
    expected_images <- paste0("maps/generated/snodas/current/", c("swe-observed.png", "swe-departure.png",
      "swe-percent-median.png", if (isTRUE(release$change_available)) "swe-change-7day.png"))
    if (!identical(vapply(release$images, `[[`, character(1), "file"), expected_images)) stop("Invalid Snow release image catalog.")
    for (image in release$images) {
      path <- file.path(root, image$file)
      if (!file.exists(path) || !identical(unname(tools::md5sum(path)), image$md5))
        stop("Snow viewer and Current Snow images differ: ", image$file)
    }
  }
  page <- file.path(root, "pages", if (rendered) "interactive-maps.html" else "interactive-maps.qmd")
  content <- paste(readLines(page, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (!grepl("../interactive-maps/index.html?embedded=1", content, fixed = TRUE)) stop("Interactive Maps frame link missing.")
  if (rendered && !grepl('href="[^"]*interactive-maps\\.html"', content)) stop("Rendered navigation missing.")
  result <- data.frame(status = "PASS", assets = length(files), bytes = sum(file.info(paths)$size), rendered = rendered)
  print(result, row.names = FALSE)
  invisible(result)
}

# Independent of terra: checks the actual compressed source/rendered bytes.
validate_interactive_snow_payload <- function(entry, folder) {
  fail <- function() stop("Unverified compressed snow payload: ", entry$file, call. = FALSE)
  g <- entry$grid
  fields <- c("observed", "median", "departure", "percent", "change", "years", "percent_status", "departure_status")
  types <- c(rep("float64", 5L), rep("uint8", 3L))
  n <- g$rows * g$cols
  date <- tryCatch(as.Date(entry$date), error = function(e) as.Date(NA))
  prior <- tryCatch(as.Date(entry$change_start_date), error = function(e) as.Date(NA))
  if (length(n) != 1L || !is.finite(n) || n < 1 || n > 5000000 ||
      any(c(g$rows, g$cols) != floor(c(g$rows, g$cols))) ||
      !isTRUE(g$dx > 0 && g$dy > 0) ||
      !isTRUE(abs((g$east - g$west) - g$cols * g$dx) < 1e-8) ||
      !isTRUE(abs((g$north - g$south) - g$rows * g$dy) < 1e-8) ||
      !identical(names(entry$fields), fields) ||
      !identical(basename(entry$file), entry$file) ||
      !isTRUE(grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", entry$date)) ||
      !isTRUE(!is.na(date) && !is.na(prior) && prior == date - 7L)) fail()
  sizes <- ifelse(types == "float64", 8L, 1L)
  offsets <- c(0, head(cumsum(n * sizes), -1L))
  for (j in seq_along(fields)) if (!identical(entry$fields[[j]]$type, types[j]) ||
      !isTRUE(entry$fields[[j]]$offset == offsets[j])) fail()
  path <- file.path(folder, entry$file)
  if (!file.exists(path) || !isTRUE(file.info(path)$size == entry$transfer_bytes) ||
      !isTRUE(entry$bytes == n * sum(sizes)) ||
      !identical(unname(tools::md5sum(path)), entry$md5)) fail()
  con <- gzfile(path, "rb"); on.exit(close(con), add = TRUE)
  data <- list()
  for (j in seq_along(fields)) {
    value <- if (sizes[j] == 8L) readBin(con, "double", n, size = 8L, endian = "little") else
      as.numeric(readBin(con, "raw", n))
    if (length(value) != n) fail()
    if (sizes[j] == 1L) value[value == 255] <- NA_real_
    data[[fields[j]]] <- value
  }
  if (length(readBin(con, "raw", 1L))) fail()
  if (any(vapply(data, function(x) any(is.infinite(x)), logical(1)))) fail()
  if (any(data$observed < 0, na.rm = TRUE) || any(data$median < 0, na.rm = TRUE) ||
      any(!data$percent_status %in% 1:3) || any(!data$departure_status %in% 1:3) ||
      any(data$years < 0 | data$years > 21 | data$years != floor(data$years), na.rm = TRUE)) fail()
  observed <- is.finite(data$observed)
  supported <- observed & is.finite(data$median) & is.finite(data$years)
  eligible <- supported & data$years >= 18 & data$median >= 1
  low <- supported & data$years >= 18 & data$median < 1
  expected_status <- ifelse(eligible, 1L, ifelse(low, 2L, 3L))
  departure_supported <- supported & data$years >= 15
  if (!identical(as.integer(data$percent_status), as.integer(expected_status)) ||
      !identical(as.integer(data$departure_status), as.integer(ifelse(departure_supported,
        ifelse(data$median < 1, 2L, 1L), 3L)))) fail()
  if (!identical(is.finite(data$percent), eligible) ||
      any(data$percent[eligible] != 100 * data$observed[eligible] / data$median[eligible]) ||
      !identical(is.finite(data$departure), observed & is.finite(data$median)) ||
      any(data$departure[is.finite(data$departure)] != (data$observed - data$median)[is.finite(data$departure)]) ||
      any(is.finite(data$change) & !observed) ||
      (!isTRUE(entry$change_available) && any(is.finite(data$change))) ||
      (isTRUE(entry$change_available) && mean(is.finite(data$change)) < .8)) fail()
  invisible(TRUE)
}
