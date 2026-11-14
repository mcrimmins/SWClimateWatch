source(file.path(project_root, "R", "snodas-historic-site.R"))

testthat::test_that("historic anomaly cards preserve existing content and are idempotent", {
  root <- tempfile(); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  page <- file.path(root, "wy2024.qmd")
  writeLines(c("---", 'title: "Water year 2024"', "---", "Keep the PRISM section."), page)
  write_snodas_historic_page_section(2024L, root, include_anomalies = TRUE)
  lines <- readLines(page)
  testthat::expect_equal(sum(grepl("Open full-resolution PNG", lines, fixed = TRUE)), 4L)
  testthat::expect_equal(sum(grepl("BEGIN GENERATED SNODAS SNOW MAPS", lines, fixed = TRUE)), 1L)
  testthat::expect_true(any(grepl("Keep the PRISM section", lines, fixed = TRUE)))
  testthat::expect_true(any(grepl("peak_swe_departure.png", lines, fixed = TRUE)))
  testthat::expect_true(any(grepl("peak_swe_percent_median.png", lines, fixed = TRUE)))
  testthat::expect_true(any(grepl("not same-date comparisons", lines, fixed = TRUE)))
  testthat::expect_true(any(grepl("not a percentile", lines, fixed = TRUE)))
  write_snodas_historic_page_section(2024L, root, include_anomalies = TRUE)
  testthat::expect_identical(readLines(page), lines)
  # Default staging remains the existing two-map release until explicit integration.
  testthat::expect_equal(sum(grepl("Open full-resolution PNG",
    snodas_historic_page_section(2024L), fixed = TRUE)), 2L)
})

testthat::test_that("anomaly page integration rejects changed outputs, sources and methods", {
  ctx <- new.env(parent = globalenv())
  source(file.path(project_root, "R", "snodas-seasonal-anomaly-site.R"), local = ctx)
  root <- tempfile(); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  inventory <- data.frame(water_year = 2005:2025, peak_md5 = "peak", coverage_md5 = "coverage",
    quality_md5 = "quality", source_signature = paste0("sig-", 2005:2025))
  ctx$snodas_peak_anomaly_inventory <- function(...) inventory
  utils::write.csv(inventory, file.path(root, "source-inventory.csv"), row.names = FALSE)
  methods <- data.frame(baseline_start_wy = 2005L, baseline_end_wy = 2025L, min_years = 18L,
    minimum_coverage = .95, minimum_median_inches = 1, target_in_reference = TRUE,
    departure_low_snow_rule = "gray near-zero low-median cells")
  utils::write.csv(methods, file.path(root, "methods.csv"), row.names = FALSE)
  for (name in c("pilot-summary.csv", "median_peak_swe.tif", "sample_years.tif"))
    writeLines("fixture", file.path(root, name))
  files <- list.files(root)
  save_marker <- function() utils::write.csv(data.frame(file = files,
    md5 = unname(tools::md5sum(file.path(root, files)))),
    file.path(root, "output-checksums.csv"), row.names = FALSE)
  save_marker()
  testthat::expect_equal(nrow(ctx$verify_snodas_anomaly_preview_inputs(root, "unused")), 5L)
  writeLines("changed", file.path(root, "median_peak_swe.tif"))
  testthat::expect_error(ctx$verify_snodas_anomaly_preview_inputs(root, "unused"), "outputs changed")
  save_marker()
  inventory$source_signature[1] <- "new-source"
  testthat::expect_error(ctx$verify_snodas_anomaly_preview_inputs(root, "unused"), "archive changed")
  inventory$source_signature[1] <- "sig-2005"
  methods$minimum_median_inches <- .5
  utils::write.csv(methods, file.path(root, "methods.csv"), row.names = FALSE); save_marker()
  testthat::expect_error(ctx$verify_snodas_anomaly_preview_inputs(root, "unused"), "methods")
})
