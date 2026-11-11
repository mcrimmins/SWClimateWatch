source(file.path(project_root,"R","acis-station-precipitation-records.R"))
rain_record_fixture<-function() {
  years<-1980:2026;rain<-rep(.1,length(years))
  rain[years %in% c(1999,2010,2024)]<-2;rain[years==2025]<-3;rain[years==2026]<-3.1
  d<-data.frame(date=as.Date(paste0(years,"-05-15")),variable="pcpn",numeric_value=rain,
    observed=TRUE,flag="",accumulated=FALSE,trace=FALSE)
  d$numeric_value[years==2015]<-20;d$accumulated[years==2015]<-TRUE
  d$numeric_value[years==2016]<-15;d$flag[years==2016]<-"S"
  d$numeric_value[years==2017]<-40;d$observed[years==2017]<-FALSE
  d$numeric_value[years==2018]<-101
  list(uid=1L,as_of=as.Date("2026-05-15"),daily=d)
}
testthat::test_that("rain records exclude the current day, later years and unusable daily reports", {
  cache<-rain_record_fixture()
  detail<-list(uid=1L,as_of="2026-05-15",daily=data.frame(date=c("2024-05-15","2026-05-15"),
    pcpn=c(2,3.1),pcpn_status="AVAILABLE"))
  d<-acis_attach_precipitation_records(detail,cache)$daily
  testthat::expect_equal(d$record_pcpn,c(2,3))
  testthat::expect_equal(d$record_pcpn_years,c("1999,2010","2025"))
  testthat::expect_equal(d$record_pcpn_n,c(40L,42L))
  testthat::expect_equal(d$record_pcpn_status,c("TIED_RECORD","NEW_RECORD"))
  testthat::expect_equal(d$pcpn,detail$daily$pcpn)
  cache$daily$accumulated[cache$daily$date==as.Date("2026-05-15")]<-TRUE
  detail$daily<-detail$daily[2,,drop=FALSE];detail$daily$pcpn<-NA_real_;detail$daily$pcpn_status<-"FLAGGED"
  d<-acis_attach_precipitation_records(detail,cache)$daily
  testthat::expect_equal(d$pcpn_record_observation_status,"ACCUMULATED")
  testthat::expect_equal(d$record_pcpn_status,"ACCUMULATED_REPORT")
  testthat::expect_equal(d$record_pcpn,3)
})
testthat::test_that("zero and trace-only references do not create tied wettest-day claims", {
  cache<-rain_record_fixture();cache$daily$flag<-"T";cache$daily$trace<-TRUE
  cache$daily$numeric_value<-.005;cache$daily$observed<-TRUE;cache$daily$accumulated<-FALSE
  detail<-list(uid=1L,as_of="2026-05-15",daily=data.frame(date="2026-05-15",pcpn=.005,pcpn_status="TRACE"))
  d<-acis_attach_precipitation_records(detail,cache)$daily
  testthat::expect_equal(d$record_pcpn,0)
  testthat::expect_equal(d$record_pcpn_years,"")
  testthat::expect_equal(d$record_pcpn_status,"NO_MEASURABLE_RECORD")
  detail$daily$pcpn<-.01;detail$daily$pcpn_status<-"AVAILABLE"
  d<-acis_attach_precipitation_records(detail,cache)$daily
  testthat::expect_equal(d$record_pcpn_status,"NEW_RECORD")
  cache$daily<-cache$daily[cache$daily$date>=as.Date("2010-01-01"),]
  testthat::expect_true(is.na(acis_attach_precipitation_records(detail,cache)$daily$record_pcpn))
})
testthat::test_that("precipitation leap records use real leap-day reports", {
  dates<-as.Date(paste0(seq(1992,2024,by=4),"-02-29"))
  d<-data.frame(date=dates,variable="pcpn",numeric_value=.5,observed=TRUE,flag="",accumulated=FALSE)
  d$numeric_value[format(d$date,"%Y") %in% c("2000","2016")]<-1
  cache<-list(uid=1L,as_of=as.Date("2024-02-29"),daily=d)
  detail<-list(uid=1L,as_of="2024-02-29",daily=data.frame(date="2024-02-29",pcpn=1.1,pcpn_status="AVAILABLE"))
  out<-acis_attach_precipitation_records(detail,cache)$daily
  testthat::expect_equal(out$record_pcpn,1);testthat::expect_equal(out$record_pcpn_n,8L)
  testthat::expect_equal(out$record_pcpn_years,"2000,2016")
  testthat::expect_equal(out$record_pcpn_status,"NEW_RECORD")
  testthat::expect_true(is.na(acis_attach_precipitation_records(detail,cache,leap_min_years=9L)$daily$record_pcpn))
})
