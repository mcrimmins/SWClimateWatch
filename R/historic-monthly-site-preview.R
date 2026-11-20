# Layout review only: construct a separate Quarto site under diagnostics.
historic_preview_source_parts <- function(lines) {
  climate <- which(lines %in% c("## Cool season", "## Climate summaries", "::: {.historic-review-notice}"))[1L]
  if (is.na(climate)) stop("Historic source page has no recognized climate section.")
  intro <- lines[seq_len(climate - 1L)]
  badge <- grep("archive-roni-badge", intro, fixed = TRUE)
  if (length(badge) != 1L) stop("Historic RONI badge is missing or ambiguous.")
  value <- regmatches(intro[badge], regexec("RONI ([+-]?[0-9]+(?:[.][0-9]+)?)", intro[badge], perl = TRUE))[[1L]]
  if (length(value) != 2L) stop("Historic RONI value cannot be verified.")
  number <- as.numeric(value[2L])
  intro[badge] <- paste0("[", swc_roni_strength_label(number), " \u00b7 RONI ",
    sprintf("%+.1f", number), " \u00b0C]{.archive-roni-badge}")
  starts <- which(lines == "::: {.dashboard-map-card}")
  cards <- lapply(starts, function(start) {
    depth <- 0L
    for (i in seq.int(start, length(lines))) {
      if (grepl("^::: +\\{", lines[i])) depth <- depth + 1L
      if (identical(lines[i], ":::")) depth <- depth - 1L
      if (depth == 0L) return(lines[start:i])
    }
    stop("Historic source has an unclosed map card.")
  })
  filenames <- c("maxt_departure.png", "mint_departure.png", "wet_day_count_percentile.png", "wet_day_intensity.png")
  daily <- unlist(lapply(filenames, function(name) {
    found <- vapply(cards, function(card) any(grepl(paste0("/", name, ")"), card, fixed = TRUE)), logical(1))
    if (sum(found) != 1L) stop("Historic detail map is missing or ambiguous: ", name)
    c(cards[[which(found)]], "")
  }), use.names = FALSE)
  snow_start <- which(lines == "<!-- BEGIN GENERATED SNODAS SNOW MAPS -->")
  snow_end <- which(lines == "<!-- END GENERATED SNODAS SNOW MAPS -->")
  snow <- character()
  if (length(snow_start) || length(snow_end)) {
    if (length(snow_start) != 1L || length(snow_end) != 1L || snow_end <= snow_start)
      stop("Historic Snow section is incomplete.")
    snow <- lines[snow_start:snow_end]
    snow <- snow[snow != "## Snow season"]
  }
  list(intro = intro, daily = daily, snow = snow, roni = number)
}

historic_preview_map_card <- function(row) {
  label <- historic_monthly_metrics()[[row$metric]]
  path <- paste0("../../maps/generated/prism/historic-monthly-pilot/", row$relative_map)
  description <- switch(row$metric,
    precipitation_total = "Total precipitation, in inches.",
    precipitation_rank = "Wet/dry standing among matching complete historical periods.",
    temperature_mean = "Average temperature over the selected period (\u00b0F).",
    temperature_departure = "Warmer or cooler than the matching 1991-2020 normal, in degrees F.",
    temperature_rank = "Warm/cold standing among matching complete historical periods.",
    spi12 = "October-September standardized precipitation; negative is drier, positive is wetter.")
  c("::: {.dashboard-map-card}", paste0("![", label, "](", path, "){loading=\"lazy\"}"), "",
    "::: {.archive-map-description}", description, ":::", "",
    "::: {.dashboard-card-actions}",
    paste0("[Open full-resolution PNG](", path, "){.btn .btn-sm .btn-outline-primary}"), ":::", ":::", "")
}

historic_preview_early_parts <- function(year) {
  if (length(year) != 1L || is.na(year) || year != floor(year) || year < 1896L || year >= 1982L)
    stop("Monthly-only pilot page years must be WY1896-WY1981.")
  list(intro = c("---", paste0('title: "Water year ', year, '"'),
    paste0('subtitle: "October 1, ', year - 1L, ' to September 30, ', year, '"'),
    "page-layout: full", "toc: false", "bread-crumbs: false", "body-classes: archive-year-page", "---", "",
    "Monthly PRISM reconstruction. Historical ENSO context has not been attached to this pilot year.", ""),
    daily = character(), snow = character(), roni = NA_real_)
}

