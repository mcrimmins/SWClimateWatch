# Local page integration only. Publication/daily-runner hooks are a later release step.
regional_climate_site_jobs <- function(annual_dir, seasonal_dir, share_dir = NULL, daily_dir = NULL) {
  jobs <- expand.grid(variable = c("precipitation", "temperature"),
    period = c("annual", "winter", "spring", "summer", "fall"), stringsAsFactors = FALSE)
  jobs$id <- paste(jobs$period, jobs$variable, sep = "-")
  jobs$file <- paste0(jobs$period, ifelse(jobs$variable == "temperature", "-mean-temperature.png", "-precipitation.png"))
  jobs$source <- vapply(seq_len(nrow(jobs)), function(i) {
    row <- jobs[i, ]
    if (row$period == "annual") file.path(annual_dir, if (row$variable == "temperature")
      "annual-mean-temperature.png" else "annual-precipitation.png") else
        file.path(seasonal_dir, row$period, paste0(row$variable, ".png"))
  }, character(1))
  if (!is.null(share_dir)) {
    periods <- names(regional_reference_seasons())
    extra <- data.frame(variable = "precipitation_share", period = periods,
      id = paste0(periods, "-precipitation-share"), file = paste0(periods, "-precipitation-share.png"),
      source = file.path(share_dir, paste0(periods, "-precipitation-share.png")))
    jobs <- rbind(jobs, extra)
  }
  if (!is.null(daily_dir)) {
    extra <- expand.grid(variable = c('wet_days','wet_amount','heavy_days','freeze_days','hot_days'),
      period = c('annual','winter','spring','summer','fall'), stringsAsFactors = FALSE)
    extra$id <- paste(extra$period, gsub('_','-',extra$variable), sep='-')
    extra$file <- paste0(extra$id,'.png')
    extra$source <- file.path(daily_dir,extra$period,paste0(extra$variable,'.png'))
    jobs <- rbind(jobs,extra)
  }
  jobs
}

regional_climate_daily_verify <- function(daily_dir) {
  marker <- file.path(daily_dir,'complete.rds')
  saved <- if(file.exists(marker)) readRDS(marker) else NULL
  if (!is.list(saved) || !length(saved$files) || !all(file.exists(saved$files)) ||
      !identical(unname(tools::md5sum(saved$files)),saved$md5)) stop('Missing or changed daily reference outputs; run scripts/build-regional-daily-reference-pilot.R.')
  plan <- read.csv(file.path(daily_dir,'input-plan.csv'),stringsAsFactors=FALSE)
  methods <- read.csv(file.path(daily_dir,'methods.csv'),stringsAsFactors=FALSE)
  months <- format(seq(as.Date('1991-01-01'),as.Date('2020-12-01'),by='month'),'%Y-%m')
  expected <- expand.grid(variable=c('pcpn','mint','maxt'),month=months,stringsAsFactors=FALSE)
  if(nrow(plan)!=1080L || !all(plan$complete) || anyDuplicated(paste(plan$month,plan$variable)) ||
      !setequal(paste(plan$month,plan$variable),paste(expected$month,expected$variable)) ||
      !all(file.exists(plan$path)) || !identical(unname(tools::md5sum(plan$path)),plan$md5) ||
      nrow(methods)!=5L || any(methods$reference!='1991-2020') || any(methods$seasons!='JFM/AMJ/JAS/OND calendar quarters'))
    stop('Daily reference inputs or period definitions changed; rebuild daily references.')
  invisible(TRUE)
}

