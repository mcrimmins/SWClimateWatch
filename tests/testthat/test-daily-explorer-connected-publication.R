connected_pub_root<-normalizePath(testthat::test_path("..",".."),winslash="/",mustWork=TRUE)
source(file.path(connected_pub_root,"R/daily-explorer-connected-publication.R"))
testthat::test_that("operational guard accepts only matching dedicated destination/state pairs",{
  withr::local_envvar(c(SWC_DAILY_CONNECTED_STAGING="",SWC_DAILY_WY2025_STAGING="",SWC_DAILY_ARCHIVE_STAGING="",
    SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch/",SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch"))
  testthat::expect_true(connected_publication_guard())
  testthat::expect_error(connected_publication_guard("s3://cales-climate-reports/climate/watch-staging/"),"matching dedicated")
  testthat::expect_error(connected_publication_guard("s3://elsewhere/"),"matching dedicated")
  withr::local_envvar(c(SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch-staging/",SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch-staging"))
  testthat::expect_true(connected_publication_guard())
  withr::local_envvar(c(SWC_DAILY_CONNECTED_STAGING="true"))
  testthat::expect_error(stage_connected_publication(),"Clear archive trial")
})
testthat::test_that("standard page switches both links and settles the outer frame idempotently",{
  text<-paste(readLines(file.path(connected_pub_root,"site/pages/daily-explorer.qmd")),collapse="\n")
  changed<-connected_publication_page(text)
  testthat::expect_match(changed,"../daily-explorer/connected/index.html?embedded=1",fixed=TRUE)
  testthat::expect_false(grepl("../daily-explorer/index.html",changed,fixed=TRUE))
  testthat::expect_match(changed,"clearTimeout(pending)",fixed=TRUE)
  testthat::expect_identical(connected_publication_page(changed),changed)
  restored<-connected_publication_page(changed,enabled=FALSE)
  testthat::expect_match(restored,"../daily-explorer/index.html?embedded=1",fixed=TRUE)
  testthat::expect_false(grepl("../daily-explorer/connected/index.html",restored,fixed=TRUE))
})
testthat::test_that("full-screen entry preserves existing assets and saved selections",{
  html<-'<head><script src="explorer.swc-123.js"></script></head>'
  result<-connected_publication_redirect(html)
  testthat::expect_match(result,"window.top === window",fixed=TRUE)
  testthat::expect_match(result,"target.search = location.search",fixed=TRUE)
  testthat::expect_match(result,"explorer.swc-123.js",fixed=TRUE)
  testthat::expect_identical(connected_publication_redirect(result),result)
})
testthat::test_that("cached staging prepares redirect before hazards freeze the current HTML",{
  root<-tempfile();dir.create(file.path(root,"site/daily-explorer"),recursive=TRUE);withr::defer(unlink(root,recursive=TRUE))
  withr::local_dir(root)
  withr::local_envvar(c(SWC_DAILY_CONNECTED="true",SWC_NWS_HAZARDS="true",SWC_STORM_REPORTS="true",
    SWC_DAILY_CONNECTED_STAGING="",SWC_DAILY_WY2025_STAGING="",SWC_DAILY_ARCHIVE_STAGING="",SWC_NWS_HAZARDS_STAGING="",SWC_STORM_REPORTS_STAGING="",
    SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch/",SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch"))
  e<-new.env(parent=globalenv());sys.source(file.path(connected_pub_root,"R/daily-explorer-connected-publication.R"),envir=e)
  e$source<-function(...)invisible(NULL)
  e$nws_hazards_daily_guard<-e$storm_reports_daily_guard<-function(...)TRUE
  e$stage_daily_explorer_site<-function(...){writeLines("<head></head>","site/daily-explorer/index.html");list(status="STAGED")}
  e$prepare_storm_reports_daily<-function(...) {
    p<-"site/daily-explorer/index.html";writeLines(sub("</head>","<!-- reports --></head>",paste(readLines(p),collapse="\n"),fixed=TRUE),p)
  }
  e$prepare_nws_hazards_daily<-function(...) {
    text<-paste(readLines("site/daily-explorer/index.html"),collapse="\n")
    testthat::expect_match(text,"swc-connected-entry",fixed=TRUE)
    testthat::expect_match(text,"<!-- reports -->",fixed=TRUE)
    e$sealed<-tools::md5sum("site/daily-explorer/index.html")
  }
  sys.source(file.path(connected_pub_root,"scripts/stage-daily-explorer.R"),envir=e)
  testthat::expect_identical(e$sealed,tools::md5sum("site/daily-explorer/index.html"))
})
testthat::test_that("late connected publication never modifies the already sealed current index",{
  root<-tempfile();dir.create(file.path(root,"site/daily-explorer"),recursive=TRUE);dir.create(file.path(root,"site/pages"))
  withr::defer(unlink(root,recursive=TRUE));withr::local_dir(root)
  withr::local_envvar(c(SWC_DAILY_CONNECTED_STAGING="",SWC_DAILY_WY2025_STAGING="",SWC_DAILY_ARCHIVE_STAGING="",
    SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch/",SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch"))
  writeLines("<head><!-- sealed hazard/report viewer --></head>","site/daily-explorer/index.html")
  before<-tools::md5sum("site/daily-explorer/index.html")
  file.copy(file.path(connected_pub_root,"site/pages/daily-explorer.qmd"),"site/pages/daily-explorer.qmd")
  e<-new.env(parent=globalenv());sys.source(file.path(connected_pub_root,"R/daily-explorer-connected-publication.R"),envir=e)
  e$source<-function(...)invisible(NULL)
  e$validate_wy2025_explorer_navigation<-e$validate_wy2026_explorer_navigation<-function(...)TRUE
  e$build_connected_static<-function(...)TRUE
  e$july_pilot_copy<-function(from,to){dir.create(dirname(to),recursive=TRUE,showWarnings=FALSE);stopifnot(file.copy(from,to,overwrite=TRUE))}
  for(year in c(2025,2026)) {
    d<-paste0("data/diagnostics/daily-explorer-wy",year,"-release");dir.create(d,recursive=TRUE)
    jsonlite::write_json(list(files=list()),file.path(d,paste0("wy",year,"-release.json")),auto_unbox=TRUE)
  }
  e$stage_connected_publication()
  testthat::expect_identical(before,tools::md5sum("site/daily-explorer/index.html"))
})
testthat::test_that("hazard snapshot seals the redirect in its regenerated outer HTML",{
  root<-tempfile();dir.create(root);withr::defer(unlink(root,recursive=TRUE));withr::local_dir(root)
  withr::local_envvar(c(SWC_DAILY_CONNECTED="true",SWC_DAILY_CONNECTED_STAGING="",SWC_DAILY_WY2025_STAGING="",SWC_DAILY_ARCHIVE_STAGING="",
    SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch/",SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch"))
  dir.create("current/reports",recursive=TRUE)
  jsonlite::write_json(list(days=list(list(date="2026-11-25"))),"current/daily-data.json",auto_unbox=TRUE)
  jsonlite::write_json(list(days=list(list(status="EMPTY",path="reports/2026-11-25.json",date="2026-11-25"))),"current/storm-reports-manifest.json",auto_unbox=TRUE)
  jsonlite::write_json(list(reports=list()),"current/reports/2026-11-25.json",auto_unbox=TRUE)
  e<-new.env(parent=globalenv())
  for(f in c("R/daily-explorer-connected-publication.R","R/site-cache.R","R/nws-hazards-staging.R"))sys.source(file.path(connected_pub_root,f),envir=e)
  e$source<-function(...)invisible(NULL)
  e$validate_storm_reports_publication<-function(...)TRUE
  e$build_nws_hazards_explorer<-function(source_dir,output_dir,...) {
    dir.create(file.path(output_dir,"hazards/cases"),recursive=TRUE)
    dir.create(file.path(output_dir,"reports"))
    file.copy(file.path(source_dir,"storm-reports-manifest.json"),output_dir)
    file.copy(file.path(source_dir,"reports/2026-11-25.json"),file.path(output_dir,"reports"))
    for(d in c("images","hazards/images")) {
      dir.create(file.path(output_dir,d),recursive=TRUE)
      writeLines("fixture image",file.path(output_dir,d,"marker.png"))
    }
    # Reproduce the real assembler discarding the earlier source HTML.
    writeLines('<head><script src="explorer.js"></script><link href="explorer.css"></head>',file.path(output_dir,"index.html"))
    writeLines("// fixture",file.path(output_dir,"explorer.js"));writeLines("body{}",file.path(output_dir,"explorer.css"))
    writeLines('<head><script src="hazards.js"></script></head>',file.path(output_dir,"hazards/index.html"))
    writeLines("// widget",file.path(output_dir,"hazards/hazards.js"))
    for(p in c("leaflet-package-LICENSE","hazards/leaflet-package-LICENSE","hazards/workload.csv","hazards/view-workload.csv","hazard-timeline.json"))writeLines("fixture",file.path(output_dir,p))
    jsonlite::write_json(list(events=list(),geometry_bundles=list()),file.path(output_dir,"hazards/cases/explorer.json"),auto_unbox=TRUE)
    jsonlite::write_json(list(cases=list()),file.path(output_dir,"hazards/catalog.json"),auto_unbox=TRUE)
  }
  e$validate_nws_hazards_publication<-function(directory) {
    r<-jsonlite::read_json(file.path(directory,"hazard-publication.json"))
    for(f in r$files) {
      testthat::expect_identical(f$md5,unname(tools::md5sum(file.path(directory,f$path))))
      testthat::expect_equal(f$bytes,file.info(file.path(directory,f$path))$size)
    }
    testthat::expect_match(paste(readLines(file.path(directory,"index.html")),collapse="\n"),"swc-connected-entry",fixed=TRUE)
    TRUE
  }
  e$stage_nws_hazards_snapshot("current","work",request_fun=function(...)stop("NO HTTP"))
  testthat::expect_identical(unname(tools::md5sum("work/index.html")),unname(tools::md5sum("current/index.html")))
})
testthat::test_that("daily and deploy guards reject wrong states before any work",{
  withr::local_dir(connected_pub_root)
  withr::local_envvar(c(SWC_DAILY_CONNECTED="true",SWC_DAILY_CONNECTED_STAGING="",SWC_DAILY_WY2025_STAGING="",SWC_DAILY_ARCHIVE_STAGING="",
    SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch-staging"))
  e<-new.env(parent=globalenv());sys.source("scripts/deploy-site-s3.R",envir=e)
  testthat::expect_error(e$deploy_swc_site("s3://cales-climate-reports/climate/watch/"),"matching dedicated")
  source("R/daily-publish.R",local=e)
  testthat::expect_error(e$run_swc_daily_publish(destination="s3://cales-climate-reports/climate/watch/",prism_update=function(...)stop("NO WORK")),"matching dedicated")
})
