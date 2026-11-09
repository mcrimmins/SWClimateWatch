# Stage verified monthly maps for local Quarto review. No downloads or S3 sync.
monthly_site_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub('"', "&quot;", x, fixed = TRUE)
  gsub("<", "&lt;", x, fixed = TRUE)
}

monthly_site_products <- function(end, ranking_dir, spi_dir) {
  jobs <- expand.grid(duration = c(1L, 3L, 6L, 12L),
    family = c("temperature", "precipitation", "spi"), stringsAsFactors = FALSE)
  jobs$folder <- vapply(seq_len(nrow(jobs)), function(i) {
    j <- jobs[i, ]
    if (j$family == "spi") file.path(spi_dir, end, sprintf("%02dmonth", j$duration)) else
      file.path(ranking_dir, end, j$family, sprintf("%02dmonth", j$duration))
  }, character(1))
  jobs$source <- file.path(jobs$folder, ifelse(jobs$family == "spi", "spi.png", paste0(jobs$family, "-ranking.png")))
  jobs
}

monthly_site_page <- function(end, jobs, version) {
  labels <- c(temperature = "Temperature rankings", precipitation = "Precipitation rankings", spi = "SPI")
  end_date <- as.Date(paste0(end, "-01"))
  body <- c('---', 'title: "Monthly Climate"', 'page-layout: full', 'toc: false', 'bread-crumbs: false',
    '---', '', '```{=html}', sprintf('<div class="monthly-climate" data-monthly-end="%s">', end),
    sprintf('<p class="monthly-status"><strong>Through %s</strong> · Complete calendar months · PRISM via RCC-ACIS</p>', format(end_date, "%B %Y")),
    '<p>Compare recent temperature and precipitation with the long-term record. Recent PRISM inputs are preliminary and may be revised.</p>',
    '<div class="monthly-controls"><label for="monthly-duration">Time period</label> <select id="monthly-duration"><option value="1">1 month</option><option value="3">3 months</option><option value="6">6 months</option><option value="12">12 months</option></select></div>',
    '<div class="monthly-tabs" role="tablist" aria-label="Monthly climate variable">')
  for (family in names(labels)) body <- c(body, sprintf('<button type="button" id="monthly-tab-%s" role="tab" aria-controls="monthly-panel-%s">%s</button>', family, family, labels[[family]]))
  body <- c(body, '</div>')
  for (family in names(labels)) {
    body <- c(body, sprintf('<section id="monthly-panel-%s" role="tabpanel" aria-labelledby="monthly-tab-%s"><h2 class="monthly-fallback-title">%s</h2>', family, family, labels[[family]]))
    for (duration in c(1L, 3L, 6L, 12L)) {
      j <- jobs[jobs$family == family & jobs$duration == duration, ]
      src <- paste0('../maps/generated/prism/monthly/', version, '/', j$file)
      begin <- seq(end_date, by = "-1 month", length.out = duration)[duration]
      period <- if (duration == 1) format(end_date, "%B %Y") else paste(format(begin, "%B %Y"), "–", format(end_date, "%B %Y"))
      body <- c(body, sprintf('<div class="monthly-map" data-duration="%d"><p class="monthly-period">%s</p><a href="%s" target="_blank" rel="noopener"><img data-monthly-map="%s-%d" src="%s" alt="%d-month %s, %s" loading="lazy"></a><p><a href="%s" target="_blank" rel="noopener">Open full-resolution PNG</a></p></div>',
        duration, period, src, family, duration, src, duration, labels[[family]], period, src))
    }
    body <- c(body, '</section>')
  }
  c(body, '<details class="monthly-methods"><summary>How to read these maps</summary>',
    '<p><strong>Rankings:</strong> Compare matching calendar-month windows in the available PRISM record beginning in 1895. Higher percentiles mean warmer or wetter conditions. Temperature averages are weighted by the number of days in each month; precipitation is summed. Multi-month windows must be complete. At least 30 years and 90% of eligible comparison windows are required.</p>',
    '<p><strong>Records:</strong> Record warm/cold and wet/dry categories identify values matching the historical maximum/minimum, including ties, only with complete comparison support and a varying record. Common zero-precipitation totals are not labeled record dry.</p>',
    '<p><strong>SPI:</strong> Negative values indicate dryness and positive values wetness. Fits use matching windows from the fixed 1895–2020 calibration. Gray indicates that support or fit checks did not permit an estimate. SPI is not a percentile, and its fixed reference differs from the expanding ranking record.</p>',
    '<p>Recent inputs are checked for revisions during the monthly update cycle. A calendar age alone does not confirm that a source file is final. These maps describe completed monthly periods; use Current Maps for daily monitoring.</p>',
    '<p><a href="methods.html">About this site</a> · <a href="https://prism.oregonstate.edu/">PRISM Climate Group</a></p></details></div>',
    '<script src="../assets/monthly-climate.js"></script>', '```')
}

