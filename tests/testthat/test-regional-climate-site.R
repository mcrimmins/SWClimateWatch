source(file.path(project_root, "R/regional-seasonal-reference.R"))
source(file.path(project_root, "R/regional-climate-site.R"))

testthat::test_that("regional reference page has three topic tabs and collapsed explanations", {
  jobs <- regional_climate_site_jobs("annual", "seasonal")
  text <- regional_climate_page_text(jobs)
  testthat::expect_equal(nrow(jobs), 10L)
  testthat::expect_false(anyDuplicated(jobs$file) > 0L)
  testthat::expect_equal(sum(grepl("^## ", text)), 3L)
  testthat::expect_equal(sum(grepl("data-reference-map=", text, fixed = TRUE)), 10L)
  testthat::expect_equal(sum(grepl("Open full-resolution PNG", text, fixed = TRUE)), 10L)
  testthat::expect_true(any(grepl('<details class="climate-reference-methods">', text, fixed = TRUE)))
  testthat::expect_false(any(grepl("<details[^>]* open", text)))
  testthat::expect_true(any(grepl("Winter (Jan-Mar)", text, fixed = TRUE)))
  testthat::expect_true(any(grepl("mean daily maximum", text, fixed = TRUE)))
})

testthat::test_that('complete topic layout includes all 39 references and unique controls', {
  jobs <- regional_climate_site_jobs('annual','seasonal','shares','daily')
  text <- regional_climate_page_text(jobs)
  testthat::expect_equal(nrow(jobs),39L)
  testthat::expect_equal(anyDuplicated(jobs$id),0L)
  testthat::expect_equal(anyDuplicated(jobs$file),0L)
  testthat::expect_equal(sum(grepl('data-reference-map=',text,fixed=TRUE)),39L)
  testthat::expect_equal(sum(grepl('data-climate-group=',text,fixed=TRUE)),3L)
  testthat::expect_true(any(grepl('## Seasonal comparison',text,fixed=TRUE)))
  testthat::expect_true(any(grepl('id="climate-period"',text,fixed=TRUE)))
  testthat::expect_true(any(grepl('id="climate-comparison-metric"',text,fixed=TRUE)))
  doc <- xml2::read_html(paste(text,collapse='\n'))
  ids <- xml2::xml_attr(xml2::xml_find_all(doc,'//*[@id]'),'id')
  testthat::expect_equal(anyDuplicated(ids),0L)
})

testthat::test_that("regional navigation is idempotent and stays outside generated groups", {
  path <- tempfile(); on.exit(unlink(path), add = TRUE)
  writeLines(c("project:", "  resources:", "    - maps/generated/prism/monthly/**",
    "website:", "  sidebar:", "    contents:", "      # BEGIN GENERATED HISTORIC YEARS",
    "      - section: Historic Years", "        contents:", "          - href: pages/archive/wy2025.qmd",
    "      # END GENERATED HISTORIC YEARS", "      - href: pages/methods.qmd", "        text: About"), path)
  regional_climate_navigation(path)
  first <- readLines(path); regional_climate_navigation(path)
  testthat::expect_identical(readLines(path), first)
  testthat::expect_equal(sum(trimws(first) == "- href: pages/climate-of-region.qmd"), 1L)
  testthat::expect_true(grep("END GENERATED HISTORIC YEARS", first) < grep("href: pages/climate-of-region", first))
  testthat::expect_true(grep("href: pages/climate-of-region", first) < grep("href: pages/methods", first))
  testthat::expect_true("maps/generated/prism/regional-reference/**" %in% yaml::read_yaml(path)$project$resources)
})

testthat::test_that("reference page validator catches missing maps and broken links", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  dir.create(file.path(root, "pages")); maps <- file.path(root, "maps/generated/prism/regional-reference/1991-2020")
  dir.create(maps, recursive = TRUE)
  jobs <- regional_climate_site_jobs("annual", "seasonal")
  for (file in jobs$file) writeLines("fixture", file.path(maps, file))
  jobs$md5 <- unname(tools::md5sum(file.path(maps, jobs$file)))
  jsonlite::write_json(list(schema_version = 1L, start_year = 1991L, end_year = 2020L,
    required_complete_periods = 30L, products = jobs[c("id", "period", "variable", "file", "md5")]),
    file.path(maps, "manifest.json"), auto_unbox = TRUE, dataframe = "rows")
  page <- file.path(root, "pages/climate-of-region.qmd")
  writeLines(regional_climate_page_text(jobs), page)
  writeLines("      - href: pages/climate-of-region.qmd", file.path(root, "_quarto.yml"))
  report <- file.path(root, "reports")
  result <- validate_regional_climate_reference_site(root, rendered = FALSE, report_dir = report)
  testthat::expect_equal(result$status, "PASS")
  testthat::expect_equal(result$maps, 10L)
  writeLines("changed", file.path(maps, jobs$file[1]))
  testthat::expect_error(validate_regional_climate_reference_site(root, rendered = FALSE, report_dir = report), "checks failed")
})
