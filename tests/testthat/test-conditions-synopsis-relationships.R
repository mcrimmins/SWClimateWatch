source(file.path(project_root, "R/conditions-synopsis-evidence.R"))
source(file.path(project_root, "R/conditions-synopsis-template.R"))
source(file.path(project_root, "R/conditions-synopsis-seasonal-review.R"))
source(file.path(project_root, "R/conditions-synopsis-ai-comparison.R"))
source(file.path(project_root, "R/conditions-synopsis-relationships.R"))

synopsis_relationship_test_evidence <- function() {
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  e <- synopsis_seasonal_fixture(synopsis_seasonal_cases()[1L, ], config)
  e$recent$facts$value[e$recent$facts$metric == "mean"] <- .8
  e$facts$value[e$facts$product == "pcpn_percentile_30day" & e$facts$metric == "area_above_upper_percentile"] <- 70
  e$facts$value[e$facts$product == "tmean_departure_30day" & e$facts$region == "AZ"] <- 1
  e$facts$value[e$facts$product == "tmean_departure_30day" & e$facts$region == "NM"] <- 4
  e
}

testthat::test_that("R establishes nested rainfall and anomaly relationships with explicit scopes", {
  e <- synopsis_relationship_test_evidence(); r <- synopsis_relationships(e)
  testthat::expect_equal(vapply(r, function(x) x$id, character(1)), c("recent_rain_wet_month", "monthly_temperature_contrast"))
  testthat::expect_match(r[[1L]]$allowed_meaning, "do not show that the month was already wet")
  testthat::expect_match(r[[2L]]$allowed_meaning, "not absolute temperatures")
  testthat::expect_true(all(vapply(r, function(x) length(x$evidence_ids) >= 2L, logical(1))))
  e$facts$value[e$facts$product == "pcpn_water_year_percentile" & e$facts$metric == "area_below_lower_percentile"] <- 70
  r <- synopsis_relationships(e)
  testthat::expect_equal(r[[1L]]$id, "recent_rain_longer_dryness")
  testthat::expect_match(r[[1L]]$allowed_meaning, "does not establish improvement")
  e$recent$facts$status <- "LOW_COVERAGE"
  testthat::expect_false(any(vapply(synopsis_relationships(e), function(x) x$category == "precipitation", logical(1))))
  e$facts$reference[e$facts$product == "tmean_departure_30day" & e$facts$region == "NM"] <- "different baseline"
  testthat::expect_false(any(vapply(synopsis_relationships(e), function(x) x$id == "monthly_temperature_contrast", logical(1))))
})

testthat::test_that("relationship writing keeps numbers in fixed anchors", {
  e <- synopsis_relationship_test_evidence(); r <- synopsis_relationships(e)
  s <- list(sentences = list(
    list(relationship_id = r[[1L]]$id, interpretation = "Recent rainfall fits within the wetter monthly picture."),
    list(relationship_id = r[[2L]]$id, interpretation = "New Mexico has the larger monthly departure relative to its own normal.")))
  testthat::expect_match(synopsis_stands_out_validate(s, r), "wetter monthly picture")
  bad <- s; bad$sentences[[1L]]$interpretation <- "Rainfall averaged 3 inches."
  testthat::expect_error(synopsis_stands_out_validate(bad, r), "qualitative")
  bad <- s; bad$sentences[[2L]]$interpretation <- "New Mexico was warmer throughout the water year."
  testthat::expect_error(synopsis_stands_out_validate(bad, r), "scope")
  bad <- s; bad$sentences[[1L]]$interpretation <- "Rainfall restored runoff."
  testthat::expect_error(synopsis_stands_out_validate(bad, r), "unsupported")
  bad <- s; bad$sentences[[1L]]$relationship_id <- "invented"
  testthat::expect_error(synopsis_stands_out_validate(bad, r), "IDs/order")
})

testthat::test_that("local paragraph preview preserves template and uses a bounded cache", {
  e <- synopsis_relationship_test_evidence(); blocks <- synopsis_template_blocks(e, e$station_extremes)
  before <- digest::digest(blocks); root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  calls <- 0L
  transport <- function(...) {
    calls <<- calls + 1L
    list(selection = list(sentences = list(
      list(relationship_id = "recent_rain_wet_month", interpretation = "Recent rainfall fits within the wetter monthly picture."),
      list(relationship_id = "monthly_temperature_contrast", interpretation = "New Mexico has the larger monthly departure relative to its own normal."))), usage = list(input_tokens = 500, output_tokens = 80))
  }
  run <- function(enabled) build_synopsis_stands_out_review(e, list(blocks = blocks), output_dir = root,
    enabled = enabled, api_key = "test-secret", transport = transport)
  offline <- run(FALSE)
  testthat::expect_equal(calls, 0L); testthat::expect_equal(offline$summary$status, "RULE_BASED_PREVIEW")
  first <- run(TRUE); second <- run(TRUE)
  testthat::expect_equal(calls, 1L); testthat::expect_equal(second$summary$status, "AI_CACHED_REVIEW")
  testthat::expect_identical(digest::digest(blocks), before)
  testthat::expect_match(paste(readLines(first$path), collapse = " "), "human review required")
  testthat::expect_false(grepl("test-secret|source_path|source_md5", paste(readLines(file.path(root, "request-preview.json")), collapse = " ")))
})
