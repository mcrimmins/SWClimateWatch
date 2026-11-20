for (file in c("prism-monthly", "prism-monthly-temperature", "historic-monthly-pilot", "map-product-site",
    "historic-monthly-site-preview", "historic-monthly-publication", "prism-seasonal-archive",
    "historic-monthly-backfill-publication"))
  source(file.path(project_root, "R", paste0(file, ".R")))

publication_fixture <- function(root, years = 1982:2025) {
  windows <- historic_monthly_windows(years)
  rows <- do.call(rbind, lapply(seq_len(nrow(windows)), function(i) {
    row <- windows[i, ]; metrics <- names(historic_monthly_metrics())[1:5]
    if (row$period == "water-year") metrics <- c(metrics, "spi12")
    data.frame(water_year = row$water_year, period = row$period, metric = metrics,
      start = row$start, end = row$end,
      relative_map = paste0("wy", row$water_year, "/", row$period, "/", metrics, ".png"),
      comparison_first_year = 1896L, comparison_last_year = 2026L)
  }))
  for (path in file.path(root, "maps", rows$relative_map)) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines("fixture map bytes", path)
  }
  rows$md5 <- unname(tools::md5sum(file.path(root, "maps", rows$relative_map)))
  write.csv(rows, file.path(root, "manifest.csv"), row.names = FALSE)
  jsonlite::write_json(list(status = "READY", manifest_md5 = unname(tools::md5sum(file.path(root, "manifest.csv")))),
    file.path(root, "release.json"), auto_unbox = TRUE)
  rows
}

testthat::test_that("early publication creates repeatable monthly-only pages with no invented historical context", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  release <- file.path(root, "release"); dir.create(release)
  years <- c(1896L, 1977L)
  rows <- publication_fixture(release, years)
  site <- file.path(root, "site"); dir.create(site)
  old <- getwd(); setwd(project_root); on.exit(setwd(old), add = TRUE)
  stage_historic_monthly_release(release, site, expected_years = years)
  testthat::expect_equal(validate_historic_monthly_publication(release, site, FALSE, years)$monthly_maps, 42L)
  pages <- file.path(site, "pages/archive", paste0("wy", years, ".qmd"))
  hashes <- unname(tools::md5sum(pages))
  stage_historic_monthly_release(release, site, expected_years = years)
  testthat::expect_identical(unname(tools::md5sum(pages)), hashes)
  for (page in pages) {
    text <- readLines(page, warn = FALSE)
    testthat::expect_equal(sum(startsWith(text, "![")), 21L)
    testthat::expect_false(any(grepl("Local layout review|Local pilot", text)))
    testthat::expect_true(any(grepl("Historical ENSO context has not been attached", text, fixed = TRUE)))
  }
  cat("\n[Invented RONI 0.0]{.archive-roni-badge}\n", file = pages[1], append = TRUE)
  testthat::expect_error(validate_historic_monthly_publication(release, site, FALSE, years), "ENSO context")
})

testthat::test_that("combined navigation includes all 130 years once and rejects incomplete migrations", {
  root <- tempfile(); dir.create(file.path(root, "pages/archive"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  file.copy(file.path(project_root, "site/_quarto.yml"), file.path(root, "_quarto.yml"))
  for (year in 1896:2025) writeLines("fixture", file.path(root, "pages/archive", paste0("wy", year, ".qmd")))
  historic_monthly_backfill_navigation(root)
  config <- readLines(file.path(root, "_quarto.yml"))
  hrefs <- trimws(config[grepl("href: pages/archive/wy", config, fixed = TRUE)])
  testthat::expect_equal(length(hrefs), 130L)
  testthat::expect_false(anyDuplicated(hrefs) > 0L)
  testthat::expect_setequal(hrefs, sprintf("- href: pages/archive/wy%d.qmd", 1896:2025))
  unlink(file.path(root, "pages/archive/wy1896.qmd"))
  testthat::expect_error(historic_monthly_backfill_navigation(root), "required combined")
})

testthat::test_that("portable release rejects missing files, corruption, unsafe paths and incomplete years", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE))
  rows <- publication_fixture(root, 2002L)
  testthat::expect_equal(nrow(historic_monthly_release_records(root, 2002L)), 21L)
  testthat::expect_error(historic_monthly_release_records(root), "coverage")
  image <- file.path(root, "maps", rows$relative_map[1])
  writeLines("changed", image)
  testthat::expect_error(historic_monthly_release_records(root, 2002L), "checksum")
  unlink(image)
  testthat::expect_error(historic_monthly_release_records(root, 2002L), "checksum")
  rows$relative_map[1] <- "../../escape.png"
  write.csv(rows, file.path(root, "manifest.csv"), row.names = FALSE)
  testthat::expect_error(historic_monthly_release_records(root, 2002L), "changed")
  jsonlite::write_json(list(status = "READY", manifest_md5 = unname(tools::md5sum(file.path(root, "manifest.csv")))),
    file.path(root, "release.json"), auto_unbox = TRUE)
  testthat::expect_error(historic_monthly_release_records(root, 2002L), "Unsafe")
})

testthat::test_that("publication staging is repeatable and preserves each existing year's detail and snow", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE))
  release <- file.path(root, "release"); dir.create(release)
  rows <- publication_fixture(release)
  site <- file.path(root, "site"); dir.create(file.path(site, "pages/archive"), recursive = TRUE)
  files <- list.files(file.path(project_root, "site/pages/archive"), pattern = "^wy[0-9]{4}[.]qmd$", full.names = TRUE)
  file.copy(files, file.path(site, "pages/archive"))
  # The copy helper's only relative resource is the reviewed CSS.
  old <- getwd(); setwd(project_root); on.exit(setwd(old), add = TRUE)
  stage_historic_monthly_release(release, site)
  first <- unname(tools::md5sum(file.path(site, "pages/archive", basename(files))))
  stage_historic_monthly_release(release, site)
  testthat::expect_identical(first, unname(tools::md5sum(file.path(site, "pages/archive", basename(files)))))
  testthat::expect_equal(validate_historic_monthly_publication(release, site, FALSE)$monthly_maps, 924L)
  for (path in files) {
    before <- historic_preview_source_parts(readLines(path, warn = FALSE))
    after <- historic_preview_source_parts(readLines(file.path(site, "pages/archive", basename(path)), warn = FALSE))
    testthat::expect_identical(before$daily, after$daily)
    testthat::expect_identical(before$snow, after$snow)
  }
  page <- file.path(site, "pages/archive/wy2002.qmd")
  text <- readLines(page, warn = FALSE)
  writeLines(text[!grepl("![Mean temperature]", text, fixed = TRUE)], page)
  testthat::expect_error(validate_historic_monthly_publication(release, site, FALSE), "count")
})
