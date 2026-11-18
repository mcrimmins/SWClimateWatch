source(file.path(project_root,"R","acis-station-monthly-climatology.R"))
monthly_fixture<-function(){
  dates<-seq(as.Date("1991-01-01"),as.Date("2020-12-31"),by="day")
  daily<-do.call(rbind,lapply(c("pcpn","maxt","mint"),function(v)
    data.frame(date=dates,variable=v,numeric_value=switch(v,pcpn=.1,maxt=80,mint=50),
      observed=TRUE,flag="",accumulated=FALSE,trace=FALSE)))
  list(uid=123L,as_of=as.Date("2026-11-03"),daily=daily)
}
testthat::test_that("monthly values use actual month lengths and independent eligible years",{
  cache<-monthly_fixture();ref<-acis_station_monthly_climatology(cache,123)
  testthat::expect_equal(ref$monthly$precip_inches[1],3.1)
  testthat::expect_equal(ref$monthly$precip_inches[2],mean(as.integer(format(as.Date(paste0(1991:2020,"-03-01"))-1,"%d")))*.1)
  testthat::expect_equal(ref$monthly$high_f,rep(80,12));testthat::expect_equal(ref$monthly$low_f,rep(50,12))
  testthat::expect_equal(ref$monthly$precipitation_years,rep(30L,12))
  # Accumulated precipitation invalidates only its month; one missing paired temperature day is tolerated.
  cache$daily$accumulated[cache$daily$variable=="pcpn" & cache$daily$date==as.Date("1991-01-10")]<-TRUE
  cache$daily$flag[cache$daily$variable=="maxt" & cache$daily$date==as.Date("1991-01-10")]<-"X"
  ref<-acis_station_monthly_climatology(cache,123,min_years=30)
  testthat::expect_equal(ref$monthly$precipitation_years[1],29L)
  testthat::expect_true(is.na(ref$monthly$precip_inches[1]))
  testthat::expect_true(is.na(ref$monthly$precip_p75[1]))
  testthat::expect_equal(ref$monthly$temperature_years[1],30L)
  cache$daily$observed[cache$daily$variable=="mint" & cache$daily$date %in% as.Date(c("1991-02-10","1991-02-11"))]<-FALSE
  ref<-acis_station_monthly_climatology(cache,123,min_years=30)
  testthat::expect_equal(ref$monthly$temperature_years[2],29L)
  testthat::expect_true(is.na(ref$monthly$high_f[2]))
})

testthat::test_that("variability uses eligible monthly distributions and preserves skew",{
  cache<-monthly_fixture();year<-as.integer(format(cache$daily$date,"%Y"))
  p<-cache$daily$variable=="pcpn";h<-cache$daily$variable=="maxt";l<-cache$daily$variable=="mint"
  cache$daily$numeric_value[p]<-(year[p]-1990)/100
  cache$daily$numeric_value[h]<-80+year[h]-1991
  cache$daily$numeric_value[l]<-50+year[l]-1991
  ref<-acis_station_monthly_climatology(cache,123)
  testthat::expect_equal(ref$monthly$precip_p25[1],unname(quantile(.31*(1:30),.25,type=7)))
  testthat::expect_equal(ref$monthly$precip_p75[1],unname(quantile(.31*(1:30),.75,type=7)))
  testthat::expect_equal(ref$monthly$high_p25[1],87.25)
  testthat::expect_equal(ref$monthly$low_p75[1],71.75)
  testthat::expect_equal(ref$monthly$precip_median[1],median(.31*(1:30)))
  testthat::expect_equal(ref$monthly$precip_min_years[1],"1991")
  testthat::expect_equal(ref$monthly$precip_max_years[1],"2020")
  testthat::expect_equal(ref$monthly$high_min[1],80)
  testthat::expect_equal(ref$monthly$high_max[1],109)
  cache$daily$numeric_value[p]<-ifelse(year[p]==2020,1,0)
  skew<-acis_station_monthly_climatology(cache,123)$monthly
  testthat::expect_equal(skew$precip_p75[1],0)
  testthat::expect_gt(skew$precip_inches[1],skew$precip_p75[1])
  testthat::expect_equal(skew$precip_median[1],0)
  testthat::expect_equal(skew$precip_max[1],31)
  testthat::expect_equal(skew$precip_max_years[1],"2020")
  testthat::expect_equal(length(strsplit(skew$precip_min_years[1],",",fixed=TRUE)[[1]]),29L)
  future<-cache$daily[cache$daily$variable=="pcpn" & format(cache$daily$date,"%Y-%m")=="2020-01",]
  future$date<-as.Date(paste0("2021",format(future$date,"-%m-%d")))
  future$numeric_value<-99
  cache$daily<-rbind(cache$daily,future)
  testthat::expect_equal(acis_station_monthly_climatology(cache,123)$monthly$precip_max[1],31)
})
testthat::test_that("trace is zero, absent leap days invalidate precipitation, null caches stay unavailable",{
  cache<-monthly_fixture()
  cache$daily$trace[cache$daily$variable=="pcpn" & cache$daily$date==as.Date("1991-01-10")]<-TRUE
  cache$daily<-cache$daily[!(cache$daily$variable=="pcpn" & cache$daily$date==as.Date("1992-02-29")),]
  ref<-acis_station_monthly_climatology(cache,123)
  testthat::expect_equal(ref$monthly$precip_inches[1],(29*3.1+3)/30)
  testthat::expect_equal(ref$monthly$precipitation_years[2],29L)
  testthat::expect_true(all(is.na(acis_station_monthly_climatology(NULL,123)$monthly$precip_inches)))
  cache$daily<-rbind(cache$daily,cache$daily[1,])
  testthat::expect_error(acis_station_monthly_climatology(cache,123),"Duplicate")
})
testthat::test_that("monthly cache ignores current rows but rebuilds for historical revisions",{
  cache<-monthly_fixture();directory<-tempfile("monthly-reference-")
  on.exit(unlink(directory,recursive=TRUE),add=TRUE)
  first<-read_or_build_acis_monthly_climatology(cache,123,directory)
  testthat::expect_false(first$reused)
  saved<-readRDS(file.path(directory,"123.rds"));saved$reference$baseline<-"bad period label"
  saveRDS(saved,file.path(directory,"123.rds"))
  repaired<-read_or_build_acis_monthly_climatology(cache,123,directory)
  testthat::expect_true(repaired$reused)
  testthat::expect_identical(repaired$reference$baseline,"1991\u20132020")
  extra<-cache$daily[1,];extra$date<-as.Date("2026-11-02")
  cache$daily<-rbind(cache$daily,extra)
  testthat::expect_true(read_or_build_acis_monthly_climatology(cache,123,directory)$reused)
  cache$daily$numeric_value[1]<-.2
  testthat::expect_false(read_or_build_acis_monthly_climatology(cache,123,directory)$reused)
})

