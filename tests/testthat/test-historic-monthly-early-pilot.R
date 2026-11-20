for (file in c("prism-monthly", "prism-monthly-temperature", "historic-monthly-pilot",
    "historic-monthly-site-preview", "historic-monthly-early-pilot"))
  source(file.path(project_root, "R", paste0(file, ".R")))

early_layout_rows <- function(years) {
  windows <- historic_monthly_windows(years)
  do.call(rbind, lapply(seq_len(nrow(windows)), function(i) {
    row <- windows[i, ]; metrics <- names(historic_monthly_metrics())[1:5]
    if (row$period == "water-year") metrics <- c(metrics, "spi12")
    data.frame(water_year = row$water_year, period = row$period, metric = metrics,
      relative_map = paste0("wy", row$water_year, "/", row$period, "/", metrics, ".png"),
      comparison_first_year = 1896L, comparison_last_year = 2026L)
  }))
}

testthat::test_that("early pages include only requested monthly maps and honest context/availability notes", {
  testthat::expect_identical(historic_monthly_early_years(), c(1896L, 1934L, 1977L))
  for (year in historic_monthly_early_years()) {
    parts <- historic_preview_early_parts(year)
    page <- historic_preview_page(character(), early_layout_rows(year), parts)
    text <- paste(page, collapse = "\n")
    testthat::expect_equal(sum(startsWith(page, "![")), 21L)
    testthat::expect_identical(sub("### ", "", page[startsWith(page, "### ")]), historic_monthly_periods()$label)
    testthat::expect_true(grepl(paste0("October 1, ", year - 1L, " to September 30, ", year), text, fixed = TRUE))
    testthat::expect_true(grepl("Historical ENSO context has not been attached", text, fixed = TRUE))
    testthat::expect_false(grepl("archive-roni-badge|range conditions|/seasonal-archive/", text))
    testthat::expect_true(grepl("no daily maps from another year", text, fixed = TRUE))
    testthat::expect_true(grepl("SNODAS seasonal archive begins in WY2005", text, fixed = TRUE))
    testthat::expect_equal(sum(startsWith(page, '<details class="historic-review-details">')), 3L)
    testthat::expect_equal(sum(grepl("![September SPI-12]", page, fixed = TRUE)), 1L)
  }
  testthat::expect_error(historic_preview_early_parts(1895L), "WY1896")
  testthat::expect_error(historic_preview_early_parts(1982L), "WY1896")
})

testthat::test_that("early source previews require explicit opt-in and retain strict exact-year coverage", {
  old <- getwd(); setwd(project_root); on.exit(setwd(old), add = TRUE)
  root <- tempfile("early-layout-", tmpdir = "data/diagnostics")
  dir.create(root, recursive = TRUE); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  input <- file.path(root, "input"); dir.create(input)
  rows <- early_layout_rows(historic_monthly_early_years())
  rows$map <- file.path(input, paste0(seq_len(nrow(rows)), ".png"))
  for (path in rows$map) writeLines("fixture image bytes", path)
  write.csv(rows, file.path(input, "manifest.csv"), row.names = FALSE)
  write.csv(data.frame(status = "READY", years = 3L), file.path(input, "summary.csv"), row.names = FALSE)
  writeLines("monthly-only pilot", file.path(input, "methods.txt"))
  output <- file.path(root, "site")
  testthat::expect_error(build_historic_monthly_site_preview(input, output), "source page is missing")
  build_historic_monthly_site_preview(input, output, expected_years = historic_monthly_early_years(), allow_early = TRUE)
  result <- validate_historic_monthly_site_preview(output, FALSE, historic_monthly_early_years(), allow_early = TRUE)
  testthat::expect_equal(result$monthly_maps, 63L)
  testthat::expect_equal(result$daily_detail_maps, 0L)
  testthat::expect_equal(result$snow_maps, 0L)
  testthat::expect_error(validate_historic_monthly_site_preview(output, FALSE), "complete Historic")
  testthat::expect_error(validate_historic_monthly_site_preview(output, FALSE, c(1896L, 1934L), TRUE), "extra")
  plan <- read.csv(file.path(output, "preview-plan.csv"))
  testthat::expect_identical(plan$water_year, historic_monthly_early_years())
})
