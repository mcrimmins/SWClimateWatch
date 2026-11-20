# Two independent portable releases; preserve the already published 44-year set.
historic_monthly_backfill_release_root <- function() "data/processed/historic-monthly-backfill-release"

historic_monthly_backfill_navigation <- function(site_dir = "site", expected_years = 1896:2025) {
  actual <- sort(prism_archive_page_years(file.path(site_dir, "pages/archive")))
  if (!identical(actual, as.integer(expected_years))) stop("Historic Years page set differs from the required combined archive.")
  write_prism_archive_navigation(file.path(site_dir, "pages/archive"), file.path(site_dir, "_quarto.yml"))
}

validate_historic_monthly_backfill_publication <- function(root = historic_monthly_backfill_release_root(),
    site_dir = "site", rendered = TRUE, expected_years = 1896:1981, combined_years = 1896:2025) {
  result <- validate_historic_monthly_publication(root, site_dir, rendered, expected_years)
  config <- trimws(readLines(file.path(site_dir, "_quarto.yml"), warn = FALSE))
  refs <- sprintf("- href: pages/archive/wy%d.qmd", combined_years)
  if (any(vapply(refs, function(ref) sum(config == ref), integer(1)) != 1L))
    stop("Combined Historic Years navigation is missing or duplicates a year.")
  if (rendered) {
    # Every page must carry the combined sidebar, including both release eras.
    for (year in expected_years) {
      doc <- xml2::read_html(file.path(site_dir, "_site/pages/archive", paste0("wy", year, ".html")))
      hrefs <- xml2::xml_attr(xml2::xml_find_all(doc, "//nav[@id='quarto-sidebar']//a[@href]"), "href")
      linked <- sub(".*wy([0-9]{4})[.]html.*", "\\1", hrefs[grepl("wy[0-9]{4}[.]html", hrefs)])
      if (!setequal(linked, as.character(combined_years))) stop("Rendered combined Historic Years navigation is incomplete: ", year)
    }
  }
  dir.create("data/diagnostics/historic-monthly-backfill-publication", recursive = TRUE, showWarnings = FALSE)
  result$total_archive_years <- length(combined_years)
  write.csv(result, "data/diagnostics/historic-monthly-backfill-publication/summary.csv", row.names = FALSE)
  result
}

stage_historic_monthly_backfill_release <- function(root = historic_monthly_backfill_release_root(), site_dir = "site") {
  invisible(stage_historic_monthly_release(root, site_dir, expected_years = 1896:1981))
  invisible(historic_monthly_backfill_navigation(site_dir))
  invisible(validate_historic_monthly_backfill_publication(root, site_dir, rendered = FALSE))
}
