connected_stage_root<-normalizePath(testthat::test_path("..",".."),winslash="/",mustWork=TRUE)
source(file.path(connected_stage_root,"R/daily-explorer-connected.R"))
source(file.path(connected_stage_root,"R/daily-explorer-connected-staging.R"))
source(file.path(connected_stage_root,"R/daily-explorer-wy2026-staging.R"))
testthat::test_that("connected staging rejects production before reading or writing",{
  withr::local_dir(connected_stage_root)
  withr::local_envvar(c(SWC_DAILY_CONNECTED_STAGING="true",SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch/",
    SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch"))
  testthat::expect_error(stage_connected_trial(),"exact staging")
  testthat::expect_error(stage_wy2026_trial(),"exact staging")
  e<-new.env(parent=globalenv());sys.source("scripts/deploy-site-s3.R",envir=e)
  testthat::expect_error(e$deploy_swc_site("s3://cales-climate-reports/climate/watch/"),"exact staging")
  withr::local_envvar(c(SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch-staging/",
    SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch-staging"))
  testthat::expect_true(connected_staging_guard())
})
testthat::test_that("static adapters reference sealed scripts while data retain original relative paths",{
  html<-'<head><script src="explorer.swc-1234567890abcdef.js"></script><script src="archive-month-bridge.js"></script></head>'
  x<-connected_static_html(html,"../../../archive/wy2025/months/2025-01/","../../../../connected/months/2025-01/explorer.swc-123.js",
    "../../../../connected/connected-bridge.swc-123.js","../../../../connected/connected-frame.swc-123.css")
  testthat::expect_match(x,'<base href="../../../archive/wy2025/months/2025-01/">',fixed=TRUE)
  testthat::expect_match(x,'src="../../../../connected/months/2025-01/explorer.swc-123.js"',fixed=TRUE)
  testthat::expect_match(x,'href="../../../../connected/connected-frame.swc-123.css"',fixed=TRUE)
  testthat::expect_false(grepl("archive-month-bridge",x,fixed=TRUE))
})
testthat::test_that("static validation blocks changed assets and current cutoffs",{
  root<-tempfile();dir.create(file.path(root,"connected/current"),recursive=TRUE);withr::defer(unlink(root,recursive=TRUE))
  writeLines("test",file.path(root,"connected/current/index.html"))
  jsonlite::write_json(list(latest_cached_date="2026-11-25"),file.path(root,"daily-data.json"),auto_unbox=TRUE)
  jsonlite::write_json(list(latest="2026-11-25",months=list(list(kind="current",viewer="current/index.html",dates=list("2026-11-25")))),
    file.path(root,"connected/connected-catalog.json"),auto_unbox=TRUE)
  manifest<-list(files=list(list(path="current/index.html",md5=unname(tools::md5sum(file.path(root,"connected/current/index.html"))))),
    dependencies=list(list(path="daily-data.json",md5=unname(tools::md5sum(file.path(root,"daily-data.json"))))))
  jsonlite::write_json(manifest,file.path(root,"connected/connected-release.json"),auto_unbox=TRUE)
  testthat::expect_identical(validate_connected_static(root)$status,"PASS")
  writeLines("changed",file.path(root,"connected/current/index.html"))
  testthat::expect_error(validate_connected_static(root),"differs")
})
