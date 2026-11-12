source(file.path(project_root,"R","weather-moisture-pilot.R"))
source(file.path(project_root,"R","weather-period-moisture-overlays.R"))
testthat::test_that("period winds require above-ground support at every sample and every day",{
  fixture<-list(mslp=c(100000,102000),u850=c(10,-10),v850=c(0,0),surface=c(95000,97000),wind_mask=c(TRUE,TRUE))
  x<-rep(list(fixture),7)
  x[[3]]$wind_mask[1]<-FALSE
  x[[4]]$surface[2]<-NA
  y<-weather_overlay_average(x,7)
  testthat::expect_identical(y$wind_mask,c(FALSE,TRUE))
  testthat::expect_equal(y$mslp,c(100000,102000))
  testthat::expect_true(is.na(y$surface[2]))
  testthat::expect_error(weather_overlay_average(x[1:6],7),"Complete")
  x[[1]]$u850[1]<-NA
  testthat::expect_error(weather_overlay_average(x,7),"Incomplete")
  ps<-matrix(90000,2,8);ps[1,8]<-84000;ps[2,4]<-NA
  testthat::expect_identical(weather_moisture_wind_mask(ps,850),c(FALSE,FALSE))
})
testthat::test_that("overlay wind means retain direction cancellation",{
  x<-rep(list(list(mslp=101000,u850=10,v850=0,surface=95000,wind_mask=TRUE)),30)
  for(i in 16:30)x[[i]]$u850<--10
  testthat::expect_equal(weather_overlay_average(x,30)$u850,0)
})
testthat::test_that("overlay index identity and timing are explicit",{
  spec<-weather_overlay_specs("2026-09-06")[1,]
  lines<-c("1:0:d=2026090600:MSLET:mean sea level:8@3 hour ave(anl),missing=0:",
    "2:32:d=2026090600:UGRD:850 mb:8@3 hour ave(anl),missing=0:")
  testthat::expect_equal(weather_overlay_record(lines,spec),list(start=0,end=31))
  testthat::expect_error(weather_overlay_record(sub("20260906","20260907",lines),spec),"date")
  testthat::expect_error(weather_overlay_record(sub("missing=0","missing=1",lines),spec),"Incomplete")
  spec<-weather_overlay_specs("2026-09-06")[4,]
  testthat::expect_null(weather_overlay_record(lines,spec))
  testthat::expect_error(weather_overlay_inputs(as.Date("2026-09-01")+0:30),"cap")
})