regional_climate_site_verify <- function(annual_dir, seasonal_dir) {
  roots <- c(annual_dir, file.path(seasonal_dir, c("winter", "spring", "summer", "fall")))
  for (root in roots) {
    path <- file.path(root, "complete.rds")
    marker <- if (file.exists(path)) tryCatch(readRDS(path), error = function(e) NULL) else NULL
    if (!is.list(marker) || !length(marker$files) || !all(file.exists(marker$files)) ||
        !identical(unname(tools::md5sum(marker$files)), marker$md5))
      stop("Missing or changed reference outputs; rebuild the pilot: ", root)
  }
  annual_methods <- read.csv(file.path(annual_dir, "methods.csv"), stringsAsFactors = FALSE)
  seasonal_methods <- read.csv(file.path(seasonal_dir, "methods.csv"), stringsAsFactors = FALSE)
  if (nrow(annual_methods) != 1L || nrow(seasonal_methods) != 1L ||
      !isTRUE(annual_methods$start_year == 1991L && annual_methods$end_year == 2020L &&
        annual_methods$required_complete_years == 30L && seasonal_methods$start_year == 1991L &&
        seasonal_methods$end_year == 2020L && seasonal_methods$complete_seasons_required == 30L &&
        seasonal_methods$calendar == "JFM/AMJ/JAS/OND calendar quarters"))
    stop("Reference periods/support do not match the proposed page.")
  annual_inventory <- read.csv(file.path(annual_dir, "source-inventory.csv"), stringsAsFactors = FALSE)
  seasonal_inventory <- read.csv(file.path(seasonal_dir, "source-inventory.csv"), stringsAsFactors = FALSE)
  keys <- c("month", "variable", "request_signature", "md5")
  months <- format(seq(as.Date("1991-01-01"), as.Date("2020-12-01"), by = "month"), "%Y-%m")
  expected <- expand.grid(variable = c("maxt", "mint", "pcpn"), month = months, stringsAsFactors = FALSE)
  if (nrow(annual_inventory) != 1080L || !all(keys %in% names(annual_inventory)) ||
      !all(keys %in% names(seasonal_inventory)) ||
      anyDuplicated(paste(annual_inventory$variable, annual_inventory$month)) ||
      !setequal(paste(annual_inventory$variable, annual_inventory$month), paste(expected$variable, expected$month)) ||
      !identical(annual_inventory[keys], seasonal_inventory[keys]) ||
      !all(file.exists(annual_inventory$path)) ||
      !identical(unname(tools::md5sum(annual_inventory$path)), annual_inventory$md5))
    stop("Annual/seasonal source inventories differ or inputs changed; rebuild the pilot.")
  for (period in c("winter", "spring", "summer", "fall")) {
    methods <- read.csv(file.path(seasonal_dir, period, "methods.csv"), stringsAsFactors = FALSE)
    spec <- regional_reference_seasons()[[period]]
    if (nrow(methods) != 1L || !isTRUE(methods$period == period && methods$months == spec$text &&
        methods$start_year == 1991L && methods$end_year == 2020L && methods$complete_seasons_required == 30L))
      stop("Seasonal reference definition disagrees with page labels: ", period)
  }
  invisible(TRUE)
}

# Page layout and labels for the locally reviewed reference map suite.
regional_climate_metrics <- function() list(
  precipitation = list(group='precipitation', label='Precipitation total', note='Average precipitation total, in inches.'),
  precipitation_share = list(group='precipitation', label='Share of annual precipitation', note='Seasonal mean divided by the annual mean, times 100.'),
  wet_days = list(group='precipitation', label='Wet days', note='Average days with at least 0.04 inch of precipitation.'),
  wet_amount = list(group='precipitation', label='Amount per wet day', note='Average precipitation on wet days (at least 0.04 inch), pooled over the reference years.'),
  heavy_days = list(group='precipitation', label='Heavy-precipitation days', note='Average days with at least 1 inch of precipitation; this is an absolute threshold, not a local rarity ranking.'),
  temperature = list(group='temperature', label='Mean temperature', note='Average temperature in degrees F; monthly means weighted by actual days within each reference year.'),
  freeze_days = list(group='temperature', label='Freeze nights', note='Average nights with minimum temperature at or below 32 F.'),
  hot_days = list(group='temperature', label='Hot days', note='Average days with maximum temperature at or above 90 F; this is not a heat-risk index.'))

regional_climate_period_labels <- function() c(annual='Annual (Jan-Dec)', winter='Winter (Jan-Mar)',
  spring='Spring (Apr-Jun)', summer='Summer (Jul-Sep)', fall='Fall (Oct-Dec)')

