# Portable, cached publication of the reviewed monthly Historic Years archive.
historic_monthly_release_root <- function() "data/processed/historic-monthly-release"

historic_monthly_release_records <- function(root = historic_monthly_release_root(), expected_years = 1982:2025) {
  if (!file.exists(file.path(root, "release.json")) || !file.exists(file.path(root, "manifest.csv")))
    stop("Historic monthly publication bundle is missing. Transfer the complete verified release first.")
  seal <- jsonlite::read_json(file.path(root, "release.json"), simplifyVector = TRUE)
  manifest <- file.path(root, "manifest.csv")
  if (!identical(seal$status, "READY") ||
      !identical(unname(tools::md5sum(manifest)), seal$manifest_md5)) stop("Historic monthly release is incomplete or changed.")
  rows <- read.csv(manifest, stringsAsFactors = FALSE)
  if (!all(c("water_year", "period", "metric", "start", "end", "relative_map", "md5") %in% names(rows)) || anyNA(rows))
    stop("Historic monthly manifest is incomplete.")
  wanted <- do.call(rbind, lapply(expected_years, function(year) {
    windows <- historic_monthly_windows(year)
    do.call(rbind, lapply(seq_len(nrow(windows)), function(i) {
      metrics <- names(historic_monthly_metrics())[1:5]
      if (windows$period[i] == "water-year") metrics <- c(metrics, "spi12")
      data.frame(water_year = year, period = windows$period[i], metric = metrics,
        start = windows$start[i], end = windows$end[i])
    }))
  }))
  key <- function(x) paste(x$water_year, x$period, x$metric, x$start, x$end)
  if (anyDuplicated(key(rows)) || !setequal(key(rows), key(wanted))) stop("Historic monthly release year/product/date coverage differs from the required archive.")
  safe <- paste0("wy", rows$water_year, "/", rows$period, "/", rows$metric, ".png")
  if (!identical(rows$relative_map, safe)) stop("Unsafe or unexpected historic map paths.")
  paths <- file.path(root, "maps", safe)
  if (any(!file.exists(paths)) || !identical(unname(tools::md5sum(paths)), rows$md5)) stop("Historic monthly release PNG checksum mismatch.")
  rows
}

export_historic_monthly_release <- function(source_dir = "data/diagnostics/historic-monthly-archive",
    root = historic_monthly_release_root(), expected_years = 1982:2025) {
  rows <- read.csv(file.path(source_dir, "manifest.csv"), stringsAsFactors = FALSE)
  validated <- read.csv(file.path(source_dir, "validation-status.csv"))
  if (!identical(validated$status, "PASS") || validated$monthly_maps != nrow(rows)) stop("Validate the complete local archive before export.")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  lock <- filelock::lock(file.path(root, "export.lock"), timeout = 0)
  if (is.null(lock)) stop("Another Historic Years export is running.")
  on.exit(filelock::unlock(lock), add = TRUE)
  # A partial/resumed export can never be mistaken for the last complete release.
  jsonlite::write_json(list(status = "BUILDING"), file.path(root, "release.json"), auto_unbox = TRUE)
  policy <- prism_monthly_spi_policy()
  renderer <- historic_monthly_signature(body(historic_monthly_plot), body(save_southwest_map),
    historic_monthly_code_signature(), policy, "publication-footer-v1")
  for (i in seq_len(nrow(rows))) {
    row <- rows[i, ]; map <- file.path(root, "maps", row$relative_map)
    checkpoint <- paste0(map, ".rds")
    signature <- historic_monthly_signature(renderer, unname(tools::md5sum(row$grid)), row)
    old <- if (file.exists(checkpoint)) readRDS(checkpoint) else NULL
    reuse <- !is.null(old) && identical(old$signature, signature) && file.exists(map) &&
      identical(old$md5, unname(tools::md5sum(map)))
    if (!reuse) {
      message("[", i, "/", nrow(rows), "] Publication map: WY", row$water_year, " ", row$period, " ", row$metric)
      window <- historic_monthly_windows(row$water_year)
      window <- window[window$period == row$period, ]
      layer <- switch(row$metric, precipitation_rank = "precipitation_display",
        temperature_rank = "temperature_display", spi12 = "display_class", row$metric)
      raster <- terra::rast(row$grid)[[layer]]
      product <- historic_monthly_plot(raster, row$metric, window,
        seq.int(row$comparison_first_year, row$comparison_last_year), 1991:2020, policy,
        seq.int(1896L, policy$calibration_end))
      product$footer <- sub(" | Local pilot, not published", "", product$footer, fixed = TRUE)
      dir.create(dirname(map), recursive = TRUE, showWarnings = FALSE)
      save_southwest_map(product$plot, map, logo_path = southwest_brand_logo_path(), footer_text = product$footer)
      saveRDS(list(signature = signature, md5 = unname(tools::md5sum(map))), checkpoint)
    }
  }
  rows$grid <- NULL; rows$map <- NULL
  rows$md5 <- unname(tools::md5sum(file.path(root, "maps", rows$relative_map)))
  write.csv(rows, file.path(root, "manifest.csv"), row.names = FALSE)
  jsonlite::write_json(list(status = "READY", years = length(unique(rows$water_year)), maps = nrow(rows),
    manifest_md5 = unname(tools::md5sum(file.path(root, "manifest.csv")))),
    file.path(root, "release.json"), auto_unbox = TRUE, pretty = TRUE)
  invisible(historic_monthly_release_records(root, expected_years))
}

