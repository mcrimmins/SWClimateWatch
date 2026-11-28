stats_root<-normalizePath(testthat::test_path("../.."),winslash="/",mustWork=TRUE)
source(file.path(stats_root,"R/streamflow-pilot.R"))
source(file.path(stats_root,"R/streamflow-statistics.R"))
stats_feature<-function(day="11-26",n=40L,values=as.character(c(0,1,2,3,4,5,6))) {
  list(type="Feature",properties=list(monitoring_location_id="USGS-09506000",data=list(list(parameter_code="00060",
    parent_time_series_id="abc123",parent_statistic_id="00003",unit_of_measure="ft^3/s",values=list(list(
      time_of_year=day,time_of_year_type="day_of_year",values=as.list(values),percentiles=as.list(as.character(c(5,10,25,50,75,90,95))),
      sample_count=n,approval_status="approved",computation="percentile"))))))
}
testthat::test_that("calendar-day percentiles require support, approval and correct identity",{
  x<-streamflow_normals(list(stats_feature()),"USGS-09506000","abc123")
  r<-x[x$month_day=="11-26",]
  testthat::expect_true(r$supported);testthat::expect_equal(r$p50,3);testthat::expect_equal(r$sample_count,40)
  low<-streamflow_normals(list(stats_feature(n=29)),"USGS-09506000","abc123")
  testthat::expect_false(any(low$supported));testthat::expect_true(all(is.na(low$p50)))
  testthat::expect_error(streamflow_normals(list(stats_feature()),"USGS-00000000","abc123"),"gauge identity")
  testthat::expect_error(streamflow_normals(list(stats_feature()),"USGS-09506000","wrong"),"series identity")
  bad<-stats_feature();bad$properties$data[[1]]$values[[1]]$approval_status<-"provisional"
  testthat::expect_false(any(streamflow_normals(list(bad),"USGS-09506000","abc123")$supported))
  bad<-stats_feature();bad$properties$data[[1]]$unit_of_measure<-"ft"
  testthat::expect_error(streamflow_normals(list(bad),"USGS-09506000","abc123"),"parameter/unit/statistic")
  testthat::expect_error(streamflow_normals(list(stats_feature(),stats_feature()),"USGS-09506000","abc123"),"Duplicate")
})
testthat::test_that("leap day is not substituted and unordered thresholds are withheld",{
  f1<-stats_feature("02-28");f2<-stats_feature("02-29",n=20);f3<-stats_feature("03-01",values=as.character(10:16))
  x<-streamflow_normals(list(f1,f2,f3),"USGS-09506000","abc123")
  testthat::expect_equal(x$p50[x$month_day=="02-28"],3)
  testthat::expect_true(is.na(x$p50[x$month_day=="02-29"]))
  testthat::expect_equal(x$p50[x$month_day=="03-01"],13)
  bad<-streamflow_normals(list(stats_feature(values=c("0","5","2","3","4","1","6"))),"USGS-09506000","abc123")
  testthat::expect_false(any(bad$supported))
})
testthat::test_that("categories are threshold ranges with explicit zero/tie handling",{
  r<-data.frame(supported=TRUE,p10=1,p25=2,p50=3,p75=4,p90=5)
  testthat::expect_equal(vapply(c(0,1,2,4,5,6),streamflow_historical_category,character(1),normal=r),
    c("Below 10th","10th\u201325th","25th\u201375th","25th\u201375th","75th\u201390th","Above 90th"))
  r$p10<-r$p25<-r$p50<-0
  testthat::expect_equal(streamflow_historical_category(0,r),"Tied thresholds")
  r$supported<-FALSE
  testthat::expect_equal(streamflow_historical_category(0,r),"History unavailable")
  testthat::expect_equal(streamflow_historical_category(NA_real_,r),"Unavailable")
})
testthat::test_that("historical-statistics cache is verified and reusable without HTTP",{
  cache<-tempfile();dir.create(cache);withr::defer(unlink(cache,recursive=TRUE))
  params<-list(monitoring_location_id="USGS-09506000",parent_time_series_id="abc123",parameter_code="00060",normal_type="DOY",
    computation_type="percentile",approval_status="approved",mime_type="application/json",page_size=10000L)
  req<-do.call(httr2::req_url_query,c(list(httr2::request("https://api.waterdata.usgs.gov/statistics/v0/observationNormals")),params))
  file<-file.path(cache,paste0(digest::digest(req$url,algo="sha256",serialize=FALSE),".json"))
  jsonlite::write_json(list(type="FeatureCollection",features=list(stats_feature()),`next`=NULL),file,auto_unbox=TRUE)
  saveRDS(list(sha256=digest::digest(file=file,algo="sha256",serialize=FALSE),fetched_utc="2026-11-27T12:00:00Z"),paste0(file,".rds"))
  x<-streamflow_statistics_request("USGS-09506000","abc123",cache_dir=cache,download=FALSE)
  testthat::expect_true(x$metrics$reused);testthat::expect_equal(x$metrics$transferred_bytes,0)
  writeLines("modified",file)
  testthat::expect_error(streamflow_statistics_request("USGS-09506000","abc123",cache_dir=cache,download=FALSE),"Verified historical")
})
