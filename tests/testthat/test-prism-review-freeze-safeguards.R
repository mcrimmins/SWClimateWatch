review_freeze_raster <- function(values,dates=seq(as.Date('1991-08-01'),by='year',length.out=length(values))) {
  r <- terra::rast(nrows=1,ncols=1,nlyrs=length(values),xmin=-112,xmax=-111.95,ymin=33,ymax=33.05,crs='EPSG:4326')
  terra::values(r) <- matrix(values,nrow=1); terra::time(r) <- dates; r
}
testthat::test_that('no-freeze and missing seasons remain distinct in sample caches', {
  dates <- seq(as.Date('2026-08-01'),by='day',length.out=3)
  warm <- review_freeze_raster(c(40,40,40),dates)
  missing <- review_freeze_raster(c(40,NA,40),dates)
  testthat::expect_equal(as.numeric(terra::values(prism_first_freeze_from_raster(warm,dates[1],preserve_no_freeze=TRUE))),0)
  testthat::expect_equal(as.numeric(terra::values(prism_last_freeze_from_raster(warm,dates[1],preserve_no_freeze=TRUE))),0)
  testthat::expect_true(is.na(as.numeric(terra::values(prism_first_freeze_from_raster(missing,dates[1],preserve_no_freeze=TRUE)))))
  testthat::expect_true(is.na(as.numeric(terra::values(prism_last_freeze_from_raster(missing,dates[1],preserve_no_freeze=TRUE)))))
  one <- terra::rast(nrows=1,ncols=4,xmin=-112,xmax=-111.8,ymin=33,ymax=33.05,crs='EPSG:4326')
  terra::values(one) <- c(40,31,NA,Inf); terra::time(one) <- as.Date('2026-08-01')
  testthat::expect_equal(as.numeric(terra::values(prism_first_freeze_from_raster(one,as.Date('2026-08-01'),preserve_no_freeze=TRUE))),c(0,1,NA,NA))
  testthat::expect_equal(as.numeric(terra::values(prism_last_freeze_from_raster(one,as.Date('2026-08-01'),preserve_no_freeze=TRUE))),c(0,1,NA,NA))
})
testthat::test_that('freeze medians include censored seasons and never reinterpret missing data', {
  x <- review_freeze_raster(c(1:24,rep(0,6)))
  first <- prism_first_freeze_climatology(x)
  last <- prism_last_freeze_climatology(x)
  testthat::expect_equal(as.numeric(terra::values(first$median_day)),15.5)
  testthat::expect_equal(as.numeric(terra::values(last$median_day)),9.5)
  testthat::expect_equal(as.numeric(terra::values(first$frequency)),.8)
  terra::values(x)[1,30] <- NA
  testthat::expect_true(is.na(as.numeric(terra::values(prism_first_freeze_climatology(x)$median_day))))
  testthat::expect_true(is.na(as.numeric(terra::values(prism_last_freeze_climatology(x)$median_day))))
})
testthat::test_that('freeze-free bounds identify a median only when justified', {
  x <- review_freeze_raster(c(160,180,200,-300))
  testthat::expect_equal(as.numeric(terra::values(prism_freeze_free_climatology(x,.75)$median_length)),190)
  terra::values(x)[1,4] <- -100
  testthat::expect_true(is.na(as.numeric(terra::values(prism_freeze_free_climatology(x,.75)$median_length))))
  v <- rep(40,365); v[300] <- 30
  testthat::expect_equal(prism_freeze_free_length_index(v,1:212,213:365,preserve_censoring=TRUE),-300)
  v <- rep(40,365); v[100] <- 30
  testthat::expect_equal(prism_freeze_free_length_index(v,1:212,213:365,preserve_censoring=TRUE),-266)
  v[2] <- NA
  testthat::expect_true(is.na(prism_freeze_free_length_index(v,1:212,213:365,preserve_censoring=TRUE)))
})
testthat::test_that('overdue first freezes have separate lower-bound evidence, not invented event dates', {
  observed <- review_freeze_raster(0); normal <- review_freeze_raster(93)
  bound <- prism_first_freeze_late_bound(observed,normal,'2026-12-01')
  testthat::expect_equal(as.numeric(terra::values(bound)),30)
  testthat::expect_true(is.na(as.numeric(terra::values(prism_first_freeze_departure_raster(observed,normal,'2026-12-01')))))
  missing <- observed*NA
  testthat::expect_true(is.na(as.numeric(terra::values(prism_first_freeze_late_bound(missing,normal,'2026-12-01')))))
  testthat::expect_true(prism_first_freeze_publishable('2026-12-01',missing,normal,late_bound=bound))
  testthat::expect_false(prism_first_freeze_publishable('2026-12-01',missing,normal))
})
testthat::test_that('spring last-freeze departures wait for both safeguards and remain provisional', {
  observed <- review_freeze_raster(200); normal <- review_freeze_raster(258)
  testthat::expect_true(is.na(as.numeric(terra::values(prism_last_freeze_departure_raster(observed,normal,'2027-03-15')))))
  terra::values(observed) <- 270
  testthat::expect_true(is.na(as.numeric(terra::values(prism_last_freeze_departure_raster(observed,normal,'2027-04-30')))))
  terra::values(observed) <- 250
  testthat::expect_equal(as.numeric(terra::values(prism_last_freeze_departure_raster(observed,normal,'2027-04-30'))),-8)
  terra::values(observed) <- 365
  testthat::expect_equal(as.numeric(terra::values(prism_last_freeze_departure_raster(observed,normal,'2027-07-31'))),107)
})
testthat::test_that('freeze calendar classes put month boundaries in their labeled intervals', {
  first <- map_product_categorical_classes('mint_first_freeze_date',c(32,93,154,213,365),c(1,365))
  last <- map_product_categorical_classes('mint_last_freeze_date',c(93,154,213,274,365),c(1,365))
  testthat::expect_equal(as.character(cut(c(31,32,92,93),first$breaks,labels=first$labels,include.lowest=TRUE)),c('August','Sep-Oct','Sep-Oct','Nov-Dec'))
  testthat::expect_equal(as.character(cut(c(273,274),last$breaks,labels=last$labels,include.lowest=TRUE)),c('Mar-Apr','May-Jul'))
  testthat::expect_equal(prism_freeze_plot_day_index(c(213,214,366),'2015-08-01'),c(212,213,365))
  testthat::expect_equal(prism_freeze_plot_day_index(c(212,213,365),'2016-08-01'),c(212,213,365))
})
testthat::test_that('reference text follows configured years and centered window', {
  config <- swc_prism; config$percentile_start <- as.Date('1981-01-01'); config$percentile_end <- as.Date('2010-12-31'); config$centered_window_days <- 7L
  testthat::expect_equal(prism_reference_baseline_label('percentile',config=config),'1981-2010 | centered 7-day baseline')
  testthat::expect_equal(prism_reference_baseline_label('normal',centered=FALSE,config=config),'1991-2020')
})

