testthat::test_that('regional map metrics use area weights and coverage guards', {
  w <- c(1,3,0)
  settings <- list(threshold_inches=.1,lower_percentile=10,upper_percentile=90)
  testthat::expect_equal(map_dashboard_regional_value(c(.1,0,5),w,'area_above_threshold',settings),25)
  testthat::expect_equal(map_dashboard_regional_value(c(2,-2,100),w,'regional_mean'),-1)
  testthat::expect_equal(map_dashboard_regional_value(c(9,90,100),w,'area_below_percentile',settings),25)
  testthat::expect_equal(map_dashboard_regional_value(c(90,91,100),w,'area_above_percentile',settings),75)
  testthat::expect_true(is.na(map_dashboard_regional_value(c(1,NA,0),w,'regional_mean')))
  testthat::expect_true(is.na(map_dashboard_regional_value(c(1,2,3),c(0,0,0),'regional_mean')))
})

testthat::test_that('YAML validates map-specific metrics, toggles, groups and thresholds', {
  config <- yaml::read_yaml(file.path(project_root,'config','map-products.yml'))
  products <- read_map_product_config(file.path(project_root,'config','map-products.yml'))
  ids <- unlist(config$dashboard$products,use.names=FALSE)
  validate <- function(x) map_dashboard_validate_summaries(x,products,ids)
  testthat::expect_identical(validate(config$dashboard)$layout,'per_map')
  bad <- config$dashboard; bad$summaries$tmean_departure_30day$metrics <- 'area_above_threshold'
  testthat::expect_error(validate(bad),'Incompatible')
  bad <- config$dashboard; bad$summaries$pcpn_percentile_30day$lower_percentile <- 95
  testthat::expect_error(validate(bad),'ordered')
  bad <- config$dashboard; bad$summaries$pcpn_total_07day$threshold_inches <- -1
  testthat::expect_error(validate(bad),'threshold')
  bad <- config$dashboard; bad$summary_layout <- 'top_cards'
  testthat::expect_error(validate(bad),'per_map or none')
  bad <- config$dashboard; bad$groups[[1]]$products <- rev(bad$groups[[1]]$products)
  testthat::expect_error(validate(bad),'display order')
  off <- config$dashboard; off$summaries$tmean_departure_30day$enabled <- FALSE
  testthat::expect_false(validate(off)$summaries$tmean_departure_30day$enabled)
})

testthat::test_that('summary output is inside its map card and not attached to substituted snow', {
  dashboard <- read_map_dashboard_config(file.path(project_root,'config','map-products.yml'))
  settings <- attr(dashboard,'summary_config')$summaries
  spec <- map_dashboard_summary_spec('pcpn_percentile_30day')
  summaries <- list(pcpn_percentile_30day=list(type=spec$type,values=c(area_below_percentile=25,area_above_percentile=5),
    date='2026-10-05',label='Past 30 days',settings=settings$pcpn_percentile_30day))
  page <- map_dashboard_page_text(dashboard,roni=NULL,summaries=summaries)
  testthat::expect_true(any(grepl('Very dry: 25%',page,fixed=TRUE)))
  testthat::expect_true(any(grepl('Very wet: 5%',page,fixed=TRUE)))
  testthat::expect_true(any(grepl('through 2026-10-05',page,fixed=TRUE)))
  summary_line <- which(grepl('Very dry: 25%',page,fixed=TRUE))
  image_line <- which(grepl('pcpn-percentile-rank-30day-latest.png',page,fixed=TRUE))[1]
  testthat::expect_lt(summary_line,image_line)
  testthat::expect_gt(summary_line,which(page=='::: {.dashboard-map-card}')[2])
  testthat::expect_false(any(grepl('dashboard-tool-link',page,fixed=TRUE)))
  missing <- summaries[[1]]; missing$values[] <- NA_real_
  testthat::expect_match(map_dashboard_summary_text(missing),'unavailable')
  snow <- list(available=TRUE,date='2026-02-15',image='snow.png',page='snow.qmd')
  dry <- summaries[[1]]; dry$label <- 'DRY SUMMARY MUST BE HIDDEN'
  summaries$pcpn_current_dry_spell_percentile <- dry
  winter <- map_dashboard_page_text(dashboard,snow=snow,roni=NULL,summaries=summaries)
  testthat::expect_false(any(grepl('DRY SUMMARY MUST BE HIDDEN',winter,fixed=TRUE)))
  attr(dashboard,'summary_config')$layout <- 'none'
  off <- map_dashboard_page_text(dashboard,roni=NULL,summaries=summaries)
  testthat::expect_false(any(grepl('Very dry: 25%',off,fixed=TRUE)))
})

