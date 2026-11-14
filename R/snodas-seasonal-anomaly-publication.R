# Cached historical anomaly staging and fail-closed publication validation.
snodas_anomaly_archive_dir <- function() "data/diagnostics/snodas-seasonal-anomaly-archive"

snodas_anomaly_publication_years <- function(config_path = "config/snodas-seasonal-anomalies.yml") {
  if (!file.exists(config_path)) return(integer())
  config <- yaml::read_yaml(config_path)
  if (!isTRUE(config$enabled)) return(integer())
  years <- validate_snodas_seasonal_archive_years(unlist(config$years))
  if (!identical(as.integer(years), 2005:2025)) stop("Publish the complete eligible WY2005-WY2025 snow anomaly archive.")
  years
}

stage_snodas_seasonal_anomaly_archive <- function(site_dir = "site",
    anomaly_dir = snodas_anomaly_archive_dir(), archive_root = "data/diagnostics/snodas-seasonal-archive",
    years = snodas_anomaly_publication_years(), dry_run = TRUE) {
  if (!is.logical(dry_run) || length(dry_run) != 1L || is.na(dry_run)) stop("dry_run must be TRUE or FALSE.")
  if (!length(years)) return(invisible(NULL))
  years <- validate_snodas_seasonal_archive_years(years)
  marker <- verify_snodas_anomaly_preview_inputs(anomaly_dir, archive_root)
  methods <- read.csv(file.path(anomaly_dir, "methods.csv"), stringsAsFactors = FALSE)
  if (!isTRUE(methods$publication_ready)) stop("Build publication-ready snow anomaly maps first.")
  files <- unlist(lapply(years, function(year)
    sprintf("wy%d-peak-swe-%s.png", year, c("departure", "percent-median"))))
  if (!all(files %in% marker$file)) stop("Incomplete anomaly archive: build all configured years first.")
  maps_root <- file.path(site_dir, "maps/generated/snodas/seasonal-archive")
  pages <- file.path(site_dir, "pages/archive")
  plan <- plan_snodas_historic_site(years, maps_root, pages, archive_root = archive_root)
  plan$anomaly_maps_to_copy <- vapply(years, function(year) {
    source <- file.path(anomaly_dir, sprintf("wy%d-peak-swe-%s.png", year, c("departure", "percent-median")))
    target <- file.path(maps_root, paste0("wy", year), c("peak_swe_departure.png", "peak_swe_percent_median.png"))
    sum(is.na(tools::md5sum(target)) | unname(tools::md5sum(target)) != unname(tools::md5sum(source)))
  }, integer(1))
  if (dry_run) {
    message("Historical snow anomaly staging plan only; no site files changed.")
    return(plan)
  }
  stage_snodas_historic_site(years, dry_run = FALSE, site_maps_root = maps_root,
    page_dir = pages, archive_root = archive_root)
  rows <- list()
  for (year in years) {
    for (kind in c("departure", "percent-median")) {
      file <- if (kind == "departure") "peak_swe_departure.png" else "peak_swe_percent_median.png"
      from <- file.path(anomaly_dir, sprintf("wy%d-peak-swe-%s.png", year, kind))
      to <- file.path(maps_root, paste0("wy", year), file)
      if (!file.exists(to) || !identical(unname(tools::md5sum(from)), unname(tools::md5sum(to)))) {
        if (!file.copy(from, to, overwrite = TRUE)) stop("Could not copy historical anomaly map: ", to)
      }
      if (!identical(unname(tools::md5sum(from)), unname(tools::md5sum(to)))) stop("Historical anomaly copy checksum mismatch.")
    }
    write_snodas_historic_page_section(year, pages, include_anomalies = TRUE)
    for (file in c("peak_swe.png", "snow_days.png", "peak_swe_departure.png", "peak_swe_percent_median.png")) {
      path <- paste0("maps/generated/snodas/seasonal-archive/wy", year, "/", file)
      rows[[length(rows) + 1L]] <- data.frame(water_year = year, file = path,
        md5 = unname(tools::md5sum(file.path(site_dir, path))))
    }
  }
  assets <- file.path(site_dir, "assets"); dir.create(assets, recursive = TRUE, showWarnings = FALSE)
  inventory <- read.csv(file.path(anomaly_dir, "source-inventory.csv"), stringsAsFactors = FALSE)
  jsonlite::write_json(list(schema_version = 1L, years = as.integer(years), methods = as.list(methods[1, , drop = FALSE]),
    sources = inventory[c("water_year", "source_signature", "peak_md5", "coverage_md5", "quality_md5", "quality_status")],
    maps = do.call(rbind, rows)), file.path(assets, "snodas-seasonal-anomalies.json"),
    auto_unbox = TRUE, dataframe = "rows", pretty = TRUE)
  message("Staged ", length(years), " historical snow years; ", 2L * length(years), " anomaly companions.")
  plan
}

