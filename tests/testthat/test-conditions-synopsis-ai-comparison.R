source(file.path(project_root, "R/conditions-synopsis-evidence.R"))
source(file.path(project_root, "R/conditions-synopsis-template.R"))
source(file.path(project_root, "R/conditions-synopsis-seasonal-review.R"))
source(file.path(project_root, "R/conditions-synopsis-regional-highlights.R"))
source(file.path(project_root, "R/conditions-synopsis-ai-comparison.R"))

synopsis_ai_test_packet <- function() {
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  cases <- synopsis_seasonal_cases()
  e <- synopsis_seasonal_fixture(cases[cases$id == "competing-highlights", ], config)
  blocks <- synopsis_template_blocks(e, e$station_extremes, regional_candidates = synopsis_regional_candidates(e))
  list(evidence = e, draft = list(blocks = blocks))
}

synopsis_ai_test_selection <- function(catalog) {
  lapply(synopsis_ai_sections, function(section) {
    x <- Filter(function(b) b$section == section, catalog)
    topics <- vapply(x, function(b) b$topic, character(1))
    unname(as.list(head(vapply(x[!duplicated(topics)], function(b) b$id, character(1)), 2L)))
  })
}

testthat::test_that("AI selection accepts only approved, correctly grouped statement IDs", {
  p <- synopsis_ai_test_packet(); catalog <- synopsis_ai_catalog(p$draft)
  selection <- synopsis_ai_test_selection(catalog)
  blocks <- synopsis_ai_validate(selection, catalog)
  testthat::expect_true(all(vapply(blocks, function(b) b$text %in% vapply(catalog, function(c) c$text, character(1)), logical(1))))
  invalid <- selection; invalid$past_30_days <- list("fabricated")
  testthat::expect_error(synopsis_ai_validate(invalid, catalog))
  invalid <- selection; invalid$past_7_days <- selection$past_30_days
  testthat::expect_error(synopsis_ai_validate(invalid, catalog), "wrong-section")
  invalid <- selection; invalid$past_30_days <- rep(selection$past_30_days[1], 3)
  testthat::expect_error(synopsis_ai_validate(invalid, catalog), "Repeated")
  invalid <- selection; invalid$extra <- "unsupported text"
  testthat::expect_error(synopsis_ai_validate(invalid, catalog), "Unexpected")
  invalid <- selection; invalid$past_30_days <- list()
  testthat::expect_error(synopsis_ai_validate(invalid, catalog), "omitted")
})

testthat::test_that("opt-in, cache reuse and failures retain a safe local comparison", {
  p <- synopsis_ai_test_packet(); root <- tempfile(); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  calls <- 0L
  mock <- function(body, key) {
    calls <<- calls + 1L
    testthat::expect_false(body$store)
    testthat::expect_equal(body$text$format$type, "json_schema")
    list(selection = synopsis_ai_test_selection(synopsis_ai_catalog(p$draft)),
      usage = list(input_tokens = 100L, output_tokens = 30L), returned_model = "mock-model")
  }
  run <- function(...) compare_conditions_synopsis_ai(p$evidence, p$draft, output_dir = root, transport = mock, ...)
  offline <- run(enabled = FALSE, api_key = "test-secret")
  testthat::expect_equal(calls, 0L); testthat::expect_equal(offline$summary$status, "NOT_RUN_DISABLED")
  missing <- run(enabled = TRUE, api_key = "")
  testthat::expect_equal(calls, 0L); testthat::expect_equal(missing$summary$status, "NOT_RUN_NO_KEY")
  first <- run(enabled = TRUE, api_key = "test-secret")
  testthat::expect_equal(first$summary$status, "AI_SELECTED"); testthat::expect_equal(calls, 1L)
  cached <- run(enabled = TRUE, api_key = "test-secret")
  testthat::expect_equal(cached$summary$status, "AI_CACHED"); testthat::expect_equal(calls, 1L)
  testthat::expect_equal(cached$summary$requests, 0L)
  testthat::expect_false(grepl("test-secret", paste(readLines(file.path(root, "request-preview.json")), collapse = "")))
  # A changed model cannot silently reuse the prior response.
  changed <- run(enabled = TRUE, api_key = "test-secret", model = "different-model")
  testthat::expect_equal(changed$summary$status, "AI_SELECTED"); testthat::expect_equal(calls, 2L)
  p$draft$blocks[[1L]]$text <- paste0(p$draft$blocks[[1L]]$text, " Updated approved context.")
  revised <- run(enabled = TRUE, api_key = "test-secret", model = "different-model")
  testthat::expect_equal(revised$summary$status, "AI_SELECTED"); testthat::expect_equal(calls, 3L)
  bad <- compare_conditions_synopsis_ai(p$evidence, p$draft, output_dir = file.path(root, "bad"), enabled = TRUE,
    api_key = "test-secret", transport = function(...) list(selection = list(fake = "new facts")))
  testthat::expect_equal(bad$summary$status, "TEMPLATE_FALLBACK")
  testthat::expect_identical(bad$blocks, p$draft$blocks)
  testthat::expect_false(file.exists(file.path(root, "bad/selection-cache.rds")))
  failed <- compare_conditions_synopsis_ai(p$evidence, p$draft, output_dir = file.path(root, "failed"), enabled = TRUE,
    api_key = "test-secret", transport = function(...) stop("Simulated unavailable API"))
  testthat::expect_equal(failed$summary$status, "TEMPLATE_FALLBACK")
  testthat::expect_equal(failed$summary$requests, 1L)
})
