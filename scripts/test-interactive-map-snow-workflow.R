# Self-contained regression checks: synthetic fixtures, no downloads/publication.
project_root <- getwd()
for (test in c("test-interactive-map-site.R", "test-interactive-map-snow-site.R",
    "test-interactive-map-snow-current.R", "test-interactive-map-snow-workflow.R",
    "test-interactive-map-workflow.R")) {
  testthat::test_file(file.path("tests/testthat", test), stop_on_failure = TRUE)
}
