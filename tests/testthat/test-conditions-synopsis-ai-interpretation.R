source(file.path(project_root, "R/conditions-synopsis-evidence.R"))
source(file.path(project_root, "R/conditions-synopsis-template.R"))
source(file.path(project_root, "R/conditions-synopsis-seasonal-review.R"))
source(file.path(project_root, "R/conditions-synopsis-regional-highlights.R"))
source(file.path(project_root, "R/conditions-synopsis-ai-comparison.R"))
source(file.path(project_root, "R/conditions-synopsis-ai-interpretation.R"))

synopsis_interpretive_test_packet <- function() {
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  e <- synopsis_seasonal_fixture(synopsis_seasonal_cases()[1, ], config)
  blocks <- synopsis_template_blocks(e, e$station_extremes)
  catalog <- synopsis_ai_catalog(list(blocks = blocks))
  sources <- synopsis_interpretive_sources(e, catalog)
  selection <- lapply(synopsis_ai_sections, function(section) {
    s <- Filter(function(s) s$section == section, sources)[[1L]]
    list(list(text = s$text, source_ids = list(s$id)))
  })
  list(e = e, blocks = blocks, catalog = catalog, sources = sources, selection = selection)
}

testthat::test_that("interpretive drafts are cited and distinct from ID-only selection", {
  p <- synopsis_interpretive_test_packet()
  body <- synopsis_interpretive_request(p$e, p$sources, "test-model")
  testthat::expect_equal(body$text$format$name, "climate_interpretive_draft")
  testthat::expect_match(body$instructions, "Connect the recent week")
  testthat::expect_false(body$store)
  blocks <- synopsis_interpretive_validate(p$selection, p$sources, p$e)
  testthat::expect_length(blocks, 3L)
  testthat::expect_true(all(vapply(blocks, function(b) b$needs_human_review, logical(1))))
  testthat::expect_true(all(vapply(blocks, function(b) length(b$fact_ids) > 0L, logical(1))))
  testthat::expect_false(grepl("source_path|source_md5|OPENAI_API_KEY", body$input))
})

testthat::test_that("unsupported numbers, unknown citations, markup and process claims are withheld", {
  p <- synopsis_interpretive_test_packet()
  bad <- p$selection; bad$past_7_days[[1]]$text <- "The region received 987.65 inches."
  testthat::expect_error(synopsis_interpretive_validate(bad, p$sources, p$e), "unsupported number")
  bad <- p$selection; bad$past_7_days[[1]]$source_ids <- list("invented")
  testthat::expect_error(synopsis_interpretive_validate(bad, p$sources, p$e), "source IDs")
  bad <- p$selection; bad$past_7_days[[1]]$text <- "Recent warmth drove snowmelt."
  testthat::expect_error(synopsis_interpretive_validate(bad, p$sources, p$e), "impact/process")
  bad <- p$selection; bad$past_7_days[[1]]$text <- "<script>alert(1)</script>"
  testthat::expect_error(synopsis_interpretive_validate(bad, p$sources, p$e), "plain text")
  bad <- p$selection; bad$past_7_days <- list()
  testthat::expect_error(synopsis_interpretive_validate(bad, p$sources, p$e), "omitted")
})

testthat::test_that("interpretive comparison labels scientific review and caches validated prose", {
  p <- synopsis_interpretive_test_packet(); output <- tempfile(); dir.create(output)
  on.exit(unlink(output, recursive = TRUE), add = TRUE)
  calls <- 0L
  transport <- function(body, key) {calls <<- calls + 1L; list(selection = p$selection, usage = list(input_tokens = 300, output_tokens = 200))}
  run <- function() compare_conditions_synopsis_ai(p$e, list(blocks = p$blocks), root = project_root,
    output_dir = output, enabled = TRUE, api_key = "test-secret", transport = transport, mode = "interpretive")
  first <- run()
  testthat::expect_equal(first$summary$status, "AI_WRITTEN_REVIEW")
  testthat::expect_equal(first$summary$mode, "interpretive")
  second <- run()
  testthat::expect_equal(calls, 1L)
  testthat::expect_equal(second$summary$status, "AI_CACHED")
  testthat::expect_match(paste(readLines(second$path), collapse = " "), "scientific interpretation still requires human review")
})
