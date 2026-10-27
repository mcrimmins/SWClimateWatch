source(file.path(project_root,"R","weather-circulation-pilot.R"))
source(file.path(project_root,"R","weather-core-index-recovery.R"))

pressure_grib_fixture <- function() {
  uint<-function(n,size) as.raw(floor(n/256^rev(seq_len(size)-1))%%256)
  product<-as.raw(rep(0,34)); product[1:4]<-uint(34,4); product[5]<-as.raw(4)
  product[10]<-as.raw(3); product[12]<-as.raw(2); product[23]<-as.raw(1); product[29]<-as.raw(255)
  c(charToRaw("GRIB"),as.raw(c(0,0,0,2)),uint(54,8),product,charToRaw("7777"))
}

testthat::test_that("bounded recovery identifies pressure metadata and rejects ambiguous records", {
  b<-pressure_grib_fixture()
  found<-weather_core_find_surface_pressure(c(as.raw(c(1,2)),b),offset=100)
  testthat::expect_equal(found$start,102)
  testthat::expect_equal(found$end,155)
  testthat::expect_identical(found$body,b)
  wrong<-b; wrong[16+11]<-as.raw(1)
  testthat::expect_null(weather_core_find_surface_pressure(wrong))
  wrong<-b; wrong[16+23]<-as.raw(100)
  testthat::expect_null(weather_core_find_surface_pressure(wrong))
  wrong<-b; wrong[16+22]<-as.raw(3)
  testthat::expect_null(weather_core_find_surface_pressure(wrong))
  testthat::expect_null(weather_core_find_surface_pressure(head(b,-1)))
  wrong<-b; wrong[length(wrong)]<-as.raw(0)
  testthat::expect_null(weather_core_find_surface_pressure(wrong))
  testthat::expect_error(weather_core_find_surface_pressure(c(b,b)),"Ambiguous")
})

testthat::test_that("recovery bounds transfers, pins object identity and verifies cached bytes", {
  b<-pressure_grib_fixture(); calls<-0L; changed<-FALSE
  get<-function(url,start,end,etag=NULL) {
    calls<<-calls+1L
    testthat::expect_lte(end-start+1,1e6)
    if(start==0) result<-b[1:16] else {
      testthat::expect_identical(etag,'"object-v1"')
      result<-raw(end-start+1)
      if(start==1000000) result[124:(123+length(b))]<-b
    }
    attr(result,"object_size")<-4000000
    attr(result,"etag")<-if(changed && start>0) '"object-v2"' else '"object-v1"'
    result
  }
  root<-tempfile(); dir.create(root); on.exit(unlink(root,recursive=TRUE),add=TRUE)
  base<-"https://storage.googleapis.com/noaa-nws-ncep-core/grib/3hour/pgb/2026/09/pgb.2026092809"
  result<-weather_core_recover_surface_pressure(base,"2026092809",root,get)
  testthat::expect_equal(calls,3L)
  testthat::expect_equal(result$start,1000123)
  weather_core_recover_surface_pressure(base,"2026092809",root,get)
  testthat::expect_equal(calls,3L)
  writeBin(charToRaw("broken"),file.path(root,"3hour-pgb-2026092809-PRES-surface.grb"))
  weather_core_recover_surface_pressure(base,"2026092809",root,get)
  testthat::expect_equal(calls,6L)
  changed<-TRUE
  testthat::expect_error(weather_core_recover_surface_pressure(base,"2026092809",root,get,refresh=TRUE),"object changed")
  testthat::expect_error(weather_core_check_range(raw(16),200,"bytes 0-15/100",0,15),"exact requested")
  testthat::expect_error(weather_core_check_range(raw(15),206,"bytes 0-15/100",0,15),"exact requested")
  testthat::expect_error(weather_core_check_range(raw(16),206,"bytes 1-16/100",0,15),"exact requested")
})