stage_prism_monthly_site <- function(end = prism_monthly_latest_complete(), site_dir = "site",
    ranking_dir = "data/diagnostics/prism-monthly-ranking-pilots",
    spi_dir = "data/diagnostics/prism-monthly-spi-pilots", cache_dir = prism_monthly_cache_dir(),
    audit_dir = "data/diagnostics/prism-monthly-cache-audit", .verify_sources = TRUE) {
  end <- format(prism_monthly_month(end), "%Y-%m")
  jobs <- monthly_site_products(end, ranking_dir, spi_dir)
  # Validate the entire release before touching the currently staged page.
  audit <- if (.verify_sources) audit_prism_monthly_cache(end = end, cache_dir = cache_dir, report_dir = audit_dir) else NULL
  if (!is.null(audit) && audit$summary$status == "FAIL") stop("Monthly source audit failed; staged page retained.")
  for (i in seq_len(nrow(jobs))) {
    j <- jobs[i, ]; marker_path <- file.path(j$folder, "complete.rds")
    marker <- prism_monthly_update_read(marker_path)
    if (is.null(marker) || !prism_monthly_ranking_complete(marker_path, marker$signature) ||
        !j$source %in% marker$files || !file.exists(j$source)) stop("Unverified monthly product: ", j$family, " ", j$duration, ". Staged page retained.")
    if (!is.null(audit)) {
      variables <- if (j$family == "temperature") c("maxt", "mint") else "pcpn"
      deps <- if (j$family == "spi") prism_monthly_spi_dependencies("1895-01", end, j$duration) else prism_monthly_ranking_dependencies("1895-01", end, j$duration)
      signature <- prism_monthly_input_signature(audit, variables, deps)
      expected <- if (j$family == "spi") digest::digest(list(policy = prism_monthly_spi_policy(), source = signature,
        end = end, duration = as.integer(j$duration), maps = TRUE, display = prism_monthly_spi_display_policy()), algo = "sha256") else
        digest::digest(list(policy = "monthly-ranking-pilots-v3.1-record-both-zero02", source = signature,
          variable = j$family, duration = as.integer(j$duration), start = "1895-01", end = end,
          min_years = 30L, min_fraction = 0.9, make_maps = TRUE), algo = "sha256")
      if (!identical(expected, marker$signature)) stop("Monthly inputs/policy changed; rebuild ", j$family, " ", j$duration, " before staging.")
    }
    png_header <- readBin(j$source, "raw", n = 8)
    if (!identical(png_header, as.raw(c(137,80,78,71,13,10,26,10)))) stop("Invalid monthly PNG: ", j$source)
  }
  jobs$md5 <- unname(tools::md5sum(jobs$source))
  jobs$file <- sprintf("%s-%02dmonth.png", jobs$family, jobs$duration)
  version <- paste0(end, "-", substr(digest::digest(jobs[, c("family", "duration", "md5")], algo = "sha256"), 1, 16))
  folder <- file.path(site_dir, "maps/generated/prism/monthly", version)
  dir.create(folder, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(nrow(jobs))) {
    destination <- file.path(folder, jobs$file[i])
    if (!file.exists(destination) || unname(tools::md5sum(destination)) != jobs$md5[i]) prism_monthly_install_file(jobs$source[i], destination)
    if (!identical(unname(tools::md5sum(destination)), jobs$md5[i])) stop("Copied monthly map failed verification; staged page retained.")
  }
  manifest <- list(schema = 1L, end_month = end, version = version,
    staged_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), products = jobs[, c("family", "duration", "file", "md5")])
  temporary <- tempfile(tmpdir = folder)
  on.exit(unlink(temporary), add = TRUE)
  jsonlite::write_json(manifest, temporary, auto_unbox = TRUE, pretty = TRUE)
  replace_file_atomically(temporary, file.path(folder, "manifest.json"))
  page <- file.path(site_dir, "pages/monthly-climate.qmd")
  dir.create(dirname(page), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(tmpdir = dirname(page)); on.exit(unlink(temporary), add = TRUE)
  writeLines(monthly_site_page(end, jobs, version), temporary, useBytes = TRUE)
  replace_file_atomically(temporary, page)
  message("Monthly Climate staged: ", end, "; 12 verified maps. No website render or S3 sync.")
  invisible(list(end_month = end, page = page, version = version, products = jobs))
}

