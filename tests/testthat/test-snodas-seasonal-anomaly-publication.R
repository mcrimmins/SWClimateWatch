source(file.path(project_root, "R/snodas-seasonal-archive-batch.R"))
source(file.path(project_root, "R/snodas-historic-site.R"))
source(file.path(project_root, "R/snodas-seasonal-anomaly-publication.R"))

testthat::test_that("historical snow activation requires the fixed eligible year set", {
  path <- tempfile(fileext = ".yml"); on.exit(unlink(path), add = TRUE)
  writeLines("enabled: false", path)
  testthat::expect_identical(snodas_anomaly_publication_years(path), integer())
  writeLines(c("enabled: true", "years: [2024]"), path)
  testthat::expect_error(snodas_anomaly_publication_years(path), "complete eligible")
  yaml::write_yaml(list(enabled = TRUE, years = 2005:2025), path)
  testthat::expect_identical(snodas_anomaly_publication_years(path), 2005:2025)
})

testthat::test_that("snow staging and publication checks cover all four maps and rendered links", {
  root <- tempfile(); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  site <- file.path(root, "site"); anomaly <- file.path(root, "anomalies")
  dir.create(file.path(site, "pages/archive"), recursive = TRUE); dir.create(anomaly)
  writeLines(c("---", "title: Test year", "---", "Keep this PRISM paragraph."),
    file.path(site, "pages/archive/wy2024.qmd"))
  sample <- file.path(root, "sample.png")
  grDevices::png(sample, width = 100, height = 100); graphics::par(mar = rep(0, 4))
  graphics::plot.new(); grDevices::dev.off()
  for (kind in c("departure", "percent-median"))
    file.copy(sample, file.path(anomaly, paste0("wy2024-peak-swe-", kind, ".png")))
  write.csv(data.frame(publication_ready = TRUE, baseline_start_wy = 2005L, baseline_end_wy = 2025L,
    min_years = 18L, minimum_coverage = .95, minimum_median_inches = 1,
    target_in_reference = TRUE, departure_low_snow_rule = "Gray near-zero low-median cells"),
    file.path(anomaly, "methods.csv"), row.names = FALSE)
  inventory <- data.frame(water_year = 2024L, source_signature = "source", peak_md5 = "peak",
    coverage_md5 = "coverage", quality_md5 = "quality", quality_status = "REVIEW")
  write.csv(inventory, file.path(anomaly, "source-inventory.csv"), row.names = FALSE)
  ctx <- new.env(parent = globalenv())
  source(file.path(project_root, "R/snodas-seasonal-anomaly-publication.R"), local = ctx)
  ctx$verify_snodas_anomaly_preview_inputs <- function(...) data.frame(file =
    c("wy2024-peak-swe-departure.png", "wy2024-peak-swe-percent-median.png"))
  ctx$plan_snodas_historic_site <- function(...) data.frame(water_year = 2024L, maps_to_copy = 2L)
  ctx$stage_snodas_historic_site <- function(years, dry_run, site_maps_root, page_dir, archive_root) {
    dir.create(file.path(site_maps_root, "wy2024"), recursive = TRUE, showWarnings = FALSE)
    for (file in c("peak_swe.png", "snow_days.png")) file.copy(sample, file.path(site_maps_root, "wy2024", file))
  }
  plan <- ctx$stage_snodas_seasonal_anomaly_archive(site, anomaly, years = 2024L, dry_run = TRUE)
  testthat::expect_equal(plan$anomaly_maps_to_copy, 2L)
  testthat::expect_false(file.exists(file.path(site, "assets/snodas-seasonal-anomalies.json")))
  ctx$stage_snodas_seasonal_anomaly_archive(site, anomaly, years = 2024L, dry_run = FALSE)
  report <- file.path(root, "reports")
  result <- validate_snodas_seasonal_anomaly_publication(site, require_rendered = FALSE, years = 2024L, report_dir = report)
  testthat::expect_equal(result$status, "PASS")
  testthat::expect_equal(result$maps, 4L)
  testthat::expect_true(any(grepl("Keep this PRISM", readLines(file.path(site, "pages/archive/wy2024.qmd")), fixed = TRUE)))
  manifest <- jsonlite::read_json(file.path(site, "assets/snodas-seasonal-anomalies.json"), simplifyVector = TRUE)
  rendered <- file.path(site, "_site"); dir.create(file.path(rendered, "pages/archive"), recursive = TRUE)
  dir.create(file.path(rendered, "assets"))
  file.copy(file.path(site, "assets/snodas-seasonal-anomalies.json"), file.path(rendered, "assets/snodas-seasonal-anomalies.json"))
  for (path in manifest$maps$file) {
    dir.create(dirname(file.path(rendered, path)), recursive = TRUE, showWarnings = FALSE)
    file.copy(file.path(site, path), file.path(rendered, path))
  }
  html <- paste0('<img src="../../', manifest$maps$file, '"><a href="../../', manifest$maps$file, '">Open full-resolution PNG</a>')
  page <- file.path(rendered, "pages/archive/wy2024.html"); writeLines(html, page)
  testthat::expect_equal(validate_snodas_seasonal_anomaly_publication(site, years = 2024L, report_dir = report)$status, "PASS")
  writeLines(html[-4], page)
  testthat::expect_error(validate_snodas_seasonal_anomaly_publication(site, years = 2024L, report_dir = report), "validation failed")
  writeLines(html, page)
  writeLines("bad image", file.path(rendered, manifest$maps$file[4]))
  testthat::expect_error(validate_snodas_seasonal_anomaly_publication(site, years = 2024L, report_dir = report), "validation failed")
  testthat::expect_error(validate_snodas_seasonal_anomaly_publication(root, years = 2024L, report_dir = report), "manifest")
})