validate_snodas_seasonal_anomaly_publication <- function(site_dir = "site", require_rendered = TRUE,
    years = snodas_anomaly_publication_years(),
    report_dir = "data/diagnostics/snodas-seasonal-anomaly-publication", fail = TRUE) {
  if (!length(years)) return(invisible(data.frame(status = "DISABLED", years = 0L, maps = 0L, failed = 0L)))
  path <- file.path(site_dir, "assets/snodas-seasonal-anomalies.json")
  manifest <- if (file.exists(path)) tryCatch(jsonlite::read_json(path, simplifyVector = TRUE), error = function(e) NULL) else NULL
  if (is.null(manifest) || !identical(manifest$schema_version, 1L) ||
      !identical(as.integer(manifest$years), as.integer(years)) ||
      !is.list(manifest$methods) || !isTRUE(manifest$methods$publication_ready) || !is.data.frame(manifest$maps))
    stop("Missing or invalid historical snow publication manifest; stage the verified archive first.")
  methods <- manifest$methods
  fields <- c("baseline_start_wy", "baseline_end_wy", "min_years", "minimum_coverage",
    "minimum_median_inches", "target_in_reference", "departure_low_snow_rule")
  if (!all(fields %in% names(methods)) ||
      !isTRUE(methods$baseline_start_wy == 2005L && methods$baseline_end_wy == 2025L &&
        methods$min_years == 18L && methods$minimum_coverage == .95 &&
        methods$minimum_median_inches == 1 && methods$target_in_reference))
    stop("Historical snow methods disagree with published reference/support labels.")
  rows <- manifest$maps
  expected <- unlist(lapply(years, function(year) paste0("maps/generated/snodas/seasonal-archive/wy", year, "/",
    c("peak_swe.png", "snow_days.png", "peak_swe_departure.png", "peak_swe_percent_median.png"))))
  if (!all(c("water_year", "file", "md5") %in% names(rows)) || anyNA(rows) ||
      anyDuplicated(rows$file) || !setequal(rows$file, expected)) stop("Historical snow map manifest is incomplete.")
  checks <- lapply(seq_len(nrow(rows)), function(i) {
    row <- rows[i, ]; issues <- character()
    target <- file.path(site_dir, row$file)
    if (!file.exists(target) || !identical(unname(tools::md5sum(target)), row$md5)) issues <- c(issues, "staged map checksum")
    if (file.exists(target) && !identical(readBin(target, "raw", n = 8), as.raw(c(137, 80, 78, 71, 13, 10, 26, 10))))
      issues <- c(issues, "invalid PNG")
    reference <- paste0("../../", row$file)
    page <- file.path(site_dir, "pages/archive", sprintf("wy%d.qmd", row$water_year))
    text <- if (file.exists(page)) paste(readLines(page, warn = FALSE), collapse = "\n") else ""
    if (!grepl(paste0("](", reference, ")"), text, fixed = TRUE) ||
        !grepl(paste0("[Open full-resolution PNG](", reference, ")"), text, fixed = TRUE)) issues <- c(issues, "source page image/link")
    if (require_rendered) {
      rendered <- file.path(site_dir, "_site", row$file)
      if (!file.exists(rendered) || !identical(unname(tools::md5sum(rendered)), row$md5)) issues <- c(issues, "rendered map checksum")
      html <- file.path(site_dir, "_site/pages/archive", sprintf("wy%d.html", row$water_year))
      doc <- if (file.exists(html)) tryCatch(xml2::read_html(html), error = function(e) NULL) else NULL
      images <- if (!is.null(doc)) xml2::xml_attr(xml2::xml_find_all(doc, "//img"), "src") else character()
      anchors <- if (!is.null(doc)) xml2::xml_find_all(doc, "//a[@href]") else NULL
      linked <- !is.null(anchors) && any(xml2::xml_attr(anchors, "href") == reference &
        grepl("Open full-resolution PNG", xml2::xml_text(anchors), fixed = TRUE))
      if (!reference %in% images || !linked) issues <- c(issues, "rendered page image/link")
    }
    data.frame(water_year = row$water_year, file = row$file,
      status = if (length(issues)) "FAIL" else "PASS", note = paste(issues, collapse = "; "))
  })
  checks <- do.call(rbind, checks)
  if (require_rendered) {
    rendered_manifest <- file.path(site_dir, "_site/assets/snodas-seasonal-anomalies.json")
    if (!file.exists(rendered_manifest) || !identical(unname(tools::md5sum(path)), unname(tools::md5sum(rendered_manifest))))
      checks <- rbind(checks, data.frame(water_year = NA_integer_, file = "assets/snodas-seasonal-anomalies.json",
        status = "FAIL", note = "rendered manifest checksum"))
  }
  result <- data.frame(status = if (any(checks$status != "PASS")) "FAIL" else "PASS",
    years = length(years), maps = nrow(rows), anomaly_maps = length(years) * 2L,
    failed = sum(checks$status != "PASS"), rendered = require_rendered)
  dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
  write.csv(checks, file.path(report_dir, "checks.csv"), row.names = FALSE)
  write.csv(result, file.path(report_dir, "summary.csv"), row.names = FALSE)
  if (fail && result$failed > 0L) stop("Historical snow publication validation failed; inspect ", report_dir, "/checks.csv")
  result
}
