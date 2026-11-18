source(file.path(project_root,"R","daily-publish.R"))
testthat::test_that("isolated daily station loading provides sibling module paths",{
  withr::local_dir(project_root)
  context<-swc_daily_publish_station_context()
  testthat::expect_true(is.environment(context))
  for(name in c("run_swc_station_beta_update","run_acis_station_explorer_update_pilot",
    "build_acis_station_explorer_prototype","validate_acis_station_monthly_detail"))
    testthat::expect_true(exists(name,envir=context,inherits=FALSE))
  testthat::expect_identical(environment(context$run_swc_station_beta_update),context)
})
