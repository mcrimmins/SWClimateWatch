source(file.path(project_root,"R","daily-publish.R"))

testthat::test_that("daily weather updates precede bounded cached means and errors isolate the selector",{
  withr::local_envvar(c(SWC_WEATHER_MAPS="true",SWC_WEATHER_PERIOD_MEANS="true",SWC_WEATHER_MEANS_MAX_NEW_DATES="3"))
  root<-withr::local_tempdir();report<-file.path(root,"report");calls<-character()
  payload<-list(circulation_enabled=TRUE,circulation_period_means_enabled=TRUE)
  jsonlite::write_json(payload,file.path(root,"daily-data.json"),auto_unbox=TRUE)
  daily<-function(today,explorer_dir,dependency_path){calls<<-c(calls,"daily");testthat::expect_equal(dependency_path,file.path(report,"needed-dates.csv"));list(status="READY",days=30,built=0,reused=30,failed=0,pending=0,latest="2026-11-11")}
  means<-function(explorer_dir,output_dir,max_new_end_dates){calls<<-c(calls,"means");testthat::expect_equal(max_new_end_dates,3)
    data.frame(periods=6,maps=18,built=2,reused=4,deferred=0,unavailable=0,requests=0,seconds=12,latest="2026-11-11")}
  result<-swc_daily_publish_update_weather(daily_builder=daily,means_builder=means,explorer_dir=root,means_report_dir=report)
  testthat::expect_identical(calls,c("daily","means"))
  testthat::expect_equal(result$period_means$status,"READY")
  testthat::expect_equal(read.csv(file.path(report,"workflow-status.csv"))$status,"READY")
  bad<-function(...)stop("missing cached field")
  result<-swc_daily_publish_update_weather(daily_builder=daily,means_builder=bad,explorer_dir=root,means_report_dir=report)
  testthat::expect_equal(result$status,"READY");testthat::expect_equal(result$period_means$status,"ERROR")
  testthat::expect_true(jsonlite::read_json(file.path(root,"daily-data.json"))$circulation_enabled)
  testthat::expect_false(jsonlite::read_json(file.path(root,"daily-data.json"))$circulation_period_means_enabled)
  testthat::expect_equal(read.csv(file.path(report,"workflow-status.csv"))$status,"ERROR")
  withr::local_envvar(c(SWC_WEATHER_MEANS_MAX_NEW_DATES="3.5"))
  result<-swc_daily_publish_update_weather_means(root,builder=function(...)stop("should not run"),report_dir=report)
  testthat::expect_match(result$error,"0-30")
  withr::local_envvar(c(SWC_WEATHER_MAPS="false"))
  jsonlite::write_json(payload,file.path(root,"daily-data.json"),auto_unbox=TRUE)
  testthat::expect_equal(swc_daily_publish_update_weather(daily_builder=bad,means_builder=bad,explorer_dir=root)$status,"DISABLED")
  testthat::expect_false(jsonlite::read_json(file.path(root,"daily-data.json"))$circulation_enabled)
  testthat::expect_false(jsonlite::read_json(file.path(root,"daily-data.json"))$circulation_period_means_enabled)
})

testthat::test_that("disabled, partial and invalid means are reported without network fallback",{
  root<-withr::local_tempdir();report<-file.path(root,"report")
  jsonlite::write_json(list(circulation_enabled=TRUE,circulation_period_means_enabled=TRUE),file.path(root,"daily-data.json"),auto_unbox=TRUE)
  withr::local_envvar(c(SWC_WEATHER_PERIOD_MEANS="false"))
  testthat::expect_equal(swc_daily_publish_update_weather_means(root,builder=function(...)stop("must not run"),report_dir=report)$status,"DISABLED")
  testthat::expect_false(jsonlite::read_json(file.path(root,"daily-data.json"))$circulation_period_means_enabled)
  withr::local_envvar(c(SWC_WEATHER_PERIOD_MEANS="true",SWC_WEATHER_MEANS_MAX_NEW_DATES="0"))
  builder<-function(...)data.frame(periods=2,maps=6,built=0,reused=2,deferred=2,unavailable=1,requests=0,seconds=2)
  testthat::expect_equal(swc_daily_publish_update_weather_means(root,builder,report)$status,"PARTIAL")
  builder<-function(...)data.frame(periods=2,maps=6,built=0,reused=2,deferred=0,unavailable=0,requests=1,seconds=2)
  testthat::expect_equal(swc_daily_publish_update_weather_means(root,builder,report)$status,"ERROR")
})

testthat::test_that("mean failures do not stop daily publication and phone summaries include mean stats",{
  root<-withr::local_tempdir();events<-character()
  weather<-function(today)list(status="READY",days=30,built=0,reused=30,failed=0,pending=0,latest="2026-11-11",
    period_means=list(status="ERROR",error="fixture"))
  result<-run_swc_daily_publish(dry_run=FALSE,force_publish=TRUE,marker_path=file.path(root,"marker.csv"),log_path=NULL,
    prism_update=function()list(summary=data.frame(data_changed=FALSE)),explorer_update=function()list(status="STAGED"),
    weather_update=weather,snow_update=function(today)list(maps=list(status="OUT_OF_SEASON")),station_update=function(today)list(status="UPDATED"),
    monthly_update=function(today)list(status="DISABLED"),site_fingerprint=function()"fixture",publish=function(dry_run)list(),
    notify=function(event,message)events<<-c(events,message))
  testthat::expect_equal(result$status,"PUBLISHED")
  testthat::expect_true(any(grepl("Weather period means failed",events,fixed=TRUE)))
  testthat::expect_true(any(grepl("Weather means: unavailable",result$summary_lines,fixed=TRUE)))
  record<-data.frame(status="PUBLISHED",elapsed_seconds=120)
  w<-weather(NULL);w$period_means<-list(status="READY",periods=6,maps=18,built=2,reused=4,deferred=0,unavailable=0,seconds=12)
  lines<-swc_daily_publish_summary_lines(record,weather=w,destination=swc_daily_publish_live_destination())
  testthat::expect_true(any(grepl("Weather means (7/30 days): 6 periods, 18 maps; 2 built, 4 reused",lines,fixed=TRUE)))
})
