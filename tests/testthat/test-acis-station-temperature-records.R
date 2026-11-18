source(file.path(project_root,"R","acis-station-temperature-records.R"))
temperature_record_fixture <- function() {
  years<-1980:2026;dates<-as.Date(paste0(years,"-05-15"))
  hi<-rep(90,length(years));lo<-rep(40,length(years))
  hi[years %in% c(1999,2010,2024)]<-100;lo[years %in% c(1996,2000,2024)]<-30
  hi[years==2025]<-110;lo[years==2025]<-20
  hi[years==2026]<-111;lo[years==2026]<-19
  list(uid=1L,as_of=as.Date("2026-05-15"),daily=rbind(
    data.frame(date=dates,variable="maxt",numeric_value=hi,observed=TRUE,flag=""),
    data.frame(date=dates,variable="mint",numeric_value=lo,observed=TRUE,flag="")))
}
testthat::test_that("records exclude observations and later years, preserving tied years", {
  cache<-temperature_record_fixture()
  detail<-list(uid=1L,as_of="2026-05-15",daily=data.frame(date=c("2024-05-15","2026-05-15"),maxt=c(100,111),mint=c(30,19)))
  d<-acis_attach_temperature_records(detail,cache)$daily
  testthat::expect_equal(d$record_high,c(100,110))
  testthat::expect_equal(d$record_low,c(30,20))
  testthat::expect_equal(d$record_high_years,c("1999,2010","2025"))
  testthat::expect_equal(d$record_low_years,c("1996,2000","2025"))
  testthat::expect_equal(d$record_high_status,c("TIED_HIGH","NEW_HIGH"))
  testthat::expect_equal(d$record_low_status,c("TIED_LOW","NEW_LOW"))
  testthat::expect_equal(d$record_high_n,c(44L,46L))
  testthat::expect_equal(d$maxt,detail$daily$maxt)
})
testthat::test_that("flags, inverted pairs and insufficient history cannot create records", {
  cache<-temperature_record_fixture()
  detail<-list(uid=1L,as_of="2026-05-15",daily=data.frame(date="2026-05-15",maxt=NA_real_,mint=19))
  target<-cache$daily$date==as.Date("2025-05-15")
  cache$daily$flag[target & cache$daily$variable=="maxt"]<-"S"
  d<-acis_attach_temperature_records(detail,cache)$daily
  testthat::expect_equal(d$record_high,100);testthat::expect_equal(d$record_low,20)
  testthat::expect_equal(d$record_high_status,"MISSING_OBSERVATION")
  cache$daily$flag[]<-""
  cache$daily$numeric_value[target & cache$daily$variable=="maxt"]<-10
  d<-acis_attach_temperature_records(detail,cache)$daily
  testthat::expect_equal(d$record_high,100);testthat::expect_equal(d$record_low,30)
  cache$daily<-cache$daily[cache$daily$date>=as.Date("2010-01-01"),]
  d<-acis_attach_temperature_records(detail,cache)$daily
  testthat::expect_true(is.na(d$record_high))
  testthat::expect_equal(d$record_high_status,"INSUFFICIENT_HISTORY")
  testthat::expect_true(is.na(acis_attach_temperature_records(detail,NULL)$daily$record_high))
})
testthat::test_that("leap records use actual leap observations and explicit support", {
  dates<-as.Date(paste0(seq(1992,2024,by=4),"-02-29"))
  cache<-list(uid=1L,as_of=as.Date("2024-02-29"),daily=rbind(
    data.frame(date=dates,variable="maxt",numeric_value=90,observed=TRUE,flag=""),
    data.frame(date=dates,variable="mint",numeric_value=40,observed=TRUE,flag=""),
    data.frame(date=as.Date("2023-02-28"),variable="maxt",numeric_value=140,observed=TRUE,flag="")))
  detail<-list(uid=1L,as_of="2024-02-29",daily=data.frame(date="2024-02-29",maxt=91,mint=39))
  d<-acis_attach_temperature_records(detail,cache)$daily
  testthat::expect_equal(d$record_high,90);testthat::expect_equal(d$record_high_n,8L)
  testthat::expect_equal(d$record_high_status,"NEW_HIGH")
  testthat::expect_false(grepl("2023|2024",d$record_high_years))
  testthat::expect_true(is.na(acis_attach_temperature_records(detail,cache,leap_min_years=9L)$daily$record_high))
  testthat::expect_true(is.na(acis_attach_temperature_records(detail,cache,min_span_years=35L)$daily$record_high))
})