testthat::test_that("full record includes outside-baseline history but not unfinished or future months",{
  cache<-monthly_fixture()
  extra<-cache$daily[format(cache$daily$date,"%Y-%m")=="2020-01",]
  extra$date<-as.Date(paste0("1980",format(extra$date,"-%m-%d")))
  extra$numeric_value[extra$variable=="pcpn"]<-2
  cache$daily<-rbind(cache$daily,extra)
  baseline<-acis_station_monthly_climatology(cache,123)
  full<-acis_station_monthly_climatology(cache,123,period="record")
  testthat::expect_equal(baseline$monthly$precipitation_years[1],30L)
  testthat::expect_equal(full$monthly$precipitation_years[1],31L)
  testthat::expect_equal(full$monthly$precip_max[1],62)
  testthat::expect_equal(full$monthly$precip_max_years[1],"1980")
  testthat::expect_equal(full$monthly$precip_first_year[1],1980L)
  testthat::expect_identical(baseline$baseline,"1991\u20132020")
  testthat::expect_identical(full$baseline,"Full available record (1980\u20132020)")
  testthat::expect_match(full$baseline,"1980")
  late<-extra;late$date<-as.Date(paste0("2021",format(late$date,"-%m-%d")))
  cache$daily<-rbind(cache$daily,late)
  not_finished<-acis_station_monthly_climatology(cache,123,period="record",as_of="2021-01-30")
  finished<-acis_station_monthly_climatology(cache,123,period="record",as_of="2021-01-31")
  testthat::expect_equal(not_finished$monthly$temperature_years[1],31L)
  testthat::expect_equal(finished$monthly$temperature_years[1],32L)
  testthat::expect_equal(not_finished$last_complete_month,"2020-12")
  testthat::expect_equal(finished$last_complete_month,"2021-01")
  directory<-tempfile("record-reference-");on.exit(unlink(directory,recursive=TRUE),add=TRUE)
  testthat::expect_false(read_or_build_acis_monthly_climatology(cache,123,directory,period="record",as_of="2021-01-30")$reused)
  testthat::expect_false(read_or_build_acis_monthly_climatology(cache,123,directory,period="reference")$reused)
  testthat::expect_true(read_or_build_acis_monthly_climatology(cache,123,directory,period="record",as_of="2021-01-29")$reused)
  testthat::expect_false(read_or_build_acis_monthly_climatology(cache,123,directory,period="record",as_of="2021-01-31")$reused)
})

testthat::test_that("publication validation requires both periods, correct dates and supported ordered values",{
  directory<-tempfile("monthly-validate-");on.exit(unlink(directory,recursive=TRUE),add=TRUE)
  ref<-prepare_acis_station_monthly_reference(monthly_fixture(),123,"2026-11-03",directory)$reference
  detail<-list(uid=123L,as_of="2026-11-03",monthly_climatology=ref)
  testthat::expect_invisible(validate_acis_station_monthly_detail(detail,123,"2026-11-03"))
  parsed<-jsonlite::fromJSON(jsonlite::toJSON(detail,auto_unbox=TRUE,dataframe="rows",na="null",null="null"))
  testthat::expect_invisible(validate_acis_station_monthly_detail(parsed,123,"2026-11-03"))
  bad<-detail;bad$monthly_climatology$full_record<-NULL
  testthat::expect_error(validate_acis_station_monthly_detail(bad,123,"2026-11-03"),"monthly climatology")
  bad<-detail;bad$monthly_climatology$snapshot_date<-"2026-11-02"
  testthat::expect_error(validate_acis_station_monthly_detail(bad,123,"2026-11-03"),"stale")
  bad<-detail;bad$monthly_climatology$monthly$precip_median[1]<-999
  testthat::expect_error(validate_acis_station_monthly_detail(bad,123,"2026-11-03"),"invalid")
  bad<-detail;bad$monthly_climatology$full_record$last_complete_month<-"2026-11"
  testthat::expect_error(validate_acis_station_monthly_detail(bad,123,"2026-11-03"),"invalid")
  bad<-detail;bad$monthly_climatology$full_record$monthly$temperature_years<-NULL
  testthat::expect_error(validate_acis_station_monthly_detail(bad,123,"2026-11-03"),"invalid")
})
