# Isolated presentation pilot. Reuses existing maps and catalog descriptions.
temperature_preview_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub('"', "&quot;", x, fixed = TRUE)
  gsub("<", "&lt;", x, fixed = TRUE)
}

temperature_preview_page <- function(kind, products) {
  variables <- c(maxt = "Maximum", tmean = "Mean", mint = "Minimum")
  periods <- if (kind == "values") "daily" else c("daily", "30day")
  title <- if (kind == "values") "Temperature values" else "Temperature departures"
  lines <- c('---', paste0('title: "', title, '"'), 'page-layout: full', 'toc: false', '---', '', '```{=html}',
    sprintf('<div class="temperature-tabs-preview" data-kind="%s">', kind),
    '<p class="temperature-preview-note">Local layout review · Existing PRISM maps; dates are shown on each map.</p>')
  if (kind == "departures") lines <- c(lines,
    '<div class="temperature-period-control"><label for="temperature-period">Time period</label> <select id="temperature-period"><option value="daily">Daily</option><option value="30day">30-day mean</option></select></div>')
  lines <- c(lines, '<div class="temperature-variable-tabs" role="tablist" aria-label="Temperature variable">')
  for (variable in names(variables)) lines <- c(lines,
    sprintf('<button type="button" id="temperature-tab-%s" role="tab" aria-controls="temperature-panel-%s">%s</button>', variable, variable, variables[[variable]]))
  lines <- c(lines, '</div>')
  for (variable in names(variables)) {
    lines <- c(lines, sprintf('<section id="temperature-panel-%s" role="tabpanel" aria-labelledby="temperature-tab-%s"><h2 class="temperature-fallback-title">%s temperature</h2>', variable, variable, variables[[variable]]))
    for (period in periods) {
      id <- if (kind == "values") paste0(variable, "_value") else paste0(variable, "_departure_", period)
      p <- products[[id]]; src <- paste0("maps/", basename(p$image))
      lines <- c(lines, sprintf('<div class="temperature-map" data-period="%s" data-product="%s"><a class="temperature-map-link" href="%s" target="_blank" rel="noopener"><img src="%s" alt="%s" loading="lazy"></a><p class="temperature-description">%s</p><p><a href="%s" target="_blank" rel="noopener">Open full-resolution PNG</a> · <a href="individual/%s.html">Original individual map page</a></p></div>',
        period, id, src, src, temperature_preview_escape(p$label), temperature_preview_escape(p$description), src, id))
    }
    lines <- c(lines, '</section>')
  }
  c(lines, '</div><script src="temperature-tabs.js"></script>', '```')
}

precipitation_preview_page <- function(kind, products) {
  periods <- if (kind == "totals") c(1L, 7L, 30L, 90L) else c(7L, 30L, 90L)
  title <- if (kind == "totals") "Precipitation totals" else "Precipitation percentile ranks"
  lines <- c('---', paste0('title: "', title, '"'), 'page-layout: full', 'toc: false', '---', '', '```{=html}',
    '<div class="precipitation-period-preview">',
    '<p class="temperature-preview-note">Local layout review · Existing PRISM maps; dates are shown on each map.</p>',
    '<div class="temperature-period-control"><label for="precipitation-period">Time period</label> <select id="precipitation-period">')
  for (period in periods) lines <- c(lines, sprintf('<option value="%d">%s</option>', period,
    if (period == 1) "1 day" else paste(period, "days")))
  lines <- c(lines, '</select></div>')
  for (period in periods) {
    id <- sprintf(if (kind == "totals") "pcpn_total_%02dday" else "pcpn_percentile_%02dday", period)
    p <- products[[id]]; src <- paste0("maps/", basename(p$image))
    lines <- c(lines, sprintf('<div class="temperature-map" data-period="%d" data-product="%s"><h2 class="precipitation-fallback-title">%s</h2><a href="%s" target="_blank" rel="noopener"><img src="%s" alt="%s" loading="lazy"></a><p class="temperature-description">%s</p><p><a href="%s" target="_blank" rel="noopener">Open full-resolution PNG</a> · <a href="individual/%s.html">Original individual map page</a></p></div>',
      period, id, p$label, src, src, temperature_preview_escape(p$label), temperature_preview_escape(p$description), src, id))
  }
  c(lines, '</div><script src="precipitation-periods.js"></script>', '```')
}

