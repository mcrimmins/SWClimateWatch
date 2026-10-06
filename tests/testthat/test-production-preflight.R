source(file.path(project_root, "R", "production-preflight.R"))

testthat::test_that("production preflight is read-only and reports missing seed data", {
  root <- tempfile("swc-preflight-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  result <- swc_production_preflight(
    root = root,
    destination = "s3://cales-climate-reports/climate/watch-staging/")
  testthat::expect_false(result$ready)
  testthat::expect_true(all(c("group", "item", "status", "detail") %in%
                              names(result$checks)))
  testthat::expect_true(any(result$checks$status == "MISSING"))
  testthat::expect_identical(result$destination,
                             "s3://cales-climate-reports/climate/watch-staging/")
  testthat::expect_true(result$staging_destination)
  testthat::expect_false(file.exists(file.path(root, "site", "_site")))
})