testthat::test_that('summary cache follows input revisions, missing grids and config edits', {
  root <- tempfile(); dir.create(root); on.exit(unlink(root,recursive=TRUE),add=TRUE)
  dashboard <- read_map_dashboard_config(file.path(project_root,'config','map-products.yml'))
  base <- file.path(root,'data','processed','prism','az-nm-pad050','daily')
  path <- file.path(base,'accumulation','pcpn','07day','2026-10-05.tif')
  dir.create(dirname(path),recursive=TRUE)
  r <- terra::rast(nrows=1,ncols=2,xmin=-110,xmax=-108,ymin=34,ymax=35,crs='EPSG:4326')
  terra::values(r) <- c(.1,0); terra::writeRaster(r,path)
  dates <- c(Precipitation='2026-10-05',Temperature='2026-10-05')
  run <- function() map_dashboard_summaries(dates,root,weights_function=function(r) c(1,1),dashboard=dashboard)
  x <- run()
  testthat::expect_equal(x$pcpn_total_07day$values[['area_above_threshold']],50)
  testthat::expect_true(all(is.na(x$pcpn_percentile_30day$values)))
  cached <- map_dashboard_summaries(dates,root,dashboard=dashboard)
  testthat::expect_identical(x,cached)
  attr(dashboard,'summary_config')$summaries$pcpn_total_07day$threshold_inches <- .2
  testthat::expect_equal(run()$pcpn_total_07day$values[['area_above_threshold']],0)
  terra::values(r) <- c(.3,.3); terra::writeRaster(r,path,overwrite=TRUE)
  testthat::expect_equal(run()$pcpn_total_07day$values[['area_above_threshold']],100)
  unlink(path)
  z <- map_dashboard_summaries(dates,root,dashboard=dashboard)
  testthat::expect_true(all(is.na(z$pcpn_total_07day$values)))
})

testthat::test_that('compact chips highlight each tail independently without calling rainfall rare', {
  summary <- list(type='percentile',label='Past 30 days',date='2026-10-05',
    settings=list(lower_percentile=10,upper_percentile=90,highlight_area_percent=10,strong_area_percent=25),
    values=c(area_below_percentile=5,area_above_percentile=68))
  text <- map_dashboard_summary_text(summary)
  testthat::expect_match(text,'summary-neutral[^>]*>Very dry: 5%')
  testthat::expect_match(text,'summary-wet summary-strong')
  testthat::expect_match(text,'Area above percentile 90; through 2026-10-05')
  summary$values <- c(area_below_percentile=25,area_above_percentile=15)
  text <- map_dashboard_summary_text(summary)
  testthat::expect_match(text,'summary-dry summary-strong')
  testthat::expect_match(text,'summary-wet"')
  summary$type <- 'precipitation'; summary$values <- c(regional_mean=10)
  testthat::expect_false(grepl('summary-strong',map_dashboard_summary_text(summary)))
  summary$type <- 'temperature'; summary$values <- c(regional_mean=-4)
  testthat::expect_match(map_dashboard_summary_text(summary),'summary-cool summary-strong')
})
