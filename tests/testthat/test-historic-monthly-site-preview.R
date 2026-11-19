source(file.path(project_root, "R/historic-monthly-pilot.R"))
source(file.path(project_root, "R/map-product-site.R"))
source(file.path(project_root, "R/historic-monthly-site-preview.R"))
source(file.path(project_root, "R/historic-monthly-archive.R"))

historic_layout_fixture <- function(year) {
  specs <- historic_monthly_periods()
  do.call(rbind, lapply(seq_len(nrow(specs)), function(i) {
    metrics <- names(historic_monthly_metrics())[1:5]
    if (specs$id[i] == "water-year") metrics <- c(metrics, "spi12")
    data.frame(water_year = year, period = specs$id[i], metric = metrics,
      relative_map = paste0("wy", year, "/", specs$id[i], "/", metrics, ".png"),
      comparison_first_year = 1896L, comparison_last_year = 2026L)
  }))
}

testthat::test_that("local page assembly preserves source detail and introduces exactly 21 maps in four tabs", {
  for (year in historic_monthly_archive_years(file.path(project_root, "site"))) {
    path <- file.path(project_root, "site/pages/archive", paste0("wy", year, ".qmd"))
    before <- tools::md5sum(path)
    original <- readLines(path, warn = FALSE, encoding = "UTF-8")
    parts <- historic_preview_source_parts(original)
    page <- historic_preview_page(original, historic_layout_fixture(year))
    text <- paste(page, collapse = "\n")
    refs <- unique(regmatches(text, gregexpr("\\.\\./\\.\\./maps/[A-Za-z0-9_./-]+[.]png", text))[[1L]])
    testthat::expect_equal(sum(grepl("/historic-monthly-pilot/", refs, fixed = TRUE)), 21L)
    testthat::expect_equal(sum(grepl("/prism/seasonal-archive/", refs, fixed = TRUE)), 4L)
    testthat::expect_equal(sum(grepl("/snodas/", refs, fixed = TRUE)), if (year >= 2005) 4L else 0L)
    testthat::expect_equal(sum(grepl("^### ", page)), 4L)
    testthat::expect_true(grepl(paste(parts$daily, collapse = "\n"), text, fixed = TRUE))
    if (length(parts$snow)) testthat::expect_true(grepl(paste(parts$snow, collapse = "\n"), text, fixed = TRUE)) else
      testthat::expect_match(text, "SNODAS seasonal archive begins in WY2005")
    testthat::expect_false(any(grepl("/cool_total.png|/cool_percentile.png|/water_total.png|/water_percentile.png", page)))
    testthat::expect_true(any(grepl("April-June", page, fixed = TRUE)))
    testthat::expect_true(any(grepl("July-September", page, fixed = TRUE)))
    testthat::expect_identical(tools::md5sum(path), before)
    testthat::expect_match(text, "index-magnitude conditions")
    testthat::expect_equal(sum(grepl('<details class="historic-review-details">', page, fixed = TRUE)), 3L)
    testthat::expect_identical(historic_preview_page(page, historic_layout_fixture(year)), page)
  }
})

testthat::test_that("full archive navigation covers every existing year once in descending decade groups", {
  years <- historic_monthly_archive_years(file.path(project_root, "site"))
  testthat::expect_identical(years, 1982:2025)
  nav <- historic_preview_navigation(years)
  links <- unlist(lapply(nav, function(group) vapply(group$contents, function(link) link$href, character(1))), use.names = FALSE)
  testthat::expect_length(links, 44L)
  testthat::expect_false(anyDuplicated(links) > 0)
  testthat::expect_identical(links, paste0("pages/archive/wy", rev(years), ".qmd"))
})

testthat::test_that("a partial archive batch cannot pass the existing-year coverage gate", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  write.csv(data.frame(water_year = c(1982L, 2002L, 2005L, 2020L)),
    file.path(root, "year-scope.csv"), row.names = FALSE)
  write.csv(data.frame(water_year = c(1982L, 2002L, 2005L, 2020L)),
    file.path(root, "manifest.csv"), row.names = FALSE)
  testthat::expect_error(check_historic_monthly_archive_maps(root, expected_years = 1982:2025), "missing or has extra")
  testthat::expect_equal(read.csv(file.path(root, "validation-status.csv"))$status, "CHECKING")
})

testthat::test_that("historic RONI labels retain values, periods and source without claiming official episodes", {
  path <- file.path(project_root, "site/pages/archive/wy2005.qmd")
  original <- readLines(path, warn = FALSE, encoding = "UTF-8")
  parts <- historic_preview_source_parts(original)
  testthat::expect_equal(parts$roni, .5)
  testthat::expect_true(any(grepl("Weak El Ni", parts$intro, fixed = TRUE)))
  testthat::expect_true(any(grepl("-range conditions", parts$intro, fixed = TRUE)))
  testthat::expect_identical(parts$intro[grepl("December-February", parts$intro)], original[grepl("December-February", original)])
  missing <- original; missing[grep("archive-roni-badge", missing)] <- "Unverified index"
  testthat::expect_error(historic_preview_source_parts(missing), "badge")
  malformed <- original; malformed[grep("archive-roni-badge", malformed)] <- "[RONI unknown]{.archive-roni-badge}"
  testthat::expect_error(historic_preview_source_parts(malformed), "value")
})

testthat::test_that("preview validation refuses altered copied maps and changed source inputs", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  input <- file.path(root, "source.png"); output <- file.path(root, "map.png")
  writeLines("verified source", input); file.copy(input, output)
  plan <- data.frame(water_year = c(2002L, 2005L, 2020L), monthly_maps = 21L,
    daily_detail_maps = 4L, snow_maps = c(0L, 4L, 4L), page = paste0("wy", c(2002, 2005, 2020), ".qmd"))
  write.csv(plan, file.path(root, "preview-plan.csv"), row.names = FALSE)
  write.csv(data.frame(path = input, md5 = unname(tools::md5sum(input))), file.path(root, "source-checksums.csv"), row.names = FALSE)
  write.csv(data.frame(file = "map.png", md5 = unname(tools::md5sum(output))), file.path(root, "output-checksums.csv"), row.names = FALSE)
  testthat::expect_equal(validate_historic_monthly_site_preview(root, FALSE)$status, "PASS")
  writeLines("changed copied map", output)
  testthat::expect_error(validate_historic_monthly_site_preview(root, FALSE), "Copied")
  file.copy(input, output, overwrite = TRUE); writeLines("revised source", input)
  testthat::expect_error(validate_historic_monthly_site_preview(root, FALSE), "inputs changed")
})