testthat::test_that('first-freeze calculation persists separate overdue bounds and missing coverage', {
  root <- tempfile(); on.exit(unlink(root,recursive=TRUE),add=TRUE)
  ranges <- list(seq(as.Date('1991-08-01'),as.Date('1992-07-31'),by='day'),seq(as.Date('2026-08-01'),as.Date('2026-12-01'),by='day'))
  paths <- file.path(root,paste0('source',1:2,'.tif')); dir.create(root)
  for(i in 1:2) {
    dates <- ranges[[i]]; r <- terra::rast(nrows=1,ncols=3,nlyrs=length(dates),xmin=-112,xmax=-111.85,ymin=33,ymax=33.05,crs='EPSG:4326')
    values <- matrix(40,nrow=3,ncol=length(dates)); values[3,1] <- NA
    if(i==1) values[1,93] <- 30
    terra::values(r) <- values; terra::time(r) <- dates; terra::writeRaster(r,paths[i],overwrite=TRUE)
  }
  manifest <- data.frame(product='daily',aoi_id=swc_prism$aoi_id,variable='mint',native_units='degreeF',
    start_date=as.Date(c('1991-08-01','2026-08-01')),end_date=as.Date(c('1992-07-31','2026-12-01')),
    processed_at='2026-01-01 00:00:00 UTC',md5=unname(tools::md5sum(paths)),path=paths)
  result <- calculate_prism_first_freeze_products(date=as.Date('2026-12-01'),baseline_start='1991-01-01',baseline_end='1991-12-31',
    processed_dir=root,processed_manifest=manifest,quiet=TRUE)
  testthat::expect_equal(as.numeric(terra::values(result$departure_lower_bound)),c(30,NA,NA))
  testthat::expect_true(all(is.na(terra::values(result$departure))))
  testthat::expect_equal(as.numeric(terra::values(terra::rast(result$paths[['late-lower-bound']]))),c(30,NA,NA))
  testthat::expect_equal(as.Date(terra::time(terra::rast(result$paths[['late-lower-bound']]))),as.Date('2026-12-01'))
  testthat::expect_true(result$publishable)
})

testthat::test_that('freeze map cells and status overlays retain exact spatial footprints', {
  r <- terra::rast(nrows=2,ncols=4,xmin=-113,xmax=-109,ymin=33,ymax=35,crs='EPSG:4326')
  terra::values(r) <- rep(c(-20,NA,NA,10),2)
  status <- r; terra::values(status) <- rep(c(NA,30,NA,NA),2)
  p <- build_prism_first_freeze_map(r,'departure',date=as.Date('2026-12-01'),status_raster=status)
  layers <- ggplot2::ggplot_build(p)$data
  testthat::expect_equal(unique(layers[[1]]$xmax-layers[[1]]$xmin),terra::res(r)[1])
  testthat::expect_equal(unique(layers[[2]]$xmax-layers[[2]]$xmin),terra::res(r)[1])
  testthat::expect_equal(nrow(layers[[2]]),2L)
})