historic_preview_page <- function(lines, records, parts = NULL) {
  if (is.null(parts)) parts <- historic_preview_source_parts(lines)
  years <- unique(records$water_year)
  if (length(years) != 1L) stop("Supply one year's preview maps.")
  year <- years[[1L]]; specs <- historic_monthly_periods()
  tabs <- unlist(lapply(seq_len(nrow(specs)), function(i) {
    spec <- specs[i, ]; rows <- records[records$period == spec$id, ]
    metric_order <- c("precipitation_rank", "temperature_departure", "precipitation_total", "temperature_mean", "temperature_rank", "spi12")
    rows <- rows[order(match(rows$metric, metric_order)), ]
    c(paste0("### ", spec$label), "", paste0(spec$definition, "."), "",
      ":::: {.dashboard-map-grid}",
      unlist(lapply(seq_len(nrow(rows)), function(j) historic_preview_map_card(rows[j, ])), use.names = FALSE),
      "::::", "")
  }), use.names = FALSE)
  snow <- if (length(parts$snow)) c(
    '<details class="historic-review-details"><summary>Snow season (October-May)</summary>', "",
    parts$snow, "", "</details>", "") else c(
    '<details class="historic-review-details"><summary>Snow availability</summary>', "",
    "The SNODAS seasonal archive begins in WY2005. No snow maps are substituted for this year.", "", "</details>", "")
  c(parts$intro,
    "::: {.historic-review-notice}", "Local layout review. The existing Historic Years archive is unchanged.", ":::", "",
    "## Climate summaries", "",
    sprintf("Retrospective ranks compare WY%d-WY%d; temperature departures use 1991-2020.",
      min(records$comparison_first_year), max(records$comparison_last_year)), "",
    "::::: {.panel-tabset}", tabs, ":::::", "",
    '<details class="historic-review-details"><summary>How to read these maps</summary>', "",
    "Cool season is October-March, spring is April-June, and monsoon is July-September. Together they cover the full water year without gaps or overlaps. July-September is a historical climate window rather than the June 15-September 30 meteorological monsoon season.", "",
    "Monthly PRISM precipitation totals require every month at each cell. Mean temperature uses monthly maximum/minimum means and actual day weights, including leap days. Missing months are not filled.", "",
    "Percentiles use matching completed-water-year periods over the displayed retrospective record, including the target once and including later years when describing older years. They require at least 30 years and 90% of eligible windows. Record categories include meaningful ties, require complete history, and suppress common-zero dry records.", "",
    "Temperature departures require at least 27 matching 1991-2020 reference seasons. September SPI-12 uses the fixed, zero-adjusted gamma-MLE calibration shown on its map; unsupported or poor-fit cells are withheld. SPI is precipitation-only, not a streamflow, temperature-demand or official drought measure.", "",
    if (is.finite(parts$roni))
      "The DJF RONI badge describes index-magnitude conditions, not an independently verified official ENSO episode. The existing historical value, period and source link are retained; no current CPC advisory is applied to a historical year. These maps do not attribute local conditions solely to ENSO."
    else "A verified historical DJF RONI value has not been attached to this pilot. No ENSO classification or current advisory is substituted. These maps do not attribute local conditions solely to ENSO.", "",
    "</details>", "",
    paste0('<details class="historic-review-details"><summary>',
      if (length(parts$daily)) "Daily-derived detail (October-March)" else "Daily-detail availability", "</summary>"), "",
    if (length(parts$daily)) c(
      "These retained maps use the existing daily PRISM archive. Wet-day ranks retain the WY1982-WY2025 daily comparison record, separately from the monthly ranks above. High/low temperature departures describe afternoons and nights separately; wet-day statistics require daily observations and cannot be reconstructed from monthly totals.", "",
      ":::: {.dashboard-map-grid}", parts$daily, "::::", "") else c(
      "Daily-derived detail is not included in this monthly-data pilot. Existing daily-detail maps cover WY1982-WY2025. Monthly grids cannot reconstruct daily extremes or wet-day statistics; no daily maps from another year are substituted.", ""),
    "</details>", "", snow)
}

