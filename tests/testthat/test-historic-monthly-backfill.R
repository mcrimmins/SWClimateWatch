for (file in c("prism-monthly", "prism-monthly-temperature", "historic-monthly-pilot",
    "historic-monthly-site-preview", "historic-monthly-backfill"))
  source(file.path(project_root, "R", paste0(file, ".R")))

testthat::test_that("backfill spans all 86 earlier years and never admits existing-year targets", {
  years <- historic_monthly_backfill_years()
  testthat::expect_identical(years, 1896L:1981L)
  testthat::expect_equal(length(years) * historic_monthly_products_per_year(), 1806L)
  testthat::expect_equal(nrow(historic_monthly_windows(years)), 344L)
  testthat::expect_error(build_historic_monthly_backfill(years = 1982L), "WY1896")
  outside <- tempfile("outside-backfill-")
  testthat::expect_error(build_historic_monthly_backfill(1896L, outside), "under data/diagnostics")
  testthat::expect_false(dir.exists(outside))
  for (year in years) {
    parts <- historic_preview_early_parts(year)
    testthat::expect_length(parts$daily, 0L)
    testthat::expect_length(parts$snow, 0L)
    testthat::expect_true(is.na(parts$roni))
    specs <- historic_monthly_periods()
    rows <- do.call(rbind, lapply(specs$id, function(period) {
      metrics <- names(historic_monthly_metrics())[1:5]
      if (period == "water-year") metrics <- c(metrics, "spi12")
      data.frame(water_year = year, period = period, metric = metrics,
        relative_map = paste0("wy", year, "/", period, "/", metrics, ".png"),
        comparison_first_year = 1896L, comparison_last_year = 2026L)
    }))
    page <- historic_preview_page(character(), rows, parts)
    testthat::expect_equal(sum(startsWith(page, "![")), 21L)
    testthat::expect_identical(sub("### ", "", page[startsWith(page, "### ")]), specs$label)
  }
  nav <- historic_preview_navigation(years)
  hrefs <- unlist(lapply(nav, function(x) vapply(x$contents, function(y) y$href, character(1))))
  testthat::expect_equal(length(hrefs), 86L)
  testthat::expect_false(anyDuplicated(hrefs) > 0)
  testthat::expect_equal(as.integer(sub(".*wy([0-9]{4})[.]qmd", "\\1", hrefs)), rev(years))
})

testthat::test_that("partial backfill cannot pass full coverage or stale protected-file checks", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  protected <- file.path(root, "protected.qmd"); writeLines("unchanged site", protected)
  write.csv(data.frame(path = protected, md5 = unname(tools::md5sum(protected))),
    file.path(root, "protected-files.csv"), row.names = FALSE)
  years <- c(1896L, 1934L, 1977L)
  write.csv(data.frame(water_year = years, monthly_maps = 21L), file.path(root, "year-scope.csv"), row.names = FALSE)
  write.csv(data.frame(water_year = rep(years, each = 21L)), file.path(root, "manifest.csv"), row.names = FALSE)
  testthat::expect_silent(historic_monthly_backfill_scope(root, years))
  testthat::expect_error(check_historic_monthly_backfill_maps(root), "missing or has extra")
  testthat::expect_equal(read.csv(file.path(root, "validation-status.csv"))$status, "CHECKING")
  writeLines("changed site", protected)
  testthat::expect_error(historic_monthly_backfill_scope(root, years), "Protected")
})
