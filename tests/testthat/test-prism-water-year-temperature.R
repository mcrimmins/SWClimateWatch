make_wy_temperature_fixture <- function() {
  root <- tempfile("wy-temperature-");dir.create(root)
  dates <- as.Date(c("2018-10-01","2018-10-02","2018-10-03",
    "2019-10-01","2019-10-02","2019-10-03"))
  rows <- list()
  for(v in c("maxt","mint")) for(i in seq_along(dates)) {
    r <- terra::rast(nrows=1,ncols=1,xmin=-112,xmax=-111.95,ymin=33,ymax=33.05,crs="EPSG:4326")
    terra::values(r) <- c(5,7,9,15,17,19)[i]+if(v=="maxt") 5 else -5
    terra::time(r)<-dates[i]
    path<-file.path(root,paste0(v,"-",dates[i],".tif"));terra::writeRaster(r,path)
    rows[[length(rows)+1L]]<-data.frame(product="daily",aoi_id=swc_prism$aoi_id,variable=v,
      native_units=unname(swc_prism$native_units[[v]]),start_date=dates[i],end_date=dates[i],
      processed_at="2026-11-10 00:00:00 UTC",md5=unname(tools::md5sum(path)),path=path)
  }
  list(root=root,manifest=do.call(rbind,rows))
}

testthat::test_that("water-year temperature cache increments, reuses and detects revisions", {
  f<-make_wy_temperature_fixture();on.exit(unlink(f$root,recursive=TRUE),add=TRUE)
  build<-function(date,increment=TRUE) build_prism_water_year_temperature_cache(date,
    "2019-01-01","2020-12-31",processed_dir=f$root,processed_manifest=f$manifest,
    allow_incremental=increment,quiet=TRUE)
  first<-build("2026-10-01")
  testthat::expect_equal(first$build_method,"direct")
  second<-build("2026-10-02")
  testthat::expect_equal(second$build_method,"incremental")
  testthat::expect_equal(as.numeric(terra::values(second$raster)),c(6,16))
  testthat::expect_equal(build("2026-10-02")$build_method,"reuse")
  third<-build("2026-10-03")
  testthat::expect_equal(third$build_method,"incremental")
  testthat::expect_equal(as.numeric(terra::values(third$raster)),c(7,17))
  direct<-build("2026-10-03",FALSE)
  testthat::expect_equal(as.numeric(terra::values(direct$raster)),as.numeric(terra::values(third$raster)))
  build("2026-10-01",FALSE)
  gap<-build("2026-10-03")
  testthat::expect_equal(gap$build_method,"incremental")
  testthat::expect_equal(as.numeric(terra::values(gap$raster)),c(7,17))
  # Revise an already-used day, then request a later cutoff: stale sums must not increment.
  build("2026-10-02",FALSE)
  row<-which(f$manifest$variable=="maxt" & f$manifest$start_date==as.Date("2018-10-01"))
  path<-f$manifest$path[row];r<-terra::rast(path);terra::values(r)<-14
  terra::writeRaster(r,path,overwrite=TRUE);f$manifest$md5[row]<-unname(tools::md5sum(path))
  revised<-build("2026-10-03")
  testthat::expect_equal(revised$build_method,"direct")
  testthat::expect_equal(as.numeric(terra::values(revised$raster)),c(23/3,17),tolerance=1e-8)
  # October 1 resets, even when a later calendar cutoff was cached.
  testthat::expect_equal(build("2027-10-01")$build_method,"direct")
  missing<-f$manifest[f$manifest$variable!="mint",]
  testthat::expect_error(prism_wy_temperature_daily(as.Date("2018-10-01"),swc_prism$aoi_id,missing),"No processed PRISM source")
})

testthat::test_that("February 29 interpolates means rather than unequal-duration sums", {
  root<-tempfile("temperature-leap-");dir.create(root)
  on.exit(unlink(root,recursive=TRUE),add=TRUE)
  env<-new.env(parent=environment(build_prism_water_year_temperature_cache))
  env$prism_wy_temperature_signature<-function(...) "fixture"
  env$prism_wy_temperature_sum<-function(dates,...) {
    r<-terra::rast(nrows=1,ncols=1)
    terra::values(r)<-length(dates)*if(format(tail(dates,1),"%m-%d")=="03-01") 30 else 10
    r
  }
  build<-build_prism_water_year_temperature_cache;environment(build)<-env
  leap<-build("2028-02-29","2019-01-01","2020-12-31",processed_dir=root,
    processed_manifest=data.frame(),quiet=TRUE)
  testthat::expect_equal(as.numeric(terra::values(leap$raster)),c(20,20))
  march<-build("2028-03-01","2019-01-01","2020-12-31",processed_dir=root,
    processed_manifest=data.frame(),quiet=TRUE)
  testthat::expect_equal(march$build_method,"direct")
  testthat::expect_equal(as.numeric(terra::values(march$raster)),c(30,30))
})

testthat::test_that("temperature comparisons preserve units, direction, ties and missing values", {
  r<-terra::rast(nrows=1,ncols=2);terra::values(r)<-c(20,20)
  a<-r;b<-r;terra::values(a)<-c(10,10);terra::values(b)<-c(20,NA)
  out<-prism_water_year_temperature_comparisons(r,c(a,b),as.Date("2026-11-09"))
  testthat::expect_equal(unname(terra::values(out$departure)[1,1]),5)
  testthat::expect_true(is.na(terra::values(out$departure)[2,1]))
  testthat::expect_equal(unname(terra::values(out$percentile)[1,1]),prism_type8_percentile_rank(20,c(10,20)))
  testthat::expect_true(is.na(terra::values(out$percentile)[2,1]))
  periods<-prism_water_year_reference_periods("2028-02-29","2019-01-01","2020-12-31")
  testthat::expect_equal(prism_wy_temperature_days(periods),c(151.5,152))
})
