hazard_daily_root<-normalizePath(testthat::test_path("..",".."),winslash="/",mustWork=TRUE)
source(file.path(hazard_daily_root,"R/nws-hazards-daily.R"))

testthat::test_that("daily hazards require opt-in, matching release settings and reports", {
  withr::local_dir(hazard_daily_root)
  withr::local_envvar(c(SWC_NWS_HAZARDS="false"))
  testthat::expect_identical(prepare_nws_hazards_daily()$status,"DISABLED")
  withr::local_envvar(c(SWC_NWS_HAZARDS="true",SWC_STORM_REPORTS="true",SWC_NWS_HAZARDS_STAGING="false",
    SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch-staging/",
    SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch-staging"))
  testthat::expect_silent(nws_hazards_daily_guard())
  withr::local_envvar(c(SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch/"))
  testthat::expect_error(nws_hazards_daily_guard(),"matching destination/state")
  withr::local_envvar(c(SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch"))
  testthat::expect_silent(nws_hazards_daily_guard())
  withr::local_envvar(c(SWC_STORM_REPORTS="false"))
  testthat::expect_error(nws_hazards_daily_guard(),"require SWC_STORM_REPORTS")
})

testthat::test_that("recent refreshes, cache-only reuse, request cap and failed retries retain verified cache", {
  withr::local_dir(hazard_daily_root)
  root<-tempfile("hazard-daily-",tmpdir="data/diagnostics");dir.create(root)
  cache<-new.env(parent=emptyenv());calls<-0L;fail<-FALSE
  fetch<-function(start,end=NULL,at=NULL,simple=FALSE,refresh=FALSE,download=TRUE) {
    key<-paste(start,end,at,collapse="/")
    if(!download) {if(!exists(key,cache,inherits=FALSE))stop("missing");return(cache[[key]])}
    calls<<-calls+1L;if(fail)stop("provider unavailable")
    value<-list(meta=list(fetched_utc="2026-11-23T12:00:00Z"),revision=calls)
    cache[[key]]<-value;value
  }
  manager<-function(download=TRUE,cap=6L)nws_hazards_request_manager("2026-11-23",download,
    max_requests=cap,state_dir=root,fetcher=fetch,now=as.POSIXct("2026-11-23 13:00:00",tz="UTC"))
  first<-manager();a<-first$request("2026-11-01","2026-11-23");first$save()
  testthat::expect_equal(first$stats()$requests,1)
  offline<-manager(FALSE);testthat::expect_identical(offline$request("2026-11-01","2026-11-23"),a)
  testthat::expect_equal(offline$stats()$requests,0)
  revise<-manager();b<-revise$request("2026-11-01","2026-11-23")
  testthat::expect_gt(b$revision,a$revision)
  fail<-TRUE
  broken<-manager();testthat::expect_identical(broken$request("2026-11-01","2026-11-23"),b)
  broken$save();testthat::expect_equal(broken$stats()$stale,1)
  testthat::expect_equal(broken$stats()$pending,1)
  testthat::expect_match(broken$note(),"stale")
  retry<-manager(FALSE);retry$request("2026-11-01","2026-11-23")
  testthat::expect_equal(retry$stats()$stale,1)
  fail<-FALSE
  recovered<-manager();recovered$request("2026-11-01","2026-11-23");recovered$save()
  testthat::expect_equal(recovered$stats()$pending,0)
  bounded<-manager(cap=1L);bounded$request("2026-11-01","2026-11-23")
  testthat::expect_error(bounded$request("2026-11-01",at="2026-11-01"),"no verified")
  testthat::expect_equal(bounded$stats()$requests,1)
  testthat::expect_equal(bounded$stats()$deferred,1)
  testthat::expect_equal(bounded$stats()$missing,1)
  testthat::expect_error(manager(FALSE)$request("2026-10-01","2026-11-01"),"no verified")
})

testthat::test_that("the daily workflow refreshes hazards after reports and includes its summary", {
  withr::local_dir(hazard_daily_root)
  source("R/daily-publish.R",local=TRUE)
  order<-character()
  result<-run_swc_daily_publish(dry_run=TRUE,force_publish=TRUE,marker_path=tempfile(),log_path=NULL,
    prism_update=function()list(summary=data.frame(data_changed=FALSE)),
    explorer_update=function()list(status="STAGED"),weather_update=function(today)list(status="DISABLED"),
    storm_reports_update=function(today){order<<-c(order,"reports");list(status="DISABLED")},
    nws_hazards_update=function(today){order<<-c(order,"hazards");list(status="READY",events=10L,cutoff="2026-11-22",
      requests=2L,refreshed=2L,reused=4L,stale=0L,deferred=0L,retry_pending=0L,seconds=1)},
    snow_update=function(today)list(maps=list(status="OUT_OF_SEASON")),station_update=function(today)list(status="UPDATED"),
    monthly_update=function(today)list(status="DISABLED"),interactive_update=function(today)list(status="DISABLED"),
    site_fingerprint=function()"fixture",publish=function(dry_run){order<<-c(order,"publish");list()})
  testthat::expect_identical(order,c("reports","hazards","publish"))
  testthat::expect_identical(result$nws_hazards$status,"READY")
  testthat::expect_true(any(grepl("NWS hazards: READY; 10 events",result$summary_lines,fixed=TRUE)))
})
