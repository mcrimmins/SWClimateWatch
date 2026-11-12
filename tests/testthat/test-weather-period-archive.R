for(file in c("weather-circulation-pilot.R","weather-core-index-recovery.R","weather-moisture-pilot.R",
  "weather-seven-day-pilot.R","weather-period-means-pilot.R","weather-period-moisture-overlays.R","weather-circulation-archive.R"))
  source(file.path(project_root,"R",file))
testthat::test_that("rolling mean builds resume, reuse, reject stale inputs and verify staging",{
  root<-withr::local_tempdir();explorer<-file.path(root,"explorer");dir.create(explorer)
  dates<-c("2026-10-03","2026-10-04","2026-10-05")
  jsonlite::write_json(list(schema_version=1L,days=lapply(dates,function(d)list(date=d)),circulation_enabled=TRUE),file.path(explorer,"daily-data.json"),auto_unbox=TRUE)
  jsonlite::write_json(list(days=lapply(dates,function(d)list(date=d,status="available"))),file.path(explorer,"circulation-manifest.json"),auto_unbox=TRUE)
  env<-new.env(parent=globalenv());sys.source(file.path(project_root,"R","weather-period-archive.R"),env)
  env$weather_mean_roots<-function()character();env$revision<-"one"
  env$weather_period_plan<-function(date,days,roots)data.frame(date=date,field=c("height500","pwat","u250","v250"),
    md5=if(date=="2026-10-05")env$revision else "stable",index_md5="idx",ready=TRUE,path="fixture")
  env$weather_overlay_inputs<-function(dates,...)list(inputs=data.frame(date=as.character(dates),field="fixture",md5="overlay",index_md5="idx"))
  env$weather_period_daily<-function(plan,cache_dir){dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE);list(date=plan$date[1],geometry=data.frame(x=200,y=40),
    values=matrix(c(5700,25.4,10,0),nrow=1,dimnames=list(NULL,c("height500","pwat","u250","v250"))))}
  env$weather_overlay_decode<-function(...)list(mslp=101000,u850=10,v850=0,surface=95000,wind_mask=TRUE)
  env$weather_mean_plot<-function(data,start,end,directory,days,include_jet=FALSE,moisture_overlay=NULL){
    paths<-setNames(file.path(directory,paste0(c("height500-","pwat-","jet250-"),days,"day.png")),c("height500","pwat","jet250"))
    if(!is.null(moisture_overlay))paths<-c(moisture=file.path(directory,paste0("pwat-overlay-",days,"day.png")))
    for(path in paths)writeLines("map",path);paths}
  cache<-file.path(root,"cache")
  one<-env$build_weather_period_archive(explorer,cache,max_new_end_dates=1L)
  testthat::expect_equal(one$built,2);testthat::expect_equal(one$deferred,4);testthat::expect_equal(one$requests,0)
  two<-env$build_weather_period_archive(explorer,cache,max_new_end_dates=1L)
  testthat::expect_equal(two$built,2);testthat::expect_equal(two$reused,2)
  three<-env$build_weather_period_archive(explorer,cache,max_new_end_dates=1L)
  testthat::expect_equal(three$built,2);testthat::expect_equal(three$reused,4)
  unchanged<-env$build_weather_period_archive(explorer,cache,max_new_end_dates=0L)
  testthat::expect_equal(unchanged$reused,6);testthat::expect_equal(unchanged$built,0)
  env$revision<-"two"
  revised<-env$build_weather_period_archive(explorer,cache,max_new_end_dates=0L)
  testthat::expect_equal(revised$deferred,2);testthat::expect_equal(revised$periods,4) # Stale means withdrawn.
  repaired<-env$build_weather_period_archive(explorer,cache,max_new_end_dates=1L)
  testthat::expect_equal(repaired$built,2)
  check<-env$validate_weather_period_assets(explorer);testthat::expect_equal(length(check$images),18)
  writeLines("corrupted",file.path(explorer,check$images[1]))
  testthat::expect_error(env$validate_weather_period_assets(explorer),"stale weather")
  # A missing day blocks both means, queues the raw dependency and survives
  # aging outside the recent endpoint selection until recovery and rebuilding.
  plan_builder<-env$weather_period_plan;env$missing<-"2026-09-30"
  env$weather_period_plan<-function(date,days,roots){p<-plan_builder(date,days,roots);p$ready<-date!=env$missing;p}
  blocked<-env$build_weather_period_archive(explorer,cache,max_new_end_dates=1L,recent_end_dates=1L)
  testthat::expect_equal(blocked$unavailable,2)
  testthat::expect_equal(read.csv(file.path(cache,"needed-dates.csv"))$date,"2026-09-30")
  testthat::expect_true("2026-10-05"%in%read.csv(file.path(cache,"retry-endpoints.csv"))$end)
  dates<-c(dates,"2026-11-10")
  jsonlite::write_json(list(schema_version=1L,days=lapply(dates,function(d)list(date=d)),circulation_enabled=TRUE),file.path(explorer,"daily-data.json"),auto_unbox=TRUE)
  jsonlite::write_json(list(days=lapply(dates,function(d)list(date=d,status="available"))),file.path(explorer,"circulation-manifest.json"),auto_unbox=TRUE)
  env$missing<-"";env$revision<-"recovered"
  env$build_weather_period_archive(explorer,cache,max_new_end_dates=1L,recent_end_dates=1L)
  recovered<-env$build_weather_period_archive(explorer,cache,max_new_end_dates=1L,recent_end_dates=1L)
  testthat::expect_equal(recovered$built,2)
  manifest<-jsonlite::read_json(file.path(explorer,"circulation-means-manifest.json"))
  testthat::expect_true(all(c(7L,30L)%in%vapply(Filter(function(p)p$end=="2026-10-05",manifest$periods),`[[`,integer(1),"days")))
  testthat::expect_equal(nrow(read.csv(file.path(cache,"needed-dates.csv"))),0)
  testthat::expect_equal(nrow(read.csv(file.path(cache,"retry-endpoints.csv"))),0)
})