regional_climate_page_text <- function(jobs) {
  metrics <- regional_climate_metrics(); periods <- regional_climate_period_labels()
  available <- names(metrics)[names(metrics) %in% jobs$variable]
  option <- function(values, labels) paste0('<option value="',values,'">',labels,'</option>',collapse='')
  lines <- c('---','title: "Climate of the Region"','page-layout: full','toc: false','bread-crumbs: false',
    'body-classes: climate-region-page','---','',
    'Typical precipitation and temperature patterns across Arizona, New Mexico and surrounding areas.','',
    '**1991-2020 reference** · PRISM monthly and daily grids via RCC-ACIS','',
    'Explore a period by topic, or compare the same metric across all four seasons. These maps describe the reference climate; use Current Maps for recent conditions.','',
    '```{=html}','<div class="climate-controls" id="climate-shared-controls">',
    paste0('<label>Period <select id="climate-period">',option(names(periods),periods),'</select></label>'),
    '<span id="climate-period-hint" role="status" aria-live="polite"></span></div>','```','',
    '::: {.panel-tabset .climate-reference-tabs}','')
  for (group in c('precipitation','temperature','comparison')) {
    title <- switch(group,precipitation='Precipitation',temperature='Temperature',comparison='Seasonal comparison')
    fields <- if (group=='comparison') available else available[vapply(metrics[available],function(m) m$group==group,logical(1))]
    fields <- setdiff(fields,if(group=='precipitation') 'precipitation_share' else character())
    lines <- c(lines,paste0('## ',title),'','```{=html}',paste0('<div data-climate-group="',group,'">'),
      '<div class="climate-controls">',paste0('<label>Metric <select id="climate-',group,'-metric">',
      option(fields,vapply(metrics[fields],`[[`,character(1),'label')),'</select></label>'))
    if (group!='comparison') lines <- c(lines,paste0('<label>View <select id="climate-',group,'-view"><option value="single">Selected map</option><option value="all">All metrics</option></select></label>'))
    if(group=='precipitation' && 'precipitation_share' %in% available) lines <- c(lines,
      '<label id="climate-share-control">Precipitation total <select id="climate-precip-mode" aria-describedby="climate-share-hint" disabled><option value="total">Total</option><option value="share">Share of annual</option></select></label>',
      '<span id="climate-share-hint">Share of annual is available for seasons.</span>')
    lines <- c(lines,'</div>',paste0('<p class="climate-view-status" id="climate-',group,'-status" role="status" aria-live="polite"></p>'))
    if (group=='comparison') lines <- c(lines,'<div class="climate-map-grid climate-comparison-grid" id="climate-comparison-maps"></div>') else {
      lines <- c(lines,paste0('<div class="climate-map-grid" id="climate-',group,'-maps">'))
      rows <- jobs[vapply(jobs$variable,function(v) metrics[[v]]$group==group,logical(1)), ]
      for(i in seq_len(nrow(rows))) {
        row <- rows[i, ]; spec <- metrics[[row$variable]]; path <- paste0('../maps/generated/prism/regional-reference/1991-2020/',row$file)
        hidden <- !(row$period=='annual' && row$variable==if(group=='precipitation') 'precipitation' else 'temperature')
        lines <- c(lines,sprintf('<article class="dashboard-map-card climate-map-card" data-reference-card="%s" data-period="%s" data-metric="%s"%s>',group,row$period,row$variable,if(hidden) ' hidden' else ''),
          sprintf('<a href="%s" target="_blank" rel="noopener"><img data-reference-map="%s" src="%s" alt="%s: %s, 1991-2020" loading="lazy"></a>',path,row$id,path,periods[[row$period]],spec$label),
          paste0('<p class="archive-map-description">',spec$note,'</p>'),
          sprintf('<div class="dashboard-card-actions"><a class="btn btn-sm btn-outline-primary" href="%s" target="_blank" rel="noopener">Open full-resolution PNG</a></div>',path),'</article>')
      }
      lines <- c(lines,'</div>')
    }
    lines <- c(lines,'</div>','```','')
  }
  c(lines,':::','','```{=html}','<details class="climate-reference-methods"><summary>How to read these maps</summary>',
    '<p><strong>Reference:</strong> Project-calculated PRISM grid averages for 1991-2020, not current anomalies, full-record rankings or official NOAA station normals. Grid cells are spatial estimates.</p>',
    '<p><strong>Periods:</strong> Annual is January-December; seasons are calendar quarters: winter January-March, spring April-June, summer July-September and fall October-December. Seasonal comparisons share the same scale within each metric. Annual precipitation totals and mean temperatures have separate scales.</p>',
    '<p><strong>Totals and temperature:</strong> Sum monthly precipitation within each year or quarter, then average the 30 complete totals. Monthly mean temperature is (mean daily maximum + mean daily minimum)/2, weighted by actual days including leap days within each year or quarter, then averaged equally across the 30 years.</p>',
    '<p><strong>Share of annual:</strong> 100 times seasonal mean precipitation divided by annual mean precipitation, not the average of yearly percentages. All four seasonal references and the annual reference require matched complete support. Zero annual totals are withheld. Supported shares sum to 100% within storage precision. Annual always displays totals; the seasonal choice is remembered.</p>',
    '<p><strong>Daily references:</strong> Wet days have precipitation &gt;=0.04 inch; heavy-precipitation days &gt;=1 inch; freeze nights have minimum temperature &lt;=32 F; hot days have maximum temperature &gt;=90 F. Counts average 30 complete periods. Amount per wet day pools precipitation on wet days and divides by the pooled wet-day count; it is unavailable if no wet days occur. These fixed thresholds do not measure local rarity or impacts.</p>',
    '<p><strong>Coverage:</strong> All 30 complete years or seasons are required separately by variable and period. Missing observations are not filled or interpolated. Zero counts are valid; beige means unavailable support. Numerical values are not capped by the open-ended display categories.</p>',
    '<p><a href="precipitation-ranks.html">Recent precipitation rankings</a> · <a href="temperature-rolling-ranks.html">Recent temperature rankings</a> · <a href="methods.html">About the data and methods</a></p>',
    '</details><script src="../assets/climate-reference.js"></script>','```')
}


