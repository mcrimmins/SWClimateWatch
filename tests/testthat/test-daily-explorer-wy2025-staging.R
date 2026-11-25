wy_stage_root<-normalizePath(testthat::test_path("..",".."),winslash="/",mustWork=TRUE)
source(file.path(wy_stage_root,"R/daily-explorer-wy2025-staging.R"))
testthat::test_that("year trial rejects production destination and state before doing work",{
  withr::local_dir(wy_stage_root)
  withr::local_envvar(c(SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch/",
    SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch"))
  testthat::expect_error(wy2025_staging_guard(),"exact staging")
  testthat::expect_error(stage_wy2025_trial(directory="not-a-target"),"exact staging")
  withr::local_envvar(c(SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch-staging/"))
  testthat::expect_error(wy2025_staging_guard(),"exact staging")
  withr::local_envvar(c(SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch-staging"))
  testthat::expect_true(wy2025_staging_guard())
  testthat::expect_error(wy2025_staging_guard("s3://cales-climate-reports/climate/watch/"),"exact staging")
})
testthat::test_that("publication and daily entry points reject an explicit production destination",{
  withr::local_dir(wy_stage_root)
  withr::local_envvar(c(SWC_DAILY_WY2025_STAGING="true",SWC_DAILY_ARCHIVE_STAGING="",
    SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch-staging/",
    SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch-staging"))
  e<-new.env(parent=globalenv());sys.source("scripts/deploy-site-s3.R",envir=e)
  testthat::expect_error(e$deploy_swc_site("s3://cales-climate-reports/climate/watch/"),"exact staging")
  source("R/daily-publish.R",local=e)
  testthat::expect_error(e$run_swc_daily_publish(destination="s3://cales-climate-reports/climate/watch/",
    prism_update=function(...)stop("UPDATE MUST NOT RUN")),"exact staging")
})
