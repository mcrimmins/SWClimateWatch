source(file.path(project_root, "R/conditions-synopsis-evidence.R"))
source(file.path(project_root, "R/conditions-synopsis-template.R"))
source(file.path(project_root, "R/conditions-synopsis-seasonal-review.R"))

testthat::test_that("seasonal editorial cases pass without touching preview history", {
  output <- tempfile(); dir.create(output)
  on.exit(unlink(output, recursive = TRUE), add = TRUE)
  state <- file.path(output, "preview-state.rds")
  saveRDS(list(sentinel = "real preview"), state)
  before <- tools::md5sum(state)
  gallery <- review_conditions_synopsis_seasons(project_root, file.path(output, "seasonal-review"))
  testthat::expect_equal(nrow(gallery$summary), 24L)
  testthat::expect_equal(sum(nzchar(gallery$summary$monthly_highlight)), 9L)
  testthat::expect_true(all(gallery$summary$status == "PASS_TEMPLATE"))
  testthat::expect_identical(tools::md5sum(state), before)
  testthat::expect_true(file.exists(gallery$path))
  testthat::expect_true(all(gallery$summary$snow_interpretation %in% c("PENDING", "INACTIVE")))
  for (id in gallery$summary$id) {
    folder <- file.path(dirname(gallery$path), id)
    testthat::expect_match(paste(readLines(file.path(folder, "synopsis.md")), collapse = " "), "SYNTHETIC VALIDATION")
    testthat::expect_equal(jsonlite::read_json(file.path(folder, "evidence.json"))$data_kind, "synthetic_validation")
    testthat::expect_equal(jsonlite::read_json(file.path(folder, "draft-evidence.json"))$data_kind, "synthetic_validation")
  }
})

testthat::test_that("synthetic inputs cannot advance operational preview comparisons", {
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  e <- synopsis_seasonal_fixture(synopsis_seasonal_cases()[1, ], config)
  testthat::expect_error(build_conditions_synopsis_draft(e, track_preview = TRUE), "cannot advance preview history")
})

testthat::test_that("localized storms and opposing state temperatures get meaningful leads", {
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  cases <- synopsis_seasonal_cases()
  blocks <- function(id) {
    e <- synopsis_seasonal_fixture(cases[cases$id == id, ], config)
    Filter(function(b) b$section == "Past 7 days", synopsis_template_blocks(e, e$station_extremes))
  }
  testthat::expect_match(blocks("monsoon-localized")[[1]]$text, "1.80 inches of precipitation")
  testthat::expect_match(blocks("opposing-states")[[1]]$text, "Arizona was 5.0.*above average while New Mexico was 5.0.*below")
  missing <- paste(vapply(blocks("missing-support"), function(b) b$text, character(1)), collapse = " ")
  testthat::expect_match(missing, "unavailable")
  testthat::expect_false(grepl("quiet|snow-free|no snow|highest|lowest", missing))
  leap <- paste(vapply(blocks("leap-day"), function(b) b$text, character(1)), collapse = " ")
  testthat::expect_match(leap, "Feb 23.*29, 2024")
  testthat::expect_false(grepl("average for the weekly low", leap))
})
