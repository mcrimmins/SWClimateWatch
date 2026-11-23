testthat::test_file("tests/testthat/test-nws-hazards-daily.R",stop_on_failure=TRUE)
source("R/nws-hazards-daily.R")
source("scripts/test-nws-hazards-staging.R")
withr::with_envvar(c(SWC_NWS_HAZARDS="true",SWC_STORM_REPORTS="true",SWC_NWS_HAZARDS_STAGING="false",
  SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch-staging/",
  SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch-staging"), {
  fixture<-"data/diagnostics/nws-hazards-staging-test/source"
  root<-"data/diagnostics/nws-hazards-daily-test"
  original<-jsonlite::read_json(file.path(fixture,"daily-data.json"))
  result<-prepare_nws_hazards_daily(fixture,download=FALSE,report_dir=root,state_dir=file.path(root,"state"))
  stopifnot(result$status%in%c("READY","PARTIAL"),result$requests==0L)
  after<-jsonlite::read_json(file.path(fixture,"daily-data.json"))
  stopifnot(identical(after,original))
  rendered<-file.path(root,"rendered/daily-explorer")
  copy_fixture<-function(){for(file in list.files(fixture,recursive=TRUE)) {
    dest<-file.path(rendered,file);dir.create(dirname(dest),recursive=TRUE,showWarnings=FALSE)
    stopifnot(file.copy(file.path(fixture,file),dest,overwrite=TRUE))
  }}
  copy_fixture();validate_nws_hazards_daily(file.path(root,"rendered"),fixture)
  # Age otherwise valid archives to prove stale notices survive rendering.
  stale_fetch<-function(...,download=TRUE) {
    x<-nws_hazards_request(...,download=FALSE)
    x$meta$fetched_utc<-"2000-01-01T00:00:00Z";x
  }
  result<-prepare_nws_hazards_daily(fixture,download=FALSE,report_dir=root,
    state_dir=file.path(root,"state"),fetcher=stale_fetch)
  stopifnot(result$status=="PARTIAL",result$stale>0L,result$requests==0L)
  copy_fixture();validate_nws_hazards_daily(file.path(root,"rendered"),fixture)
  result<-suppressWarnings(prepare_nws_hazards_daily(fixture,download=FALSE,
    report_dir=root,state_dir=file.path(root,"state"),fetcher=function(...)stop("unavailable fixture")))
  stopifnot(result$status=="UNAVAILABLE",result$requests==0L,result$retry_pending>0L,
    !isTRUE(jsonlite::read_json(file.path(fixture,"daily-data.json"))$nws_hazards_enabled))
  fallback_html<-paste(readLines(file.path(fixture,"index.html")),collapse="\n")
  stopifnot(!grepl("hazards-explorer",fallback_html,fixed=TRUE),!grepl('id="show-hazard-row"',fallback_html,fixed=TRUE))
  copy_fixture();validate_nws_hazards_daily(file.path(root,"rendered"),fixture)
})
message("PASS: cache-only daily staging, preservation, rendered verification and missing-source unavailable fallback. Nothing uploaded.")