regional_climate_navigation <- function(config_path) {
  lines <- readLines(config_path, warn = FALSE, encoding = "UTF-8")
  target <- "- href: pages/climate-of-region.qmd"
  count <- sum(trimws(lines) == target)
  if (count > 1L) stop("Duplicate Climate of the Region navigation entry.")
  if (count == 0L) {
    anchor <- which(trimws(lines) == "- href: pages/methods.qmd")
    if (length(anchor) != 1L) stop("Expected one About navigation anchor.")
    lines <- append(lines, c("      - href: pages/climate-of-region.qmd", "        text: Climate of the Region"), after = anchor - 1L)
  }
  resource <- "- maps/generated/prism/regional-reference/**"
  if (!any(trimws(lines) == resource)) {
    anchor <- which(trimws(lines) == "- maps/generated/prism/monthly/**")
    if (length(anchor) != 1L) stop("Expected the monthly resource anchor.")
    lines <- append(lines, "    - maps/generated/prism/regional-reference/**", after = anchor)
  }
  writeLines(lines, config_path, useBytes = TRUE)
  invisible(config_path)
}

stage_regional_climate_reference_site <- function(site_dir = "site",
    annual_dir = "data/diagnostics/regional-climate-reference-pilot",
    seasonal_dir = "data/diagnostics/regional-seasonal-reference-pilot",
    share_dir = "data/diagnostics/regional-precipitation-share-pilot",
    daily_dir = "data/diagnostics/regional-daily-reference-pilot") {
  regional_climate_site_verify(annual_dir, seasonal_dir)
  if (!is.null(share_dir)) verify_regional_precipitation_share_pilot(share_dir, annual_dir, seasonal_dir)
  if (!is.null(daily_dir)) regional_climate_daily_verify(daily_dir)
  jobs <- regional_climate_site_jobs(annual_dir, seasonal_dir, share_dir, daily_dir)
  for (path in jobs$source) if (!identical(readBin(path, "raw", n = 8), as.raw(c(137, 80, 78, 71, 13, 10, 26, 10))))
    stop("Invalid reference PNG: ", path)
  destination <- file.path(site_dir, "maps/generated/prism/regional-reference/1991-2020")
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(nrow(jobs))) {
    to <- file.path(destination, jobs$file[i]); from <- jobs$source[i]
    if (!file.exists(to) || !identical(unname(tools::md5sum(to)), unname(tools::md5sum(from))))
      if (!file.copy(from, to, overwrite = TRUE)) stop("Could not copy reference map.")
    if (!identical(unname(tools::md5sum(to)), unname(tools::md5sum(from)))) stop("Reference map copy checksum mismatch.")
  }
  jobs$md5 <- unname(tools::md5sum(jobs$source))
  jsonlite::write_json(list(schema_version = 1L, start_year = 1991L, end_year = 2020L,
    precipitation_share_enabled = !is.null(share_dir),
    daily_reference_enabled = !is.null(daily_dir), layout_version = 2L,
    required_complete_periods = 30L, season_definitions = lapply(regional_reference_seasons(), `[[`, "text"),
    products = jobs[c("id", "period", "variable", "file", "md5")]), file.path(destination, "manifest.json"),
    auto_unbox = TRUE, dataframe = "rows", pretty = TRUE)
  page <- file.path(site_dir, "pages/climate-of-region.qmd")
  writeLines(regional_climate_page_text(jobs), page, useBytes = TRUE)
  {
    asset <- file.path(site_dir, "assets/climate-reference.js")
    if (!file.copy("scripts/climate-reference-assets/climate-reference.js", asset, overwrite = TRUE)) stop("Could not stage precipitation selector script.")
  }
  regional_climate_navigation(file.path(site_dir, "_quarto.yml"))
  message("Climate of the Region staged locally: ", nrow(jobs), " maps; navigation above About. No publication.")
  invisible(jobs)
}