historic_monthly_publication_page <- function(lines, rows, parts = NULL) {
  page <- historic_preview_page(lines, rows, parts = parts)
  notice <- which(page == "::: {.historic-review-notice}")
  if (length(notice) != 1L) stop("Could not identify local-only review notice.")
  page <- page[-seq.int(notice, notice + 3L)]
  page <- gsub("historic-monthly-pilot/", "historic-monthly/", page, fixed = TRUE)
  c(page, "", "<!-- HISTORIC MONTHLY RELEASE -->")
}

stage_historic_monthly_release <- function(root = historic_monthly_release_root(), site_dir = "site", expected_years = 1982:2025) {
  rows <- historic_monthly_release_records(root, expected_years)
  pages <- file.path(site_dir, "pages/archive", paste0("wy", sort(unique(rows$water_year)), ".qmd"))
  # Construct all pages before changing any. Preserve each VM's own Snow section.
  planned <- lapply(pages, function(path) {
    year <- as.integer(sub("wy([0-9]+)[.]qmd$", "\\1", basename(path)))
    selected <- rows[rows$water_year == year, ]
    if (year < 1982L) historic_monthly_publication_page(character(), selected, historic_preview_early_parts(year))
    else historic_monthly_publication_page(readLines(path, warn = FALSE), selected)
  })
  for (i in seq_len(nrow(rows))) historic_preview_copy(file.path(root, "maps", rows$relative_map[i]),
    file.path(site_dir, "maps/generated/prism/historic-monthly", rows$relative_map[i]))
  css <- readLines("scripts/historic-monthly-site-assets/preview.css", warn = FALSE)
  for (i in seq_along(pages)) {
    # Page-scoped styles avoid changing the rest of the site's tab layouts.
    style <- c("", "```{=html}", "<style>", css, "</style>", "```", "")
    dir.create(dirname(pages[i]), recursive = TRUE, showWarnings = FALSE)
    writeLines(c(planned[[i]], style), pages[i], useBytes = TRUE)
  }
  invisible(validate_historic_monthly_publication(root, site_dir, rendered = FALSE, expected_years = expected_years))
}