historic_preview_copy <- function(from, to) {
  if (!file.exists(from)) stop("Missing local preview asset: ", from)
  dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
  hash <- unname(tools::md5sum(from))
  if (!file.exists(to) || !identical(hash, unname(tools::md5sum(to))))
    if (!file.copy(from, to, overwrite = TRUE)) stop("Could not copy preview asset: ", from)
  if (!identical(hash, unname(tools::md5sum(to)))) stop("Preview copy checksum mismatch.")
}

build_historic_monthly_site_preview <- function(
    pilot_dir = "data/diagnostics/historic-monthly-pilot",
    output_dir = "data/diagnostics/historic-monthly-site-preview", site_dir = "site", expected_years = NULL,
    allow_early = FALSE) {
  summary <- read.csv(file.path(pilot_dir, "summary.csv"))
  records <- read.csv(file.path(pilot_dir, "manifest.csv"), stringsAsFactors = FALSE)
  years <- sort(unique(records$water_year))
  if (summary$status != "READY" || !length(years) || summary$years != length(years) ||
      nrow(records) != historic_monthly_products_per_year() * length(years))
    stop("Build and check the complete requested monthly map set first.")
  if (!is.null(expected_years) && !identical(years, sort(as.integer(expected_years))))
    stop("Monthly maps do not cover the exact requested Historic Years pages.")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  root <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)
  allowed <- paste0(normalizePath("data/diagnostics", winslash = "/", mustWork = TRUE), "/")
  if (!startsWith(tolower(root), tolower(allowed))) stop("The preview must stay inside data/diagnostics.")
  inputs <- c(file.path(pilot_dir, c("manifest.csv", "summary.csv", "methods.txt")), records$map)
  plan <- list()
  for (year in years) {
    source <- file.path(site_dir, "pages/archive", paste0("wy", year, ".qmd"))
    rows <- records[records$water_year == year, ]
    if (year < 1982L && isTRUE(allow_early)) {
      page <- historic_preview_page(character(), rows, parts = historic_preview_early_parts(year))
    } else {
      if (!file.exists(source)) stop("Existing Historic Years source page is missing: ", year)
      inputs <- c(inputs, source)
      lines <- readLines(source, warn = FALSE, encoding = "UTF-8")
      page <- historic_preview_page(lines, rows)
    }
    destination <- file.path(root, "pages/archive", paste0("wy", year, ".qmd"))
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    writeLines(page, destination, useBytes = TRUE)
    for (i in seq_len(nrow(rows))) historic_preview_copy(rows$map[i],
      file.path(root, "maps/generated/prism/historic-monthly-pilot", rows$relative_map[i]))
    text <- paste(page, collapse = "\n")
    refs <- unique(regmatches(text, gregexpr("\\.\\./\\.\\./maps/[A-Za-z0-9_./-]+[.]png", text))[[1L]])
    old <- refs[!grepl("/historic-monthly-pilot/", refs, fixed = TRUE)]
    for (ref in old) {
      relative <- sub("^\\.\\./\\.\\./", "", ref)
      if (grepl("(^|/)[.][.]?(/|$)", relative)) stop("Unexpected parent path in historic map reference.")
      inputs <- c(inputs, file.path(site_dir, relative))
      historic_preview_copy(file.path(site_dir, relative), file.path(root, relative))
    }
    plan[[length(plan) + 1L]] <- data.frame(water_year = year, monthly_maps = nrow(rows),
      daily_detail_maps = sum(grepl("/prism/seasonal-archive/", old, fixed = TRUE)),
      snow_maps = sum(grepl("/snodas/", old, fixed = TRUE)),
      page = paste0("pages/archive/wy", year, ".qmd"))
  }
  logo <- "assets/branding/southwest-climate-watch-mark-transparent.png"
  for (relative in c("styles.css", logo)) {
    inputs <- c(inputs, file.path(site_dir, relative))
    historic_preview_copy(file.path(site_dir, relative), file.path(root, relative))
  }
  historic_preview_copy("scripts/historic-monthly-site-assets/preview.css", file.path(root, "preview.css"))
  inputs <- c(inputs, "scripts/historic-monthly-site-assets/preview.css")
  plan <- do.call(rbind, plan)
  if (any(plan$monthly_maps != 21L) || any(plan$daily_detail_maps != ifelse(plan$water_year < 1982L & isTRUE(allow_early), 0L, 4L)) ||
      any(plan$snow_maps != ifelse(plan$water_year >= 2005, 4L, 0L))) stop("Preview content counts differ from the selected scope.")
  config <- list(project = list(type = "website", `output-dir` = "_site",
    render = c("index.qmd", plan$page), resources = c("maps/**", "assets/**")),
    website = list(title = "Southwest Climate Watch", search = FALSE,
      sidebar = list(style = "docked", background = "light", title = "Southwest Climate Watch",
        logo = logo, `logo-alt` = "Southwest Climate Watch", contents = c(
          list(list(href = "index.qmd", text = "Local archive review")),
          list(list(section = "Historic Years", contents = historic_preview_navigation(years)))),
        footer = "Local layout review. Published archive unchanged."),
      `page-footer` = list(left = "Southwest Climate Watch", right = "Historic Years local review")),
    format = list(html = list(theme = list(light = "flatly", dark = "darkly"),
      css = c("styles.css", "preview.css"), toc = FALSE, `link-external-newwindow` = TRUE)))
  # Quarto's YAML 1.2 reader needs true/false, not yaml's default yes/no.
  yaml::write_yaml(config, file.path(root, "_quarto.yml"), handlers = list(
    logical = function(x) structure(ifelse(x, "true", "false"), class = "verbatim")))
  writeLines(c("---", 'title: "Historic Years - local layout review"', "toc: false", "---", "",
    sprintf(if (any(years < 1982L))
      "Review %d earlier Historic Years pages with monthly maps and explicit daily-detail, Snow and ENSO availability notes. The published archive is unchanged."
      else "Review %d Historic Years pages with the new monthly maps, retained daily-derived detail and available seasonal snow. The published archive is unchanged.", length(years)), "",
    sprintf("- [Water year %d](pages/archive/wy%d.qmd)", years, years), "",
    "Each page has 21 monthly maps in Water year / Cool season / Spring / Monsoon tabs. Daily-derived detail and snow open as grouped sections below. Map links open full-resolution PNGs."), file.path(root, "index.qmd"))
  write.csv(plan, file.path(root, "preview-plan.csv"), row.names = FALSE)
  inputs <- unique(inputs)
  write.csv(data.frame(path = inputs, md5 = unname(tools::md5sum(inputs))), file.path(root, "source-checksums.csv"), row.names = FALSE)
  outputs <- c("_quarto.yml", "index.qmd", "styles.css", "preview.css", "preview-plan.csv", plan$page,
    paste0("maps/", list.files(file.path(root, "maps"), recursive = TRUE, full.names = FALSE)), logo)
  # Store only paths relative to this isolated preview, independent of render output.
  write.csv(data.frame(file = outputs, md5 = unname(tools::md5sum(file.path(root, outputs)))),
    file.path(root, "output-checksums.csv"), row.names = FALSE)
  validate_historic_monthly_site_preview(root, rendered = FALSE, allow_early = allow_early)
  root
}

