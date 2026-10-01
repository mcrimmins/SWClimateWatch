# Current-season SNODAS maps are updated separately from the PRISM workflow.
# Source the SNODAS daily updater and SWE map pilot modules first.

snodas_current_site_latest_date <- function(plan, today = Sys.Date()) {
  season <- snodas_update_season(today)
  if (is.null(season)) return(as.Date(NA_character_))
  if (!is.data.frame(plan) ||
      !all(c("date", "processed") %in% names(plan))) {
    stop("Expected a SNODAS daily update plan.", call. = FALSE)
  }
  if (!nrow(plan)) return(as.Date(NA_character_))
  dates <- as.Date(plan$date)
  if (anyNA(dates) || !is.logical(plan$processed) ||
      anyNA(plan$processed)) {
    stop("Invalid SNODAS dates or processed flags.", call. = FALSE)
  }
  available <- dates[plan$processed & dates >= season$start &
                       dates <= season$end]
  if (!length(available)) as.Date(NA_character_) else max(available)
}

snodas_current_site_page_text <- function(water_year, date = as.Date(NA_character_)) {
  if (length(water_year) != 1L || !is.numeric(water_year) ||
      is.na(water_year) || water_year != floor(water_year) ||
      water_year < 2005L) {
    stop("Invalid SNODAS water year.", call. = FALSE)
  }
  date <- as.Date(date)
  if (length(date) != 1L) stop("Expected one map date.", call. = FALSE)
  lines <- c(
    "---", 'title: "Current snow conditions"',
    "page-layout: full", "toc: false", "bread-crumbs: false",
    "body-classes: snow-current-page", "---", "",
    paste0("SNODAS water year ", water_year,
           " covers October 1, ", water_year - 1L, " through May 31, ",
           water_year, ". Snow water equivalent (SWE) is modeled snowpack ",
           "water, not daily snowfall. The maps use the latest verified ",
           "regional data available, which may lag today's date."), ""
  )
  if (is.na(date)) {
    return(c(lines,
      "::: {.dashboard-note}",
      "Current-season snow maps are waiting for a listed, verified SNODAS ",
      "archive that passes the map-quality check. Check back after the ",
      "source posts new data.", ":::"))
  }
  pretty_date <- sub(" 0", " ", format(date, "%B %d, %Y"), fixed = TRUE)
  # This page is in site/pages/, one level below the site root.
  root <- "../maps/generated/snodas/current/"
  card <- function(filename, alt, description) c(
    "::: {.dashboard-map-card}",
    paste0("![](", root, filename, '){fig-alt="', alt, '"}'), "",
    "::: {.archive-map-description}", description, ":::", "",
    "::: {.dashboard-card-actions}",
    paste0("[Open full-resolution PNG](", root, filename,
           "){.btn .btn-sm .btn-outline-primary}"),
    ":::", ":::", ""
  )
  c(lines, paste0("**Latest map date: ", pretty_date, "**"), "",
    "::: {.dashboard-map-grid}",
    card("swe-observed.png",
         "Observed snow water equivalent across Arizona and New Mexico",
         "Modeled SWE on the map date, in inches. Pale areas may be snow-free; missing data remain uncolored."),
    card("swe-departure.png",
         "Snow water equivalent departure from the seasonal median",
         "Observed SWE minus the centered-five-day WY2005-WY2025 median for this calendar date, in inches. Positive values indicate more snow water than the reference median."),
    ":::", "",
    "SNODAS is a modeled 06:00 UTC snowpack snapshot supplied by NOAA/NSIDC.",
    "The departure is an absolute difference, not a percentile or snowfall total.")
}

write_snodas_current_site_page <- function(
    water_year, date = as.Date(NA_character_),
    page_path = file.path("site", "pages", "current-snow.qmd")) {
  lines <- snodas_current_site_page_text(water_year, date)
  if (file.exists(page_path) &&
      identical(readLines(page_path, warn = FALSE), lines)) {
    return(invisible(FALSE))
  }
  dir.create(dirname(page_path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, page_path, useBytes = TRUE)
  invisible(TRUE)
}

snodas_current_site_source_signature <- function(
    date, processed_dir = swc_paths$processed,
    climatology_root = snodas_climatology_output_root(
      2005:2025, processed_dir)) {
  date <- snodas_date(date)
  reference <- snodas_climatology_day_paths(climatology_root,
                                           format(date, "%m-%d"))
  paths <- c(swe = snodas_processed_path(date, "swe", processed_dir),
             depth = snodas_processed_path(date, "depth", processed_dir),
             median_swe = reference[["median_swe"]],
             reference_marker = reference[["complete"]])
  if (!all(file.exists(paths))) {
    stop("Current SNODAS maps need verified daily and reference files.",
         call. = FALSE)
  }
  digest::digest(c(as.character(date), unname(tools::md5sum(paths))),
                 algo = "sha256")
}

snodas_current_site_manifest <- function(path) {
  if (!file.exists(path)) return(NULL)
  row <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE),
                  error = function(error) NULL)
  required <- c("water_year", "date", "source_signature", "observed_md5",
                "departure_md5", "page_md5")
  if (is.null(row) || nrow(row) != 1L ||
      !all(required %in% names(row)) || anyNA(row[required])) return(NULL)
  row
}

