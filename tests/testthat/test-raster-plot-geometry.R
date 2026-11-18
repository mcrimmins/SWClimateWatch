source(file.path(project_root,"R/map-southwest.R"))

testthat::test_that("sparse and singleton cells keep their native bounds and missing gaps", {
  r <- terra::rast(nrows=4,ncols=6,xmin=10,xmax=22,ymin=30,ymax=34,crs="EPSG:4326")
  for(cells in list(c(1L,3L,13L,15L),c(1L,2L,5L,19L),8L,integer())) {
    values <- rep(NA_real_,terra::ncell(r));values[cells] <- seq_along(cells)-1
    terra::values(r) <- values
    data <- terra::as.data.frame(r,xy=TRUE,na.rm=TRUE);names(data)[3L] <- "value"
    plot <- ggplot2::ggplot()+southwest_raster_layer(data,ggplot2::aes(x,y,fill=value),terra::res(r))
    testthat::expect_warning(built <- ggplot2::ggplot_build(plot),NA)
    testthat::expect_s3_class(plot$layers[[1]]$geom,"GeomTile")
    layer <- built$data[[1]]
    testthat::expect_equal(nrow(layer),length(cells))
    if(length(cells)) {
      testthat::expect_equal(layer$xmax-layer$xmin,rep(2,length(cells)))
      testthat::expect_equal(layer$ymax-layer$ymin,rep(1,length(cells)))
      testthat::expect_equal(layer$x,data$x);testthat::expect_equal(layer$y,data$y)
      testthat::expect_equal(data$value,seq_along(cells)-1)
    }
    testthat::expect_equal(is.na(terra::values(r,mat=FALSE)),is.na(values))
  }
})

testthat::test_that("dense native grids retain the raster fast path despite floating roundoff", {
  data <- expand.grid(x=-115+(0:8)*.04166666666667,y=30+(0:7)*.04166666666667)
  data$value <- seq_len(nrow(data))
  plot <- ggplot2::ggplot()+southwest_raster_layer(data,ggplot2::aes(x,y,fill=value),c(1/24,1/24))
  testthat::expect_identical(southwest_raster_geometry(data,c(1/24,1/24))$engine,"raster")
  testthat::expect_s3_class(plot$layers[[1]]$geom,"GeomRaster")
  testthat::expect_warning(ggplot2::ggplot_build(plot),NA)
})

testthat::test_that("categorical sparse cells keep category values and native dimensions", {
  data <- data.frame(x=c(1000,5000),y=c(2000,6000),category=factor(c("low","high")))
  plot <- ggplot2::ggplot()+southwest_raster_layer(data,ggplot2::aes(x,y,fill=category),c(1000,2000))
  testthat::expect_warning(layer <- ggplot2::layer_data(plot),NA)
  testthat::expect_equal(layer$xmax-layer$xmin,c(1000,1000))
  testthat::expect_equal(layer$ymax-layer$ymin,c(2000,2000))
  testthat::expect_identical(plot$layers[[1]]$data$category,data$category)
})
