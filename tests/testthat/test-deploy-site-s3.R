source(file.path(project_root, "scripts", "deploy-site-s3.R"), local = TRUE)

testthat::test_that("deployment requires an explicit dedicated S3 prefix", {
  destination <- "s3://cales-climate-reports/climate/sw-climate-watch/"
  testthat::expect_equal(swc_deploy_destination(destination), destination)
  testthat::expect_error(swc_deploy_destination("s3://cales-climate-reports/"), "dedicated site prefix")
  testthat::expect_error(swc_deploy_destination("s3://cales-climate-reports/climate/"), "dedicated site prefix")
  testthat::expect_error(swc_deploy_destination("s3://cales-climate-reports/climate//"), "dedicated site prefix")
  testthat::expect_error(swc_deploy_destination("s3://cales-climate-reports/climate/../"), "unsafe prefix")
})

testthat::test_that("S3 sync previews by default and deletion is opt-in", {
  destination <- "s3://cales-climate-reports/climate/sw-climate-watch/"
  preview <- swc_deploy_sync_args("C:/tmp/site/_site", destination, "us-west-2", TRUE, FALSE)
  testthat::expect_true("--dryrun" %in% preview)
  testthat::expect_false("--delete" %in% preview)
  testthat::expect_true("--region" %in% preview)
  mirror_preview <- swc_deploy_sync_args("C:/tmp/site/_site", destination, "us-west-2", TRUE, TRUE)
  testthat::expect_true(all(c("--dryrun", "--delete") %in% mirror_preview))
  live <- swc_deploy_sync_args("C:/tmp/site/_site", destination, "us-west-2", FALSE, FALSE)
  testthat::expect_false("--dryrun" %in% live)
  testthat::expect_false("--delete" %in% live)
})

testthat::test_that("live publish entry point uses the dedicated confirmed prefix", {
  path <- file.path(project_root, "scripts", "publish-site-s3.R")
  testthat::expect_silent(parse(file = path))
  script <- paste(readLines(path, warn = FALSE), collapse = "\n")
  testthat::expect_match(
    script, "swc_site_destination <- swc_daily_publish_destination()", fixed = TRUE
  )
  testthat::expect_match(script, "destination = swc_site_destination", fixed = TRUE)
  testthat::expect_match(script, "region = \"us-west-2\"", fixed = TRUE)
  testthat::expect_match(script, "dry_run = FALSE", fixed = TRUE)
  testthat::expect_match(script, "delete = FALSE", fixed = TRUE)
  testthat::expect_match(script, "render = TRUE", fixed = TRUE)
})


testthat::test_that("site renders reconcile monthly pages from cached local releases first", {
  script<-readLines(file.path(project_root,"scripts/deploy-site-s3.R"))
  stage<-grep('swc_deploy_run(rscript, "scripts/stage-cached-prism-monthly-site.R"',script,fixed=TRUE)
  render<-grep('swc_deploy_run(quarto, c("render", "site")',script,fixed=TRUE)
  testthat::expect_length(stage,1L)
  testthat::expect_true(stage<render)
  helper<-paste(readLines(file.path(project_root,"scripts/stage-cached-prism-monthly-site.R")),collapse="\n")
  testthat::expect_false(grepl("run_prism_monthly_update(",helper,fixed=TRUE))
})