validate_prism_monthly_publication <- function(site_dir = "site", rendered_dir = NULL,
    report_dir = "data/diagnostics/prism-monthly-publication") {
  root <- if (is.null(rendered_dir)) site_dir else rendered_dir
  page <- file.path(root, "pages", if (is.null(rendered_dir)) "monthly-climate.qmd" else "monthly-climate.html")
  checks <- data.frame(check = character(), passed = logical(), note = character())
  add <- function(name, passed, note = "") checks <<- rbind(checks, data.frame(check = name, passed = isTRUE(passed), note = note))
  tryCatch({
    document <- xml2::read_html(page)
    container <- xml2::xml_find_first(document, '//*[@data-monthly-end]')
    end <- xml2::xml_attr(container, "data-monthly-end")
    images <- xml2::xml_find_all(document, '//img[@data-monthly-map]')
    ids <- xml2::xml_attr(images, "data-monthly-map")
    expected <- as.vector(outer(c("temperature", "precipitation", "spi"), c(1,3,6,12), paste, sep = "-"))
    add("twelve_unique_maps", length(ids) == 12L && setequal(ids, expected))
    add("ending_month", length(end) == 1 && !is.na(end) && grepl("^[0-9]{4}-[0-9]{2}$", end))
    versions <- character()
    for (i in seq_along(images)) {
      src <- xml2::xml_attr(images[[i]], "src")
      safe <- !is.na(src) && grepl("^\\.\\./maps/generated/prism/monthly/[0-9]{4}-[0-9]{2}-[a-f0-9]{16}/[a-z]+-[0-9]{2}month\\.png$", src)
      if (!safe) { add(paste0("path_", ids[i]), FALSE, "Unexpected asset path"); next }
      version <- basename(dirname(src)); versions <- c(versions, version)
      manifest <- jsonlite::read_json(file.path(root, "maps/generated/prism/monthly", version, "manifest.json"), simplifyVector = TRUE)
      row <- manifest$products[paste(manifest$products$family, manifest$products$duration, sep = "-") == ids[i], ]
      path <- file.path(dirname(page), src)
      add(paste0("map_", ids[i]), nrow(row) == 1 && manifest$end_month == end &&
        file.exists(path) && identical(unname(tools::md5sum(path)), row$md5))
      href <- xml2::xml_attr(xml2::xml_parent(images[[i]]), "href")
      add(paste0("link_", ids[i]), identical(href, src))
    }
    add("single_release", length(unique(versions)) == 1L)
    script <- xml2::xml_find_first(document, '//script[contains(@src,"monthly-climate.js")]')
    add("selector_script", !inherits(script, "xml_missing") && file.exists(file.path(root, "assets/monthly-climate.js")))
    add("selector_checksum", file.exists(file.path(root,"assets/monthly-climate.js")) &&
      identical(unname(tools::md5sum(file.path(root,"assets/monthly-climate.js"))),
        unname(tools::md5sum(file.path(site_dir,"assets/monthly-climate.js")))))
  }, error = function(e) add("page_read", FALSE, conditionMessage(e)))
  summary <- data.frame(status = if (nrow(checks) && all(checks$passed)) "PASS" else "FAIL",
    maps = sum(grepl("^map_", checks$check)), failed = sum(!checks$passed), rendered = !is.null(rendered_dir))
  dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
  write_prism_monthly_audit_report(checks, file.path(report_dir, "checks.csv"))
  write_prism_monthly_audit_report(summary, file.path(report_dir, "summary.csv"))
  list(summary = summary, checks = checks)
}
