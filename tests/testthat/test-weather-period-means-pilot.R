source(file.path(project_root,"R","weather-circulation-pilot.R"))
source(file.path(project_root,"R","weather-seven-day-pilot.R"))
source(file.path(project_root,"R","weather-period-means-pilot.R"))

period_fixture<-function(n)lapply(seq_len(n),function(i)list(date=as.character(as.Date("2026-09-01")+i-1),
  geometry=data.frame(x=200,y=40),values=matrix(c(5700,25.4,10,0),nrow=1,
    dimnames=list(NULL,c("height500","pwat","u250","v250")))))

testthat::test_that("all periods use complete equal-weight means and correct units",{
  for(n in c(1L,7L,30L)) {
    x<-weather_period_average(period_fixture(n),n)
    testthat::expect_equal(x$height_dm,570)
    testthat::expect_equal(x$pwat_inches,1)
    testthat::expect_equal(x$speed_knots,19.43844)
  }
  testthat::expect_error(weather_period_average(period_fixture(6),7),"complete")
  x<-period_fixture(7);x[[3]]$date<-x[[2]]$date
  testthat::expect_error(weather_period_average(x,7),"consecutive")
  x<-period_fixture(7);x[[3]]$values[1,1]<-NA
  testthat::expect_error(weather_period_average(x,7),"Incomplete")
  x<-period_fixture(7);x[[3]]$geometry$x<-201
  testthat::expect_error(weather_period_average(x,7),"inconsistent")
})
testthat::test_that("jet speed follows component means rather than scalar wind speeds",{
  x<-period_fixture(30)
  for(i in 16:30)x[[i]]$values[1,"u250"]<--10
  result<-weather_period_average(x,30)
  testthat::expect_equal(result$u250,0)
  testthat::expect_equal(result$speed_knots,0)
  testthat::expect_equal(mean(vapply(x,function(d)abs(d$values[1,"u250"]),numeric(1))),10)
})
testthat::test_that("wind indexes require correct level and complete daily samples",{
  lines<-c("1:0:d=2026090100:UGRD:250 mb:8@3 hour ave(anl),missing=0:",
    "2:32:d=2026090100:VGRD:250 mb:8@3 hour ave(anl),missing=0:",
    "3:64:d=2026090100:HGT:500 mb:8@3 hour ave(anl),missing=0:")
  testthat::expect_equal(weather_mean_record(lines,"2026-09-01","u250")$end,31)
  testthat::expect_equal(weather_mean_record(lines,"2026-09-01","v250")$start,32)
  testthat::expect_error(weather_mean_record(gsub("250 mb","200 mb",lines),"2026-09-01","u250"),"Missing")
  testthat::expect_error(weather_mean_record(gsub("missing=0","missing=1",lines),"2026-09-01","v250"),"complete")
})
testthat::test_that("oversized downloads fail before requests",{
  testthat::expect_error(weather_period_download(data.frame(ready=rep(FALSE,121),date=rep("2026-09-01",121))),"cap")
})
