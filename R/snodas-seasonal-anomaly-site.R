# Isolated full-page review; standard site staging remains unchanged.
verify_snodas_anomaly_preview_inputs <- function(anomaly_dir, archive_root) {
  marker_path <- file.path(anomaly_dir, "output-checksums.csv")
  if (!file.exists(marker_path)) stop("Rebuild the seasonal anomaly pilot first (missing output checksums).")
  marker <- utils::read.csv(marker_path, stringsAsFactors = FALSE)
  required <- c("methods.csv", "source-inventory.csv", "pilot-summary.csv",
    "median_peak_swe.tif", "sample_years.tif")
  if (!all(c("file", "md5") %in% names(marker)) || anyNA(marker) ||
      anyDuplicated(marker$file) || any(!grepl("^[A-Za-z0-9_.-]+$", marker$file)) ||
      !all(required %in% marker$file)) stop("Invalid anomaly output checksums.")
  paths <- file.path(anomaly_dir, marker$file)
  if (!all(file.exists(paths)) || !identical(unname(tools::md5sum(paths)), marker$md5))
    stop("Anomaly outputs changed; rebuild the pilot before integration.")
  inventory <- utils::read.csv(file.path(anomaly_dir, "source-inventory.csv"), stringsAsFactors = FALSE)
  current <- snodas_peak_anomaly_inventory(2005:2025, archive_root)
  keys <- c("water_year", "peak_md5", "coverage_md5", "quality_md5", "source_signature")
  if (!all(keys %in% names(inventory)) || !identical(inventory[keys], current[keys]))
    stop("Seasonal archive changed since the anomaly build; rebuild the pilot.")
  methods <- utils::read.csv(file.path(anomaly_dir, "methods.csv"), stringsAsFactors = FALSE)
  if (nrow(methods) != 1L || !all(c("baseline_start_wy", "baseline_end_wy", "min_years",
      "minimum_coverage", "minimum_median_inches", "target_in_reference", "departure_low_snow_rule") %in% names(methods)) ||
      !isTRUE(methods$baseline_start_wy == 2005L && methods$baseline_end_wy == 2025L &&
        methods$min_years == 18L && methods$minimum_coverage == .95 &&
        methods$minimum_median_inches == 1 && methods$target_in_reference))
    stop("Anomaly methods do not match the Historic Years explanatory text.")
  marker
}

build_snodas_historic_anomaly_preview <- function(years = c(2005L, 2018L, 2024L),
    anomaly_dir = "data/diagnostics/snodas-seasonal-anomaly-pilot",
    output_dir = "data/diagnostics/snodas-historic-anomaly-preview",
    site_dir = "site", archive_root = "data/diagnostics/snodas-seasonal-archive") {
  years <- validate_snodas_seasonal_archive_years(years)
  marker <- verify_snodas_anomaly_preview_inputs(anomaly_dir, archive_root)
  # Preserve the same reviewed-source gate used by ordinary Historic Years staging.
  reviewed <- snodas_historic_validate_triage(archive_root = archive_root)
  files <- unlist(lapply(years, function(year)
    sprintf("wy%d-peak-swe-%s.png", year, c("departure", "percent-median"))))
  if (!all(files %in% marker$file)) stop("Requested anomaly maps are not in the verified pilot.")
  page_dir <- file.path(output_dir, "pages", "archive")
  dir.create(page_dir, recursive = TRUE, showWarnings = FALSE)
  copy <- function(from, to) {
    if (!file.exists(from)) stop("Missing preview input: ", from)
    dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(from, to, overwrite = TRUE) ||
        !identical(unname(tools::md5sum(from)), unname(tools::md5sum(to))))
      stop("Could not verify copied preview asset: ", to)
  }
  for (year in years) {
    page <- sprintf("wy%d.qmd", year)
    source_page <- file.path(site_dir, "pages", "archive", page)
    copy(source_page, file.path(page_dir, page))
    write_snodas_historic_page_section(year, page_dir, include_anomalies = TRUE)
    # Existing PRISM maps stay on the full copied page, alongside the snow maps.
    text <- paste(readLines(source_page, warn = FALSE), collapse = "\n")
    refs <- unique(regmatches(text, gregexpr("\\.\\./\\.\\./maps/[A-Za-z0-9_./-]+\\.png", text))[[1]])
    for (ref in refs) {
      relative <- sub("^\\.\\./\\.\\./", "", ref)
      copy(file.path(site_dir, relative), file.path(output_dir, relative))
    }
    maps_dir <- file.path(output_dir, "maps/generated/snodas/seasonal-archive", paste0("wy", year))
    source <- reviewed$verified[[year - 2004L]]$paths
    copy(source[["peak_map"]], file.path(maps_dir, "peak_swe.png"))
    copy(source[["snow_days_map"]], file.path(maps_dir, "snow_days.png"))
    copy(file.path(anomaly_dir, sprintf("wy%d-peak-swe-departure.png", year)),
      file.path(maps_dir, "peak_swe_departure.png"))
    copy(file.path(anomaly_dir, sprintf("wy%d-peak-swe-percent-median.png", year)),
      file.path(maps_dir, "peak_swe_percent_median.png"))
  }
  copy(file.path(site_dir, "styles.css"), file.path(output_dir, "styles.css"))
  config <- list(project = list(type = "website", `output-dir` = "_site"),
    website = list(title = "Historic Snow - Local Review", sidebar = list(
      contents = lapply(years, function(year) list(href = sprintf("pages/archive/wy%d.qmd", year), text = paste("Water year", year))))),
    format = list(html = list(theme = list(light = "flatly", dark = "darkly"), css = "styles.css")))
  yaml::write_yaml(config, file.path(output_dir, "_quarto.yml"))
  writeLines(c("/.quarto/", "/_site/"), file.path(output_dir, ".gitignore"))
  writeLines(c("---", 'title: "Historic snow anomaly review"', "---", "",
    "Local review only. Full Historic Years pages with two seasonal snow anomaly companion maps. No production pages changed.", "",
    sprintf("- [Water year %d](pages/archive/wy%d.qmd#snow-season)", years, years)),
    file.path(output_dir, "index.qmd"))
  utils::write.csv(data.frame(water_year = years, snow_maps = 4L,
    page = sprintf("pages/archive/wy%d.qmd", years)), file.path(output_dir, "preview-plan.csv"), row.names = FALSE)
  message("Historic snow page preview prepared: ", output_dir, ". Standard site unchanged.")
  invisible(output_dir)
}
