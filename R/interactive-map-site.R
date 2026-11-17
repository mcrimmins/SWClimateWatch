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
    if (!file.exists(from) || file.info(from)$size != entry$bytes || !file.exists(receipt) ||
        !identical(readLines(receipt), unname(tools::md5sum(from)))) stop("Unverified pilot payload: ", from)
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
  page <- file.path(root, "pages", if (rendered) "interactive-maps.html" else "interactive-maps.qmd")
  content <- paste(readLines(page, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (!grepl("../interactive-maps/index.html?embedded=1", content, fixed = TRUE)) stop("Interactive Maps frame link missing.")
  if (rendered && !grepl('href="[^"]*interactive-maps\\.html"', content)) stop("Rendered navigation missing.")
  result <- data.frame(status = "PASS", assets = length(files), bytes = sum(file.info(paths)$size), rendered = rendered)
  print(result, row.names = FALSE)
  invisible(result)
}
