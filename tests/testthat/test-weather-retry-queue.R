source(file.path(project_root,"R","weather-circulation-archive.R"))
testthat::test_that("newest missing dates cannot crowd out queued older failures",{
  dates<-as.character(as.Date("2026-10-01")+0:11)
  gaps<-c("2026-10-02",tail(dates,3))
  plan<-weather_archive_plan(dates,known_dates=setdiff(dates,gaps),start_date=dates[1],
    today=as.Date("2026-10-13"),max_new_dates=3,recheck_days=0,retry_dates=gaps,
    retry_order=gaps,refresh_dates="2026-10-02")
  testthat::expect_equal(plan$date[1],"2026-10-12")
  testthat::expect_true("2026-10-02"%in%plan$date)
  testthat::expect_equal(plan$action[plan$date=="2026-10-02"],"RETRY")
  testthat::expect_lte(nrow(plan),3)
})
testthat::test_that("next daily runs recover failed dates and refresh queued mean dependencies",{
  root<-withr::local_tempdir();explorer<-file.path(root,"explorer");archive<-file.path(root,"archive")
  dependency<-file.path(root,"needed-dates.csv");dir.create(explorer)
  write_payload<-function(dates)jsonlite::write_json(list(days=lapply(dates,function(d)list(date=d))),file.path(explorer,"daily-data.json"),auto_unbox=TRUE)
  env<-new.env(parent=globalenv());sys.source(file.path(project_root,"R","weather-circulation-archive.R"),env)
  env$weather_renderer_signature<-function()"fixture";env$fail<-"2026-10-02";env$refreshed<-character()
  env$build_weather_circulation_cached<-function(dates,output_dir,refresh=FALSE){
    date<-as.character(dates);if(refresh)env$refreshed<-c(env$refreshed,date)
    failed<-date%in%env$fail
    if(!failed){d<-file.path(output_dir,date);dir.create(d,recursive=TRUE,showWarnings=FALSE);for(f in c("height500.png","jet250.png","moisture.png"))writeLines(date,file.path(d,f))}
    data.frame(date,status=if(failed)"FAILED" else "BUILT",requests=0,transferred_bytes=0,elapsed_seconds=0,note=if(failed)"HTTP 404" else "")}
  dates<-as.character(as.Date("2026-10-01")+0:4);write_payload(dates)
  first<-env$update_weather_circulation_archive(explorer,archive,today=as.Date("2026-10-06"),max_new_dates=5,recheck_days=0,dependency_path=dependency)
  testthat::expect_equal(first$retry_pending,1)
  testthat::expect_equal(read.csv(file.path(archive,"retry-queue.csv"))$date,"2026-10-02")
  # Upgrade compatibility: a pre-queue state still imports FAILED from the
  # previous batch and refreshes its cached indexes on the first upgraded run.
  state<-readRDS(file.path(archive,"archive-state.rds"));state$pending<-NULL
  saveRDS(state,file.path(archive,"archive-state.rds"))
  env$fail<-character();write_payload(c(dates,"2026-10-06"))
  next_run<-env$update_weather_circulation_archive(explorer,archive,today=as.Date("2026-10-07"),max_new_dates=3,recheck_days=0,dependency_path=dependency)
  testthat::expect_equal(next_run$retry_pending,0);testthat::expect_equal(next_run$days,6)
  testthat::expect_true("2026-10-02"%in%env$refreshed)
  # Existing PNGs do not suppress raw-field repair requested by a mean.
  write.csv(data.frame(date="2026-10-01",note="required cached field missing"),dependency,row.names=FALSE)
  env$refreshed<-character()
  env$update_weather_circulation_archive(explorer,archive,today=as.Date("2026-10-08"),max_new_dates=3,recheck_days=0,dependency_path=dependency)
  testthat::expect_true("2026-10-01"%in%env$refreshed)
  write.csv(data.frame(date=character(),note=character()),dependency,row.names=FALSE)
  env$refreshed<-character()
  env$update_weather_circulation_archive(explorer,archive,today=as.Date("2026-10-09"),max_new_dates=3,recheck_days=0,dependency_path=dependency)
  testthat::expect_length(env$refreshed,0)
})