build_temperature_tabs_preview <- function(output_dir = "data/diagnostics/temperature-tabs-preview",
    site_dir = "site", catalog_path = "config/map-products.yml") {
  catalog <- yaml::read_yaml(catalog_path)$products
  source("R/current-map-groups-preview.R")
  groups <- current_preview_groups()
  catalog <- c(catalog, current_preview_snow_products())
  ids <- c(paste0(c("maxt", "tmean", "mint"), "_value"),
    paste0(rep(c("maxt", "tmean", "mint"), 2), "_departure_", rep(c("daily", "30day"), each = 3)),
    sprintf("pcpn_total_%02dday", c(1L,7L,30L,90L)), sprintf("pcpn_percentile_%02dday", c(7L,30L,90L)),
    unlist(lapply(groups, function(g) g$rows$product), use.names = FALSE))
  sources <- vapply(ids, function(id) file.path(site_dir, "maps/generated", catalog[[id]]$image), character(1))
  available <- setNames(file.exists(sources), ids)
  missing_required <- !available & !startsWith(ids, "snow_")
  if (any(missing_required)) stop("Missing current preview maps: ", paste(sources[missing_required], collapse = ", "))
  for (path in sources[available]) if (!identical(readBin(path, "raw", 8), as.raw(c(137,80,78,71,13,10,26,10)))) stop("Unreadable PNG: ", path)
  for (folder in c("maps", "individual", "assets")) dir.create(file.path(output_dir, folder), recursive = TRUE, showWarnings = FALSE)
  for (i in seq_along(ids)) {
    destination <- file.path(output_dir, "maps", basename(sources[i]))
    if (available[i] && (!file.copy(sources[i], destination, overwrite = TRUE) || !identical(unname(tools::md5sum(sources[i])), unname(tools::md5sum(destination))))) stop("Preview copy failed.")
    p <- catalog[[ids[i]]]
    writeLines(c('---', paste0('title: "', p$label, '"'), 'toc: false', '---', '',
      if (available[i]) paste0('![](../maps/', basename(sources[i]), ')') else "Map unavailable in the laptop cache.",
      '', p$description), file.path(output_dir, "individual", paste0(ids[i], ".qmd")), useBytes = TRUE)
  }
  for (kind in c("values", "departures")) writeLines(temperature_preview_page(kind, catalog),
    file.path(output_dir, if (kind == "values") "index.qmd" else "departures.qmd"), useBytes = TRUE)
  for (kind in c("totals", "ranks")) writeLines(precipitation_preview_page(kind, catalog),
    file.path(output_dir, paste0("precipitation-", kind, ".qmd")), useBytes = TRUE)
  for (key in names(groups)) writeLines(current_group_preview_page(key, groups[[key]], catalog, available),
    file.path(output_dir, paste0(key, ".qmd")), useBytes = TRUE)
  assets <- "scripts/temperature-tabs-preview-assets"
  for (file in c("temperature-tabs.js", "temperature-tabs.css", "precipitation-periods.js", "current-map-groups.js")) {
    if (!file.copy(file.path(assets, file), file.path(output_dir, file), overwrite = TRUE)) stop("Could not copy preview assets.")
  }
  logo <- "assets/branding/southwest-climate-watch-mark-transparent.png"
  dir.create(file.path(output_dir, dirname(logo)), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(site_dir, logo), file.path(output_dir, logo), overwrite = TRUE)
  originals <- lapply(ids, function(id) list(href = paste0("individual/", id, ".qmd"),
    text = paste(catalog[[id]]$group, "—", catalog[[id]]$label)))
  temperature <- list(section = "Temperature", contents = list(
    list(href = "index.qmd", text = "Current values"), list(href = "departures.qmd", text = "Departures")))
  precipitation <- list(section = "Precipitation", contents = list(
    list(href = "precipitation-totals.qmd", text = "Recent totals"),
    list(href = "precipitation-ranks.qmd", text = "Percentile ranks")))
  grouped_links <- function(section) lapply(names(groups)[vapply(groups, function(g) g$section == section, logical(1))],
    function(key) list(href = paste0(key, ".qmd"), text = groups[[key]]$title))
  temperature$contents <- c(temperature$contents, grouped_links("Temperature"))
  precipitation$contents <- c(precipitation$contents, grouped_links("Precipitation"))
  sidebar <- list(style = "docked", background = "light", title = "Southwest Climate Watch", logo = logo,
    `collapse-level` = 1L, contents = list(list(section = "Current Maps", contents = c(list(temperature, precipitation), grouped_links("Snow"))),
      list(section = "Original individual pages", contents = originals)))
  config <- list(project = list(type = "website", `output-dir` = "_site", resources = list("maps/**", "temperature-tabs.js", "precipitation-periods.js", "current-map-groups.js")),
    website = list(title = "Southwest Climate Watch", sidebar = sidebar, search = FALSE),
    format = list(html = list(theme = list(light = "flatly", dark = "darkly"), css = "temperature-tabs.css", toc = FALSE)))
  # R's YAML emitter uses YAML 1.1 booleans; Quarto requires YAML 1.2.
  configuration <- gsub(": no(\n|$)", ": false\\1", yaml::as.yaml(config))
  writeLines(configuration, file.path(output_dir, "_quarto.yml"), useBytes = TRUE)
  manifest <- data.frame(product = ids, image = basename(sources), available = unname(available), md5 = unname(tools::md5sum(sources)))
  write.csv(manifest, file.path(output_dir, "map-manifest.csv"), row.names = FALSE)
  registry <- rbind(data.frame(page = ifelse(grepl("_value$", ids[1:16]), "index.html",
    ifelse(grepl("_departure_", ids[1:16]), "departures.html", ifelse(grepl("^pcpn_total_", ids[1:16]), "precipitation-totals.html", "precipitation-ranks.html"))), product = ids[1:16]),
    do.call(rbind, lapply(names(groups), function(key) data.frame(page = paste0(key, ".html"), product = groups[[key]]$rows$product))))
  write.csv(registry, file.path(output_dir, "page-manifest.csv"), row.names = FALSE)
  message("Current Maps grouping preview prepared: ", output_dir, "; ", sum(available), " maps copied; ", sum(!available), " unavailable. No site source or data changed.")
  invisible(list(directory = output_dir, manifest = manifest))
}