validate_regional_climate_reference_site <- function(site_dir = "site", rendered = TRUE,
    report_dir = "data/diagnostics/regional-climate-site-check") {
  root <- "maps/generated/prism/regional-reference/1991-2020"
  manifest <- jsonlite::read_json(file.path(site_dir, root, "manifest.json"), simplifyVector = TRUE)
  jobs <- manifest$products
  expected <- as.vector(outer(c("annual", "winter", "spring", "summer", "fall"), c("precipitation", "temperature"), paste, sep = "-"))
  share_enabled <- isTRUE(manifest$precipitation_share_enabled)
  if (share_enabled) expected <- c(expected, paste0(c("winter", "spring", "summer", "fall"), "-precipitation-share"))
  if (isTRUE(manifest$daily_reference_enabled)) expected <- c(expected,as.vector(outer(
    c('annual','winter','spring','summer','fall'),c('wet-days','wet-amount','heavy-days','freeze-days','hot-days'),paste,sep='-')))
  if (!identical(manifest$schema_version, 1L) || !isTRUE(manifest$start_year == 1991L && manifest$end_year == 2020L &&
      manifest$required_complete_periods == 30L) || !is.data.frame(jobs) || nrow(jobs) != length(expected) ||
      !all(c("id", "period", "variable", "file", "md5") %in% names(jobs)) || anyNA(jobs) ||
      !setequal(jobs$id, expected) || anyDuplicated(jobs$id) || anyDuplicated(jobs$file) || any(!grepl("^[a-z-]+[.]png$", jobs$file)))
    stop("Invalid reference page manifest.")
  declared <- regional_climate_site_jobs('annual','seasonal',if(share_enabled) 'share' else NULL,
    if(isTRUE(manifest$daily_reference_enabled)) 'daily' else NULL)
  match_rows <- match(jobs$id,declared$id)
  if(anyNA(match_rows) || any(as.matrix(jobs[c('period','variable','file')]) !=
    as.matrix(declared[match_rows,c('period','variable','file')]))) stop('Reference product metadata does not match its ID.')
  source <- paste(readLines(file.path(site_dir, "pages/climate-of-region.qmd"), warn = FALSE), collapse = "\n")
  nav <- readLines(file.path(site_dir, "_quarto.yml"), warn = FALSE)
  if (sum(trimws(nav) == "- href: pages/climate-of-region.qmd") != 1L) stop("Reference navigation is missing or duplicated.")
  doc <- if (rendered) xml2::read_html(file.path(site_dir, "_site/pages/climate-of-region.html")) else NULL
  if (rendered && length(xml2::xml_find_all(doc, '//div[contains(@class,"panel-tabset")]//*[@role="tab"]')) != 3L)
    stop("Expected three rendered reference topic tabs.")
  if (rendered) {
    panels <- xml2::xml_find_all(doc, '//*[@role="tabpanel"]')
    if (length(panels) != 3L || !setequal(xml2::xml_attr(xml2::xml_find_all(doc,'//*[@data-climate-group]'),'data-climate-group'),
      c('precipitation','temperature','comparison'))) stop('Expected three topic panels.')
    if(length(xml2::xml_find_all(doc,'//*[@id="climate-comparison-maps"]'))!=1L ||
      length(xml2::xml_find_all(doc,'//*[@id="climate-period"]/option'))!=5L) stop('Period/comparison controls missing.')
    if (length(xml2::xml_find_all(doc, '//details[contains(@class,"climate-reference-methods")]/ancestor::*[@role="tabpanel"]')))
      stop("Reference notes should be outside the period tabs.")
  }
  checks <- lapply(seq_len(nrow(jobs)), function(i) {
    row <- jobs[i, ]; issues <- character(); relative <- paste0("../", root, "/", row$file)
    from <- file.path(site_dir, root, row$file)
    if (!file.exists(from) || !identical(unname(tools::md5sum(from)), row$md5)) issues <- c(issues, "staged map checksum")
    if (!grepl(paste0('data-reference-map="', row$id, '"'), source, fixed = TRUE) ||
        !grepl(paste0('href="', relative, '"'), source, fixed = TRUE)) issues <- c(issues, "source map/link")
    if (rendered) {
      to <- file.path(site_dir, "_site", root, row$file)
      if (!file.exists(to) || !identical(unname(tools::md5sum(to)), row$md5)) issues <- c(issues, "rendered map checksum")
      images <- xml2::xml_find_all(doc, sprintf('//img[@data-reference-map="%s"]', row$id))
      links <- xml2::xml_find_all(doc, '//a[@href]')
      if (length(images) != 1L || !identical(xml2::xml_attr(images, "src"), relative) ||
          !any(xml2::xml_attr(links, "href") == relative & grepl("Open full-resolution PNG", xml2::xml_text(links), fixed = TRUE)))
        issues <- c(issues, "rendered map/link")
      card <- xml2::xml_find_first(images,'ancestor::article[@data-reference-card]')
      if (!identical(xml2::xml_attr(card,'data-period'),row$period) ||
          !identical(xml2::xml_attr(card,'data-metric'),row$variable)) issues <- c(issues,'rendered selector metadata')
    }
    data.frame(id = row$id, status = if (length(issues)) "FAIL" else "PASS", note = paste(issues, collapse = "; "))
  })
  checks <- do.call(rbind, checks)
  if (rendered) {
    to <- file.path(site_dir, "_site", root, "manifest.json")
    if (!file.exists(to) || !identical(unname(tools::md5sum(to)), unname(tools::md5sum(file.path(site_dir, root, "manifest.json")))))
      stop("Rendered reference manifest differs from the staged manifest.")
    if (!length(xml2::xml_find_all(doc, '//a[contains(@href,"climate-of-region.html")]')))
      stop("Rendered navigation is missing the Climate of the Region link.")
    if (length(xml2::xml_find_all(doc, '//details[contains(@class,"climate-reference-methods")][@open]')))
      stop("Reference methods should be collapsed by default.")
    {
      from <- file.path(site_dir, "assets/climate-reference.js"); to <- file.path(site_dir, "_site/assets/climate-reference.js")
      if (!file.exists(to) || !identical(unname(tools::md5sum(from)), unname(tools::md5sum(to)))) stop("Rendered precipitation selector script is missing or stale.")
      if ((share_enabled && length(xml2::xml_find_all(doc, '//*[@id="climate-precip-mode"]')) != 1L) ||
          !length(xml2::xml_find_all(doc, '//script[@src="../assets/climate-reference.js"]'))) stop("Rendered precipitation selector is missing or unlinked.")
    }
  }
  dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
  write.csv(checks, file.path(report_dir, "checks.csv"), row.names = FALSE)
  summary <- data.frame(status = if (all(checks$status == "PASS")) "PASS" else "FAIL",
    maps = nrow(jobs), tabs = 3L, failed = sum(checks$status != "PASS"), rendered = rendered)
  write.csv(summary, file.path(report_dir, "summary.csv"), row.names = FALSE)
  if (summary$status != "PASS") stop("Reference page checks failed; inspect ", report_dir, "/checks.csv")
  summary
}