snodas_current_site_is_current <- function(
    water_year, date, signature, paths, page_path, manifest_path) {
  row <- snodas_current_site_manifest(manifest_path)
  if (is.null(row) || !all(file.exists(c(paths, page_path))) ||
      row$water_year[[1L]] != water_year ||
      row$date[[1L]] != as.character(date) ||
      row$source_signature[[1L]] != signature) return(FALSE)
  identical(unname(tools::md5sum(paths[["observed"]])),
            row$observed_md5[[1L]]) &&
    identical(unname(tools::md5sum(paths[["departure"]])),
              row$departure_md5[[1L]]) &&
    identical(unname(tools::md5sum(page_path)), row$page_md5[[1L]])
}

update_snodas_current_site <- function(
    plan, today = Sys.Date(),
    processed_dir = swc_paths$processed,
    climatology_root = snodas_climatology_output_root(
      2005:2025, processed_dir),
    site_map_dir = file.path("site", "maps", "generated", "snodas", "current"),
    page_path = file.path("site", "pages", "current-snow.qmd"),
    diagnostics_dir = file.path("data", "diagnostics", "snodas-current-site"),
    build_maps = function(date, output_dir, processed_dir, climatology_root) {
      build_snodas_swe_map_pilot(
        date = date, output_dir = output_dir,
        processed_dir = processed_dir, climatology_root = climatology_root,
        overwrite = TRUE, scale_type = "categorical")
    }) {
  season <- snodas_update_season(today)
  if (is.null(season)) return(list(status = "OUT_OF_SEASON"))
  manifest_path <- file.path(diagnostics_dir, "publication.csv")
  prior <- snodas_current_site_manifest(manifest_path)
  if (is.null(prior) || prior$water_year[[1L]] != season$water_year) {
    write_snodas_current_site_page(season$water_year,
                                   page_path = page_path)
  }
  date <- snodas_current_site_latest_date(plan, today)
  if (is.na(date)) {
    return(list(status = "WAITING", water_year = season$water_year,
                date = date))
  }
  signature <- snodas_current_site_source_signature(
    date, processed_dir, climatology_root)
  paths <- setNames(file.path(site_map_dir,
                              c("swe-observed.png", "swe-departure.png")),
                    c("observed", "departure"))
  if (snodas_current_site_is_current(
        season$water_year, date, signature, paths, page_path,
        manifest_path)) {
    return(list(status = "UNCHANGED", water_year = season$water_year,
                date = date, paths = paths))
  }
  pilot <- build_maps(date, file.path(diagnostics_dir, "latest"),
                      processed_dir, climatology_root)
  if (!is.list(pilot) || !is.data.frame(pilot$gate) ||
      nrow(pilot$gate) != 1L ||
      !all(c("status", "reasons") %in% names(pilot$gate)) ||
      anyNA(pilot$gate[c("status", "reasons")])) {
    stop("SNODAS map build did not return a quality gate.", call. = FALSE)
  }
  if (!identical(pilot$gate$status[[1L]], "PASS")) {
    message("SNODAS current map held by quality gate: ",
            pilot$gate$status[[1L]], " - ", pilot$gate$reasons[[1L]])
    return(list(status = "HELD", water_year = season$water_year,
                date = date, gate = pilot$gate))
  }
  if (is.null(pilot$paths) ||
      !all(c("observed", "departure") %in% names(pilot$paths))) {
    stop("SNODAS map build omitted an image.", call. = FALSE)
  }
  sources <- pilot$paths[c("observed", "departure")]
  if (!all(file.exists(sources)) ||
      any(file.info(sources)$size <= 0) ||
      any(vapply(sources, function(path) {
        inherits(try(magick::image_read(path), silent = TRUE), "try-error")
      }, logical(1)))) {
    stop("SNODAS map build did not produce two readable PNGs.",
         call. = FALSE)
  }
  dir.create(site_map_dir, recursive = TRUE, showWarnings = FALSE)
  for (name in names(paths)) {
    if (!file.copy(sources[[name]], paths[[name]], overwrite = TRUE) ||
        !identical(unname(tools::md5sum(sources[[name]])),
                   unname(tools::md5sum(paths[[name]])))) {
      stop("Could not stage SNODAS current map: ", name, call. = FALSE)
    }
  }
  write_snodas_current_site_page(season$water_year, date, page_path)
  dir.create(diagnostics_dir, recursive = TRUE, showWarnings = FALSE)
  row <- data.frame(
    water_year = season$water_year, date = as.character(date),
    source_signature = signature,
    observed_md5 = unname(tools::md5sum(paths[["observed"]])),
    departure_md5 = unname(tools::md5sum(paths[["departure"]])),
    page_md5 = unname(tools::md5sum(page_path)),
    published_utc = format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC", tz = "UTC"))
  utils::write.csv(row, manifest_path, row.names = FALSE)
  message("Staged SNODAS current maps for ", date, ".")
  list(status = "STAGED", water_year = season$water_year, date = date,
       paths = paths, gate = pilot$gate)
}