check_temperature_tabs_preview <- function(directory = "data/diagnostics/temperature-tabs-preview") {
  manifest <- read.csv(file.path(directory, "map-manifest.csv"), stringsAsFactors = FALSE)
  registry <- read.csv(file.path(directory, "page-manifest.csv"), stringsAsFactors = FALSE)
  checked <- list()
  for (page in unique(registry$page)) {
    doc <- xml2::read_html(file.path(directory, "_site", page))
    panels <- xml2::xml_find_all(doc, '//*[@data-product]')
    expected <- registry$product[registry$page == page]
    if (!setequal(xml2::xml_attr(panels, "data-product"), expected) || length(panels) != length(expected)) stop("Incomplete preview page: ", page)
    for (panel in panels) {
      id <- xml2::xml_attr(panel, "data-product"); row <- manifest[manifest$product == id, ]
      if (!row$available) {
        if (length(xml2::xml_find_all(panel, './/img')) || !length(xml2::xml_find_all(panel, './/*[contains(@class,"group-unavailable")]'))) stop("Missing unavailable-map notice: ", id)
        checked[[length(checked) + 1L]] <- data.frame(page = page, product = id, status = "UNAVAILABLE_NOTED")
        next
      }
      image <- xml2::xml_find_first(panel, './/img'); src <- xml2::xml_attr(image, "src")
      href <- xml2::xml_attr(xml2::xml_parent(image), "href")
      path <- file.path(directory, "_site", src)
      if (!identical(src, paste0("maps/", row$image)) || !identical(src, href) || !file.exists(path) ||
          !identical(unname(tools::md5sum(path)), row$md5)) stop("Invalid rendered preview map: ", id)
      checked[[length(checked) + 1L]] <- data.frame(page = page, product = id, status = "PASS")
    }
  }
  result <- do.call(rbind, checked)
  write.csv(result, file.path(directory, "validation.csv"), row.names = FALSE)
  message("Current Maps grouping preview: PASS; ", sum(result$status == "PASS"), " maps/links verified; ", sum(result$status == "UNAVAILABLE_NOTED"), " unavailable notices verified.")
  invisible(result)
}
