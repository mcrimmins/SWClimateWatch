source(file.path(project_root, "R", "snodas-seasonal-archive-batch.R"))
source(file.path(project_root, "R", "snodas-historic-site.R"))

testthat::test_that("seasonal staging requires complete matching checksums", {
  sandbox <- tempfile("snodas-site-test-")
  year_dir <- file.path(sandbox, "wy2024")
  dir.create(year_dir, recursive = TRUE)
  paths <- snodas_historic_source_paths(2024L, sandbox)
  for (path in paths[names(paths) != "complete"]) {
    writeLines(basename(path), path)
  }
  quality <- data.frame(water_year = 2024L,
                        source_signature = "test-signature",
                        status = "REVIEW")
  utils::write.csv(quality, paths[["quality"]], row.names = FALSE)
  marker <- data.frame(source_signature = "test-signature")
  for (name in names(paths)[names(paths) != "complete"]) {
    marker[[paste0(name, "_md5")]] <-
      unname(tools::md5sum(paths[[name]]))
  }
  utils::write.csv(marker, paths[["complete"]], row.names = FALSE)
  checked <- snodas_historic_verify_output(2024L, sandbox)
  testthat::expect_equal(checked$quality$status, "REVIEW")
  writeLines("changed", paths[["peak_map"]])
  testthat::expect_error(
    snodas_historic_verify_output(2024L, sandbox), "checksums")
})

testthat::test_that("snow cards can be added without duplicating the section", {
  page_dir <- tempfile("snodas-pages-")
  dir.create(page_dir)
  page <- file.path(page_dir, "wy2024.qmd")
  original <- c("---", 'title: "Water year 2024"', "---", "",
                "## Full water year", "", "Keep this custom paragraph.")
  writeLines(original, page)
  write_snodas_historic_page_section(2024L, page_dir)
  first <- readLines(page, warn = FALSE)
  testthat::expect_true(any(grepl("Keep this custom paragraph", first,
                                  fixed = TRUE)))
  testthat::expect_equal(sum(grepl("Open full-resolution PNG", first,
                                  fixed = TRUE)), 2L)
  testthat::expect_equal(sum(grepl("BEGIN GENERATED SNODAS", first,
                                  fixed = TRUE)), 1L)
  write_snodas_historic_page_section(2024L, page_dir)
  testthat::expect_identical(readLines(page, warn = FALSE), first)
})

testthat::test_that("staging rejects stale triage or changed retain decisions", {
  sandbox <- tempfile("snodas-site-gate-")
  archive_root <- file.path(sandbox, "archive")
  triage_dir <- file.path(sandbox, "triage")
  decisions_path <- file.path(sandbox, "decisions.csv")
  dir.create(triage_dir, recursive = TRUE)
  summary <- data.frame(
    water_year = 2005:2025,
    archive_state = rep("OUTPUTS_VERIFIED", 21L),
    missing_evidence_episodes = integer(21L),
    source_signature = paste0("sig-", 2005:2025),
    peak_swe_md5 = rep(NA_character_, 21L),
    quality_md5 = rep(NA_character_, 21L))
  for (year in 2005:2025) {
    paths <- snodas_historic_source_paths(year, archive_root)
    dir.create(dirname(paths[["peak_swe"]]), recursive = TRUE)
    for (path in paths[names(paths) != "complete"]) {
      writeLines(basename(path), path)
    }
    quality <- data.frame(water_year = year,
                          source_signature = paste0("sig-", year),
                          status = "PASS")
    utils::write.csv(quality, paths[["quality"]], row.names = FALSE)
    marker <- data.frame(source_signature = paste0("sig-", year))
    for (name in names(paths)[names(paths) != "complete"]) {
      marker[[paste0(name, "_md5")]] <-
        unname(tools::md5sum(paths[[name]]))
    }
    utils::write.csv(marker, paths[["complete"]], row.names = FALSE)
    i <- year - 2004L
    summary$peak_swe_md5[i] <- marker$peak_swe_md5
    summary$quality_md5[i] <- marker$quality_md5
  }
  peaks <- data.frame(water_year = 2005L, cell = 1L,
                      peak_date = "2005-03-01", peak_swe_inches = 21,
                      pilot_priority = "REVIEW_EVENT")
  benchmarks <- data.frame(
    water_year = integer(), cell = integer(), rule_id = character(),
    source_matched = logical(), relative_detected = logical(),
    triage_priority = character())
  decision <- data.frame(water_year = 2005L, cell = 1L,
                         peak_date = "2005-03-01", peak_swe_inches = 21,
                         source_signature = "sig-2005",
                         decision = "retain")
  utils::write.csv(summary, file.path(triage_dir, "year-summary.csv"),
                   row.names = FALSE)
  utils::write.csv(peaks, file.path(triage_dir, "candidate-evidence.csv"),
                   row.names = FALSE)
  utils::write.csv(benchmarks,
                   file.path(triage_dir, "known-mask-benchmarks.csv"),
                   row.names = FALSE)
  utils::write.csv(decision, decisions_path, row.names = FALSE)
  checked <- snodas_historic_validate_triage(
    triage_dir, decisions_path, archive_root)
  testthat::expect_equal(nrow(checked$decisions), 1L)
  summary$peak_swe_md5[1L] <- "stale"
  utils::write.csv(summary, file.path(triage_dir, "year-summary.csv"),
                   row.names = FALSE)
  testthat::expect_error(snodas_historic_validate_triage(
    triage_dir, decisions_path, archive_root), "changed after")
  summary$peak_swe_md5[1L] <- checked$summary$peak_swe_md5[1L]
  utils::write.csv(summary, file.path(triage_dir, "year-summary.csv"),
                   row.names = FALSE)
  decision$peak_swe_inches <- 22
  utils::write.csv(decision, decisions_path, row.names = FALSE)
  testthat::expect_error(snodas_historic_validate_triage(
    triage_dir, decisions_path, archive_root), "changed since")
  decision$peak_swe_inches <- 21
  utils::write.csv(decision, decisions_path, row.names = FALSE)
  page_dir <- file.path(sandbox, "pages")
  site_maps_root <- file.path(sandbox, "site-maps")
  dir.create(page_dir)
  page <- file.path(page_dir, "wy2005.qmd")
  writeLines(c("---", 'title: "Water year 2005"', "---"), page)
  preview <- stage_snodas_historic_site(
    2005L, dry_run = TRUE, site_maps_root = site_maps_root,
    page_dir = page_dir, archive_root = archive_root,
    triage_dir = triage_dir, decisions_path = decisions_path)
  testthat::expect_equal(preview$maps_to_copy, 2L)
  testthat::expect_false(dir.exists(site_maps_root))
  stage_snodas_historic_site(
    2005L, dry_run = FALSE, site_maps_root = site_maps_root,
    page_dir = page_dir, archive_root = archive_root,
    triage_dir = triage_dir, decisions_path = decisions_path)
  testthat::expect_true(all(file.exists(file.path(
    site_maps_root, "wy2005", c("peak_swe.png", "snow_days.png")))))
  testthat::expect_true(any(grepl("## Snow season", readLines(page),
                                  fixed = TRUE)))
})
