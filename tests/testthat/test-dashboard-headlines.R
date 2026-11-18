testthat::test_that("headline configuration selects independent supported enabled maps", {
  path <- file.path(project_root,"config","map-products.yml")
  config <- yaml::read_yaml(path)$dashboard$headlines
  products <- read_map_product_config(path)
  cards <- map_dashboard_validate_headlines(config,products)
  testthat::expect_identical(names(cards$cards),c("pcpn_percentile_07day","pcpn_percentile_90day","tmean_departure_30day"))
  testthat::expect_equal(cards$cards[[1]]$lower_percentile,33)
  testthat::expect_equal(cards$cards[[1]]$upper_percentile,67)
  bad <- config; bad$cards[[1]]$product <- "pcpn_total_07day"
  testthat::expect_error(map_dashboard_validate_headlines(bad,products),"Unsupported")
  bad <- config; bad$cards[[2]]$product <- bad$cards[[1]]$product
  testthat::expect_error(map_dashboard_validate_headlines(bad,products),"unique")
  bad <- config; bad$cards[[1]]$lower_percentile <- 99
  testthat::expect_error(map_dashboard_validate_headlines(bad,products),"ordered")
  testthat::expect_false(map_dashboard_validate_headlines(list(enabled=FALSE),products)$enabled)
})

testthat::test_that("headlines distinguish mixed, neutral and widespread conditions", {
  settings <- list(mixed_area_percent=25,highlight_area_percent=50,strong_area_percent=67)
  summary <- list(type="percentile",settings=settings,values=c(area_below_percentile=35,area_above_percentile=28))
  testthat::expect_identical(map_dashboard_headline_tone(summary),"mixed")
  summary$values <- c(area_below_percentile=20,area_above_percentile=40)
  testthat::expect_identical(map_dashboard_headline_tone(summary),"neutral")
  summary$values <- c(area_below_percentile=10,area_above_percentile=60)
  testthat::expect_identical(map_dashboard_headline_tone(summary),"wet")
  summary$values <- c(area_below_percentile=75,area_above_percentile=5)
  testthat::expect_identical(map_dashboard_headline_tone(summary),"dry headline-strong")
  summary$values[] <- NA_real_
  testthat::expect_identical(map_dashboard_headline_tone(summary),"neutral")
  summary$type <- "temperature"; summary$values <- c(regional_mean=4)
  testthat::expect_identical(map_dashboard_headline_tone(summary),"warm headline-strong")
})

testthat::test_that("headline cache preserves per-map thresholds and handles missing grids", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root,recursive=TRUE),add=TRUE)
  dashboard <- read_map_dashboard_config(file.path(project_root,"config","map-products.yml"))
  file <- file.path(root,"data","processed","prism","az-nm-pad050","daily","percentile-rank","pcpn","07day","2026-10-05.tif")
  dir.create(dirname(file),recursive=TRUE)
  raster <- terra::rast(nrows=1,ncols=3,xmin=-110,xmax=-108,ymin=34,ymax=35,crs="EPSG:4326")
  terra::values(raster) <- c(20,50,80); terra::writeRaster(raster,file)
  dates <- c(Precipitation="2026-10-05",Temperature="2026-10-04")
  result <- map_dashboard_headlines(dates,root,dashboard,weights_function=function(r) c(1,1,1))
  testthat::expect_equal(unname(result$pcpn_percentile_07day$values),c(100/3,100/3))
  testthat::expect_identical(result,map_dashboard_headlines(dates,root,dashboard))
  testthat::expect_true(file.exists(file.path(root,"data","processed","dashboard","headline-summaries.rds")))
  testthat::expect_equal(attr(dashboard,"summary_config")$summaries$pcpn_percentile_90day$lower_percentile,10)
  text <- paste(map_dashboard_headline_text(result),collapse="\n")
  testthat::expect_match(text,"pcpn_percentile_07day.qmd")
  testthat::expect_match(text,"below normal")
  testthat::expect_match(text,"Summary unavailable")
  testthat::expect_match(text,"Through Oct 05, 2026")
  attr(dashboard,"summary_config")$headlines$enabled <- FALSE
  testthat::expect_length(map_dashboard_headlines(dates,root,dashboard),0)
})