validate_historic_monthly_publication <- function(root = historic_monthly_release_root(), site_dir = "site", rendered = TRUE, expected_years = 1982:2025) {
  rows <- historic_monthly_release_records(root, expected_years)
  for (year in sort(unique(rows$water_year))) {
    source <- file.path(site_dir, "pages/archive", paste0("wy", year, ".qmd"))
    page <- readLines(source, warn = FALSE)
    selected <- rows[rows$water_year == year, ]
    refs <- paste0("../../maps/generated/prism/historic-monthly/", selected$relative_map)
    if (sum(page == "<!-- HISTORIC MONTHLY RELEASE -->") != 1L ||
        any(grepl("Local layout review", page, fixed = TRUE)) ||
        !identical(sub("### ", "", page[startsWith(page, "### ")]), historic_monthly_periods()$label)) stop("Historic monthly source layout is incorrect: ", year)
    image_count <- 21L + ifelse(year >= 1982L, 4L, 0L) + ifelse(year >= 2005L, 4L, 0L)
    if (year < 1982L && (any(grepl("\\]\\{[.]archive-roni-badge\\}|/seasonal-archive/", page)) ||
        !any(grepl("Historical ENSO context has not been attached", page, fixed = TRUE)) ||
        !any(grepl("no daily maps from another year", page, fixed = TRUE)) ||
        !any(grepl("SNODAS seasonal archive begins in WY2005", page, fixed = TRUE))))
      stop("Early Historic Years availability or ENSO context is incorrect: ", year)
    if (sum(startsWith(trimws(page), "![")) != image_count)
      stop("Historic daily-detail or Snow image count changed: ", year)
    for (ref in refs) if (sum(grepl(paste0("](", ref, ")"), page, fixed = TRUE)) != 2L) stop("Missing/duplicate historic monthly source link: ", ref)
    targets <- file.path(site_dir, "maps/generated/prism/historic-monthly", selected$relative_map)
    if (!identical(unname(tools::md5sum(targets)), selected$md5)) stop("Historic source PNG checksum mismatch: ", year)
    if (rendered) {
      html <- xml2::read_html(file.path(site_dir, "_site/pages/archive", paste0("wy", year, ".html")))
      imgs <- xml2::xml_attr(xml2::xml_find_all(html, "//img[@src]"), "src")
      if (sum(startsWith(imgs, "../../maps/generated/"), na.rm = TRUE) != image_count)
        stop("Historic rendered daily-detail or Snow image count changed: ", year)
      links <- xml2::xml_attr(xml2::xml_find_all(html, "//a[@href]"), "href")
      for (ref in refs) if (sum(imgs == ref) != 1L || sum(links == ref) != 1L) stop("Historic rendered link mismatch: ", ref)
      if (!identical(unname(tools::md5sum(file.path(site_dir, "_site/maps/generated/prism/historic-monthly", selected$relative_map))), selected$md5)) stop("Historic rendered PNG checksum mismatch: ", year)
      tabs <- trimws(xml2::xml_text(xml2::xml_find_all(html, "//a[@role='tab']")))
      if (!identical(tabs, historic_monthly_periods()$label)) stop("Historic rendered season tabs mismatch: ", year)
      if (year < 1982L) {
        text <- xml2::xml_text(html)
        if (length(xml2::xml_find_all(html, "//*[contains(@class,'archive-roni-badge')]")) ||
            !grepl("no daily maps from another year", text, fixed = TRUE) ||
            !grepl("SNODAS seasonal archive begins in WY2005", text, fixed = TRUE) ||
            !grepl("Historical ENSO context has not been attached", text, fixed = TRUE))
          stop("Early Historic Years rendered availability or ENSO context is incorrect: ", year)
      }
    }
  }
  result <- data.frame(status = "PASS", years = length(unique(rows$water_year)), monthly_maps = nrow(rows), rendered = rendered)
  report_dir <- if (all(rows$water_year < 1982L)) "data/diagnostics/historic-monthly-backfill-publication" else "data/diagnostics/historic-monthly-publication"
  dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
  write.csv(result, file.path(report_dir, "summary.csv"), row.names = FALSE)
  result
}
