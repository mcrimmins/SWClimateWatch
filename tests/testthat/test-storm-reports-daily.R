storm_daily_root<-normalizePath(testthat::test_path("..",".."),winslash="/",mustWork=TRUE)
source(file.path(storm_daily_root,"R/storm-reports-daily.R"))
source(file.path(storm_daily_root,"R/storm-reports-pilot.R"))
testthat::test_that("daily report opt-in requires matching release settings", {
  withr::local_envvar(c(SWC_STORM_REPORTS="false"))
  testthat::expect_identical(prepare_storm_reports_daily()$status,"DISABLED")
  withr::local_envvar(c(SWC_STORM_REPORTS="true",
    SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch-staging/",
    SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch-staging"))
  testthat::expect_silent(storm_reports_daily_guard())
  withr::local_envvar(c(SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch/"))
  testthat::expect_error(storm_reports_daily_guard(),"matching destination/state")
  withr::local_envvar(c(SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch"))
  testthat::expect_silent(storm_reports_daily_guard())
})
storm_daily_fetch<-function(start,end,revision=FALSE) {
  dates<-as.character(seq(as.Date(start),as.Date(end)-1,by="day"))
  if(revision)dates<-setdiff(dates,"2024-03-01")
  list(start=as.character(start),end=as.character(end),fetched_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),
    raw=list(type="FeatureCollection",features=lapply(dates,function(date)list(type="Feature",properties=list(
      valid=paste0(date,"T18:00:00Z"),state="AZ",typetext="RAIN",magnitude=if(revision)"2"else"1",unit="Inch",
      qualifier="M",lat=33,lon=-110,city="Fixture",source="Public",remark="Fixture report")))))
}

testthat::test_that("recent revisions/deletions refresh and source failures retry with verified fallbacks",{
  withr::local_dir(storm_daily_root)
  root<-tempfile("storm-daily-",tmpdir="data/diagnostics");dir.create(root)
  cache<-file.path(root,"cache");raw<-file.path(root,"raw")
  update<-function(end="2024-03-02",fetcher=storm_daily_fetch,download=TRUE)
    refresh_storm_reports_cache("2024-02-27",end,download=download,refresh_days=2,cache_dir=cache,raw_dir=raw,fetcher=fetcher)
  first<-update();testthat::expect_equal(first$summary$requests,2)
  testthat::expect_equal(first$summary$status,"READY");testthat::expect_length(first$snapshot$reports,4)
  revised<-update(fetcher=function(a,b)storm_daily_fetch(a,b,TRUE))
  testthat::expect_equal(revised$summary$requests,1);testthat::expect_equal(revised$summary$changed,2)
  testthat::expect_length(revised$snapshot$reports,3)
  testthat::expect_equal(storm_reports_read_day(file.path(cache,"2024-02-27.rds"))$reports[[1]]$magnitude,"1")
  testthat::expect_length(storm_reports_read_day(file.path(cache,"2024-03-01.rds"))$reports,0)
  failed<-update(fetcher=function(a,b)stop("provider unavailable"))
  testthat::expect_equal(failed$summary$status,"PARTIAL");testthat::expect_equal(failed$summary$stale,2)
  cached<-update(download=FALSE,fetcher=function(a,b)stop("must not download"))
  testthat::expect_equal(cached$summary$requests,0);testthat::expect_equal(cached$summary$stale,2)
  next_failed<-update("2024-03-03",fetcher=function(a,b)stop("provider unavailable"))
  testthat::expect_equal(next_failed$summary$missing,1)
  recovered<-update("2024-03-03",fetcher=storm_daily_fetch)
  testthat::expect_equal(recovered$summary$status,"READY");testthat::expect_equal(recovered$summary$stale,0)
  testthat::expect_equal(recovered$summary$missing,0)
  # A corrupt primary reads the last verified backup and a refresh can replace it.
  path<-file.path(cache,"2024-02-29.rds");writeLines("bad",path)
  testthat::expect_true(is.list(storm_reports_read_day(path)))
})

testthat::test_that("cold outages and request caps do not fabricate empty report dates",{
  withr::local_dir(storm_daily_root)
  root<-tempfile("storm-cold-",tmpdir="data/diagnostics");dir.create(root)
  failed<-refresh_storm_reports_cache("2024-01-01","2024-04-01",cache_dir=file.path(root,"cache"),raw_dir=file.path(root,"raw"),fetcher=function(a,b)stop("offline"))
  testthat::expect_equal(failed$summary$status,"UNAVAILABLE");testthat::expect_equal(failed$summary$requests,3)
  testthat::expect_equal(failed$summary$available,0);testthat::expect_length(failed$snapshot$available_dates,0)
  ready<-refresh_storm_reports_cache("2024-01-01","2024-04-01",cache_dir=file.path(root,"cache"),raw_dir=file.path(root,"raw"),fetcher=storm_daily_fetch)
  testthat::expect_equal(ready$summary$status,"READY");testthat::expect_equal(ready$summary$dates,91)
  testthat::expect_equal(ready$summary$requests,3)
})

testthat::test_that("publication can stage an honest missing-data snapshot without source requests",{
  withr::local_dir(storm_daily_root)
  source("R/storm-reports-staging.R",local=TRUE)
  root<-tempfile("storm-unavailable-",tmpdir="data/diagnostics");dir.create(root)
  fixture<-file.path(root,"explorer");dir.create(fixture)
  original<-jsonlite::read_json("site/daily-explorer/daily-data.json");original$days<-tail(original$days,2)
  original$publication_mode<-TRUE
  jsonlite::write_json(original,file.path(fixture,"daily-data.json"),auto_unbox=TRUE,null="null",digits=NA)
  stage_storm_reports_snapshot(fixture,file.path(root,"candidate"),snapshot=list(reports=list(),available_dates=character(),stale_dates=character(),snapshots=list()))
  catalog<-jsonlite::read_json(file.path(fixture,"storm-reports-manifest.json"))
  testthat::expect_true(all(vapply(catalog$days,function(d)d$status=="UNAVAILABLE",logical(1))))
  testthat::expect_true(all(vapply(catalog$timeline$prism,function(d)!d$available&&!d$complete,logical(1))))
})

testthat::test_that("daily runner refreshes reports before publication and reports degraded coverage",{
  withr::local_dir(storm_daily_root)
  source("R/daily-publish.R",local=TRUE)
  calls<-character()
  result<-run_swc_daily_publish(dry_run=TRUE,force_publish=TRUE,marker_path=tempfile(),log_path=NULL,
    destination="s3://cales-climate-reports/climate/watch-staging/",
    prism_update=function()list(summary=data.frame(data_changed=FALSE)),
    explorer_update=function(){calls<<-c(calls,"explorer");list(status="STAGED",days=2,maps=14,built=0,reused=2)},
    weather_update=function(today){calls<<-c(calls,"weather");list(status="DISABLED")},
    storm_reports_update=function(today){calls<<-c(calls,"reports");list(status="PARTIAL",available=2,dates=3,reports=4,refreshed=1,reused=1,requests=1,stale=1,missing=1,seconds=.2)},
    snow_update=function(today)list(maps=list(status="OUT_OF_SEASON")),station_update=function(today)list(status="UPDATED"),
    monthly_update=function(today)list(status="DISABLED"),interactive_update=function(today)list(status="DISABLED"),
    site_fingerprint=function(){calls<<-c(calls,"fingerprint");"fixture"},
    publish=function(dry_run){calls<<-c(calls,"publish");list()})
  testthat::expect_equal(result$status,"PREVIEW")
  testthat::expect_true(match("weather",calls)<match("reports",calls))
  testthat::expect_true(match("reports",calls)<match("fingerprint",calls))
  testthat::expect_true(match("reports",calls)<match("publish",calls))
  testthat::expect_equal(result$storm_reports$requests,1)
  testthat::expect_true(any(grepl("Storm reports: PARTIAL",result$summary_lines,fixed=TRUE)))
})
