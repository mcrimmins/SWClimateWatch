source(file.path(project_root,"R","weather-moisture-pilot.R"))

testthat::test_that("missing terrain fields degrade overlays without relaxing required fields", {
  idx<-data.frame(variable="PRES",level="surface",period="day",
    timing="8@3 hour ave(anl),missing=0",start=0,end=100)
  testthat::expect_equal(nrow(weather_moisture_select_field(idx,"PRES","surface",TRUE)),1L)
  missing<-idx; missing$variable<-"OTHER"
  testthat::expect_null(weather_moisture_select_field(missing,"PRES","surface",TRUE))
  incomplete<-idx; incomplete$timing<-"8@3 hour ave(anl),missing=1"
  testthat::expect_null(weather_moisture_select_field(incomplete,"PRES","surface",TRUE))
  testthat::expect_error(weather_moisture_select_field(incomplete,"PRES","surface"),"Required complete")
  testthat::expect_error(weather_moisture_select_field(idx,"PWAT","atmos col",TRUE),"Only surface")
  testthat::expect_error(weather_moisture_select_field(rbind(idx,idx),"PRES","surface",TRUE),"ambiguous")
  malformed<-idx; malformed$end<-NA_real_
  testthat::expect_error(weather_moisture_select_field(malformed,"PRES","surface",TRUE),"Invalid")
  hourly<-idx; hourly$period<-"3hour"; hourly$timing<-"anl"
  testthat::expect_equal(nrow(weather_moisture_select_field(hourly,"PRES","surface",TRUE)),1L)
  hourly$timing<-"3 hour fcst"
  testthat::expect_null(weather_moisture_select_field(hourly,"PRES","surface",TRUE))
})
testthat::test_that("low-level winds are withheld if below ground at any daily sample", {
  ps<-matrix(90000,nrow=4,ncol=8)
  ps[2,4]<-84000; ps[3,5]<-NA_real_; ps[4,1]<-85000
  testthat::expect_equal(weather_moisture_wind_mask(ps,850),c(TRUE,FALSE,FALSE,FALSE))
  testthat::expect_equal(weather_moisture_wind_mask(ps,700),c(TRUE,TRUE,FALSE,TRUE))
  testthat::expect_error(weather_moisture_wind_mask(ps[,1:7],850),"eight")
  testthat::expect_error(weather_moisture_wind_mask(ps,500),"700 or 850")
  ps[,6]<-NA_real_
  testthat::expect_false(any(weather_moisture_wind_mask(ps,850)))
})

testthat::test_that("pressure-center labels reject noise, slopes and high terrain", {
  grid<-expand.grid(x=seq(120,300,1),y=seq(10,70,1))
  low<-exp(-((grid$x-180)^2+(grid$y-40)^2)/(2*6^2))
  high<-exp(-((grid$x-250)^2+(grid$y-40)^2)/(2*6^2))
  grid$pressure_hpa<-1010-25*low+25*high
  grid$surface_hpa<-1000
  centers<-weather_pressure_centers(grid)
  testthat::expect_equal(sort(centers$type),c("H","L"))
  testthat::expect_equal(centers$x[centers$type=="L"],180)
  testthat::expect_equal(centers$x[centers$type=="H"],250)
  testthat::expect_true(all(centers$contrast_hpa>=2))
  testthat::expect_equal(centers$pressure_hpa[centers$type=="L"],985,tolerance=1e-8)
  elevated<-grid; elevated$surface_hpa[abs(elevated$x-180)<3 & abs(elevated$y-40)<3]<-700
  testthat::expect_equal(weather_pressure_centers(elevated)$type,"H")
  unavailable<-grid; unavailable$surface_hpa<-NA_real_
  testthat::expect_equal(nrow(weather_pressure_centers(unavailable)),0L)
  weak<-grid; weak$pressure_hpa<-1010-.5*low
  testthat::expect_equal(nrow(weather_pressure_centers(weak)),0)
  slope<-grid; slope$pressure_hpa<-1000+.2*slope$x
  testthat::expect_equal(nrow(weather_pressure_centers(slope)),0)
  flat<-grid; flat$pressure_hpa<-1010
  testthat::expect_equal(nrow(weather_pressure_centers(flat)),0)
  edge<-grid; edge$pressure_hpa<-1010-25*exp(-((edge$x-123)^2+(edge$y-40)^2)/(2*4^2))
  testthat::expect_equal(nrow(weather_pressure_centers(edge)),0)
})
