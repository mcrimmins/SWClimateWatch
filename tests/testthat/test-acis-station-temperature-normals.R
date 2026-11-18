source(file.path(project_root,"R","acis-station-temperature-normals.R"))
temperature_normal_fixture <- function() {
  dates<-seq(as.Date("1991-01-01"),as.Date("2020-12-31"),by="day")
  high<-ifelse(as.integer(format(dates,"%Y"))<=2005L,80,90)
  low<-high-30
  list(uid=1L,as_of=as.Date("2026-11-03"),daily=rbind(
    data.frame(date=dates,variable="maxt",numeric_value=high,observed=TRUE,flag=""),
    data.frame(date=dates,variable="mint",numeric_value=low,observed=TRUE,flag="")))
}

testthat::test_that("normal high and low share paired years and enforce sample support", {
  cache<-temperature_normal_fixture()
  ref<-acis_station_temperature_normals(cache,smoothing_days=1L)
  testthat::expect_equal(nrow(ref$daily),366L)
  testthat::expect_true(all(ref$daily$normal_maxt==85))
  testthat::expect_true(all(ref$daily$normal_mint==55))
  testthat::expect_true(all(ref$daily$normal_years==30L))
  testthat::expect_false(ref$official_normals)
  i<-cache$daily$variable=="maxt" & format(cache$daily$date,"%m-%d")=="01-01" &
    as.integer(format(cache$daily$date,"%Y"))<=2000L
  cache$daily$flag[i]<-"S"
  ref<-acis_station_temperature_normals(cache,smoothing_days=1L)$daily
  jan<-ref[ref$month_day=="01-01",]
  testthat::expect_equal(jan$normal_years,20L)
  testthat::expect_equal(jan$normal_maxt,87.5)
  testthat::expect_equal(jan$normal_mint,57.5)
  cache$daily$numeric_value[cache$daily$variable=="maxt" & cache$daily$date==as.Date("2001-01-01")]<-0
  ref<-acis_station_temperature_normals(cache,smoothing_days=15L)$daily
  testthat::expect_true(is.na(ref$normal_maxt[ref$month_day=="01-01"]))
  testthat::expect_true(is.na(ref$normal_mint[ref$month_day=="01-08"]))
  testthat::expect_equal(ref$normal_maxt[ref$month_day=="01-09"],85)
  testthat::expect_true(is.na(ref$normal_maxt[ref$month_day=="12-31"]))
})

testthat::test_that("leap-day references interpolate adjacent normals without sparse leap sampling", {
  cache<-temperature_normal_fixture();md<-format(cache$daily$date,"%m-%d")
  for(variable in c("maxt","mint")) {
    offset<-if(variable=="maxt") 0 else -30
    cache$daily$numeric_value[cache$daily$variable==variable & md=="02-28"]<-100+offset
    cache$daily$numeric_value[cache$daily$variable==variable & md=="03-01"]<-120+offset
    cache$daily$numeric_value[cache$daily$variable==variable & md=="02-29"]<-140+offset
  }
  ref<-acis_station_temperature_normals(cache,smoothing_days=1L)$daily
  feb<-ref[ref$month_day=="02-29",]
  testthat::expect_equal(feb$normal_maxt,110)
  testthat::expect_equal(feb$normal_mint,80)
  testthat::expect_equal(feb$normal_years,30L)
  testthat::expect_error(acis_station_temperature_normals(cache,smoothing_days=14L))
})

testthat::test_that("normal caches ignore current updates and detect baseline revisions", {
  root<-tempfile("normal-cache-");dir.create(root)
  on.exit(unlink(root,recursive=TRUE),add=TRUE)
  cache<-temperature_normal_fixture()
  first<-read_or_build_acis_temperature_normals(cache,1L,root)
  testthat::expect_false(first$reused)
  testthat::expect_true(read_or_build_acis_temperature_normals(cache,1L,root)$reused)
  cache$daily<-rbind(cache$daily,data.frame(date=as.Date("2026-11-03"),variable="maxt",
    numeric_value=95,observed=TRUE,flag=""))
  testthat::expect_true(read_or_build_acis_temperature_normals(cache,1L,root)$reused)
  cache$daily$numeric_value[1]<-100
  testthat::expect_false(read_or_build_acis_temperature_normals(cache,1L,root)$reused)
  detail<-list(uid=1L,daily=data.frame(date=c("2026-01-01","2028-02-29"),maxt=c(90,100)))
  merged<-acis_attach_temperature_normals(detail,first$reference)
  testthat::expect_equal(merged$daily$normal_maxt,c(85,85))
  testthat::expect_equal(merged$daily$maxt,c(90,100))
  testthat::expect_false(merged$temperature_reference$official_normals)
  empty<-acis_station_temperature_normals(NULL)
  testthat::expect_true(all(is.na(empty$daily$normal_maxt)))
})