historic_preview_navigation <- function(years) {
  link <- function(year) list(href = paste0("pages/archive/wy", year, ".qmd"), text = paste("Water year", year))
  if (length(years) <= 10L) return(lapply(years, link))
  years <- sort(years, decreasing = TRUE)
  decades <- unique(years %/% 10L * 10L)
  lapply(decades, function(decade) list(section = paste0(decade, "s"),
    contents = lapply(years[years >= decade & years < decade + 10L], link)))
}

validate_historic_monthly_site_preview <- function(root = "data/diagnostics/historic-monthly-site-preview", rendered = TRUE, expected_years = NULL,
    allow_early = FALSE) {
  inputs <- read.csv(file.path(root, "source-checksums.csv"), stringsAsFactors = FALSE)
  outputs <- read.csv(file.path(root, "output-checksums.csv"), stringsAsFactors = FALSE)
  if (anyNA(inputs$md5) || !identical(unname(tools::md5sum(inputs$path)), inputs$md5))
    stop("Preview inputs changed; rebuild the local page preview.")
  if (anyNA(outputs$md5) || !identical(unname(tools::md5sum(file.path(root, outputs$file))), outputs$md5))
    stop("Copied preview content changed; rebuild before review.")
  plan <- read.csv(file.path(root, "preview-plan.csv"), stringsAsFactors = FALSE)
  if (!nrow(plan) || anyDuplicated(plan$water_year) || any(plan$monthly_maps != 21L) ||
      any(plan$water_year < 1982L & !isTRUE(allow_early)) ||
      any(plan$daily_detail_maps != ifelse(plan$water_year < 1982L, 0L, 4L)) || any(plan$snow_maps != ifelse(plan$water_year >= 2005L, 4L, 0L)))
    stop("Preview plan does not contain complete Historic Years pages.")
  if (!is.null(expected_years) && !identical(sort(plan$water_year), sort(as.integer(expected_years))))
    stop("Rendered plan is missing or has extra Historic Years pages.")
  if (rendered) for (i in seq_len(nrow(plan))) {
    path <- file.path(root, "_site", sub("[.]qmd$", ".html", plan$page[i]))
    doc <- xml2::read_html(path)
    tabs <- trimws(xml2::xml_text(xml2::xml_find_all(doc, "//*[@role='tab']")))
    if (!identical(tabs, historic_monthly_periods()$label)) stop("Rendered period tabs differ from the pilot scope.")
    refs <- unique(xml2::xml_attr(xml2::xml_find_all(doc, "//img"), "src"))
    refs <- refs[!is.na(refs) & grepl("^\\.\\./\\.\\./maps/", refs)]
    if (length(refs) != plan$monthly_maps[i] + plan$daily_detail_maps[i] + plan$snow_maps[i])
      stop("A rendered page has missing or unexpected map images.")
    if (sum(grepl("/historic-monthly-pilot/", refs, fixed = TRUE)) != 21L ||
        sum(grepl("/prism/seasonal-archive/", refs, fixed = TRUE)) != plan$daily_detail_maps[i] ||
        sum(grepl("/snodas/", refs, fixed = TRUE)) != plan$snow_maps[i])
      stop("Rendered monthly, daily-detail or Snow group has the wrong images.")
    for (ref in refs) {
      relative <- sub("^\\.\\./\\.\\./", "", ref)
      index <- match(relative, outputs$file)
      if (is.na(index) || !file.exists(file.path(dirname(path), ref)) ||
          !identical(unname(tools::md5sum(file.path(dirname(path), ref))), outputs$md5[index]))
        stop("Rendered preview map is missing or differs from its source: ", ref)
    }
    html <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    if (grepl("googletagmanager|gtag[(]", html)) stop("Preview analytics scope is invalid.")
    if (plan$water_year[i] >= 1982L) {
      if (!grepl("range conditions", xml2::xml_text(doc), fixed = TRUE)) stop("Rendered RONI wording is invalid.")
    } else if (!grepl("Historical ENSO context has not been attached", xml2::xml_text(doc), fixed = TRUE) ||
        grepl("archive-roni-badge|range conditions", html) ||
        !grepl("no daily maps from another year", xml2::xml_text(doc), fixed = TRUE))
      stop("Monthly-only pilot has an unsupported historical context or missing availability note.")
    if (length(xml2::xml_find_all(doc, "//details[@class='historic-review-details' and not(@open)]")) != 3L)
      stop("Expected methods, daily-detail and Snow sections collapsed by default.")
  }
  result <- data.frame(status = "PASS", pages = nrow(plan), monthly_maps = sum(plan$monthly_maps),
    daily_detail_maps = sum(plan$daily_detail_maps), snow_maps = sum(plan$snow_maps), rendered = rendered)
  write.csv(result, file.path(root, if (rendered) "rendered-status.csv" else "source-status.csv"), row.names = FALSE)
  result
}
