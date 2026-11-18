source(file.path(project_root, "scripts/deploy-site-s3.R"), local = TRUE)

testthat::test_that("Snow image reconciliation precedes every image inventory", {
  root <- tempfile("snow-order-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  image <- file.path(root, "snow.png"); writeLines("old image bytes", image)
  prepared <- FALSE; hashes <- list(); calls <- character()
  run <- function(command, args, label) {
    script <- args[[1L]]; calls <<- c(calls, script)
    reconcile <- function() {writeLines("revised image bytes", image); prepared <<- TRUE}
    if (grepl("prepare-interactive-map-snow-current", script)) reconcile()
    if (grepl("build-map-product-site|stage-conditions-synopsis|stage-current-map-groups", script))
      hashes[[script]] <<- unname(tools::md5sum(image))
    # The late viewer also checks/reconciles Snow; it must find it already ready.
    if (grepl("stage-cached-interactive-map-site", script) && !prepared) reconcile()
  }
  swc_deploy_stage_cached_sources("Rscript", "s3://fixture/watch-staging/", TRUE, run)
  testthat::expect_true(prepared)
  testthat::expect_length(hashes, 3L)
  testthat::expect_true(all(unlist(hashes) == unname(tools::md5sum(image))))
  testthat::expect_match(calls[[1L]], "prepare-interactive-map-snow-current", fixed = TRUE)
})

testthat::test_that("Snow preparation failures stop all downstream staging", {
  calls <- character()
  run <- function(command, args, label) {calls <<- c(calls, args[[1L]]); stop("quality gate held")}
  testthat::expect_error(swc_deploy_stage_cached_sources("Rscript", "s3://fixture/watch-staging/", TRUE, run), "quality gate")
  testthat::expect_length(calls, 1L)
  calls <- character()
  swc_deploy_stage_cached_sources("Rscript", "s3://fixture/watch-staging/", FALSE,
    function(command, args, label) calls <<- c(calls, args[[1L]]))
  testthat::expect_false(any(grepl("interactive-map", calls)))
})
