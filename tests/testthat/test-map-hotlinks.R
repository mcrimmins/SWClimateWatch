source(file.path(project_root,"R/map-hotlinks.R"))

hotlink_fixture <- function(root) {
  dir.create(root,recursive=TRUE,showWarnings=FALSE)
  pngfile<-file.path(root,"sample.png")
  grDevices::png(pngfile,width=100,height=100)
  graphics::par(mar=rep(0,4));graphics::plot.new();graphics::rect(0,0,1,1,col="blue");grDevices::dev.off()
  png<-function(path){path<-file.path(root,path);dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE);file.copy(pngfile,path,overwrite=TRUE);path}
  json<-function(x,path){path<-file.path(root,path);dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE);jsonlite::write_json(x,path,auto_unbox=TRUE,dataframe="rows")}
  products<-data.frame(id=c("maxt_value","mint_value"),enabled=c(TRUE,FALSE),section="Temperature",label=c("Maximum temperature","Minimum temperature"),image=c("prism/temperature/maxt.png","prism/temperature/mint.png"))
  image<-png("maps/generated/prism/temperature/maxt.png")
  json(data.frame(page="temperature-values.html",product="maxt_value",image=products$image[1L],available=TRUE,md5=unname(tools::md5sum(image))),"assets/current-map-groups/manifest.json")
  jobs<-expand.grid(duration=c(1L,3L,6L,12L),family=c("temperature","precipitation","spi"),stringsAsFactors=FALSE)
  jobs$file<-sprintf("%s-%02dmonth.png",jobs$family,jobs$duration)
  version<-"2026-10-1111111111111111"
  for(file in jobs$file)png(paste0("maps/generated/prism/monthly/",version,"/",file))
  jobs$md5<-unname(tools::md5sum(pngfile))
  json(list(end_month="2026-10",products=jobs),paste0("maps/generated/prism/monthly/",version,"/manifest.json"))
  dir.create(file.path(root,"pages"),showWarnings=FALSE)
  writeLines(c('<div data-monthly-end="2026-10">',sprintf('<img data-monthly-map="%s-%d" src="../maps/generated/prism/monthly/%s/%s">',jobs$family,jobs$duration,version,jobs$file),'</div>'),file.path(root,"pages/monthly-climate.html"))
  png("maps/generated/prism/seasonal-archive/wy2024/cool_total.png")
  dir.create(file.path(root,"pages/archive"))
  writeLines('<img alt="Cool-season precipitation" src="../../maps/generated/prism/seasonal-archive/wy2024/cool_total.png">',file.path(root,"pages/archive/wy2024.html"))
  days<-lapply(c("2026-10-01","2026-10-02"),function(date){path<-paste0("maps/",date,"-tmean-departure.png");png(paste0("daily-explorer/",path));list(date=date,images=list(tmean_departure=path))})
  json(list(publication_mode=TRUE,circulation_enabled=TRUE,days=days),"daily-explorer/daily-data.json")
  weather<-lapply(c("2026-10-01","2026-10-02"),function(date){
    images<-setNames(lapply(c("height500","jet250","moisture"),function(field){path<-paste0("circulation/maps/",date,"-",field,".png");png(paste0("daily-explorer/",path));path}),c("height500","jet250","moisture"))
    list(date=date,status="available",images=images)
  })
  json(list(days=weather),"daily-explorer/circulation-manifest.json")
  metadata<-file.path(root,"metadata");dir.create(metadata)
  write.csv(data.frame(id="maxt_value",image_md5=unname(tools::md5sum(image)),actual_data_date="2026-10-02"),file.path(metadata,"map-product-status.csv"),row.names=FALSE)
  list(products=products,metadata=metadata,registry=file.path(root,"registry.rds"),json=json,png=png)
}

testthat::test_that("all published map families receive predictable latest or dated links", {
  root<-tempfile();on.exit(unlink(root,recursive=TRUE),add=TRUE);f<-hotlink_fixture(root)
  rows<-stage_map_hotlinks(root,"s3://bucket/climate/watch-staging/",f$products,f$metadata,f$registry)
  testthat::expect_true(all(c("Current Temperature","Current Snow","Monthly Climate","Daily Explorer dates","Weather map dates","Historic seasons","Synopsis supporting maps") %in% rows$family))
  testthat::expect_equal(sum(nzchar(rows$alias)),29L)
  monthly<-rows[rows$id=="monthly/temperature-12",]
  testthat::expect_equal(monthly$url,"https://cales.arizona.edu/climate/watch-staging/maps/latest/monthly/temperature-12month.png")
  testthat::expect_match(monthly$source_url,"2026-10-1111111111111111",fixed=TRUE)
  current<-rows[rows$id=="current/maxt_value",]
  testthat::expect_equal(current$date,"2026-10-02")
  latest<-rows[rows$id=="daily/latest/tmean_departure",]
  testthat::expect_equal(latest$date,"2026-10-02")
  testthat::expect_equal(latest$source,"daily-explorer/maps/2026-10-02-tmean-departure.png")
  historical<-rows[rows$family=="Historic seasons",]
  testthat::expect_equal(historical$path,"maps/generated/prism/seasonal-archive/wy2024/cool_total.png")
  testthat::expect_silent(validate_map_hotlinks(root))
  before<-tools::md5sum(file.path(root,rows$path)); urls<-rows$url
  again<-stage_map_hotlinks(root,"s3://bucket/climate/watch-staging/",f$products,f$metadata,f$registry)
  testthat::expect_identical(again$url,urls)
  testthat::expect_identical(unname(tools::md5sum(file.path(root,again$path))),unname(before))
  # Even if render cleanup removes an alias, its unchanged timestamp survives.
  mtime<-as.numeric(file.info(file.path(root,monthly$path))$mtime)
  unlink(file.path(root,monthly$path))
  restored<-stage_map_hotlinks(root,"s3://bucket/climate/watch-staging/",f$products,f$metadata,f$registry)
  testthat::expect_equal(as.numeric(file.info(file.path(root,monthly$path))$mtime),mtime,tolerance=1e-4)
  writeLines("corrupt",file.path(root,monthly$path))
  testthat::expect_error(validate_map_hotlinks(root),"checksum")
})

testthat::test_that("quarantined, disabled, missing and retired maps receive notice images", {
  root<-tempfile();on.exit(unlink(root,recursive=TRUE),add=TRUE);f<-hotlink_fixture(root)
  before<-stage_map_hotlinks(root,"s3://bucket/climate/watch/",f$products,f$metadata,f$registry)
  payload<-jsonlite::read_json(file.path(root,"daily-explorer/daily-data.json"))
  payload$circulation_enabled<-FALSE;f$json(payload,"daily-explorer/daily-data.json")
  products<-f$products[2L,,drop=FALSE] # Simulates deliberate removal of the old product ID.
  rows<-stage_map_hotlinks(root,"s3://bucket/climate/watch/",products,f$metadata,f$registry)
  weather<-rows[rows$id=="weather/latest/moisture",]
  testthat::expect_equal(weather$status,"UNAVAILABLE")
  testthat::expect_false(identical(weather$md5,before$md5[before$id==weather$id]))
  retired<-rows[rows$id=="current/maxt_value",]
  testthat::expect_equal(retired$status,"DISABLED")
  testthat::expect_equal(retired$url,before$url[before$id==retired$id])
  testthat::expect_true(map_hotlink_png(file.path(root,retired$path)))
  testthat::expect_true(all(rows$status[rows$family=="Current Snow"]=="UNAVAILABLE"))
  testthat::expect_silent(validate_map_hotlinks(root))
})

testthat::test_that("invalid declared source maps fail before replacing existing hotlinks", {
  root<-tempfile();on.exit(unlink(root,recursive=TRUE),add=TRUE);f<-hotlink_fixture(root)
  rows<-stage_map_hotlinks(root,"s3://bucket/climate/watch/",f$products,f$metadata,f$registry)
  path<-file.path(root,rows$path[rows$id=="current/maxt_value"])
  before<-tools::md5sum(path)
  writeLines("bad source",file.path(root,"maps/generated/prism/temperature/maxt.png"))
  testthat::expect_error(stage_map_hotlinks(root,"s3://bucket/climate/watch/",f$products,f$metadata,f$registry),"differs from accepted")
  testthat::expect_identical(tools::md5sum(path),before)
  testthat::expect_error(map_hotlink_path(root,"../outside.png"),"Unsafe")
  testthat::expect_error(map_hotlink_base("s3://bucket/climate/../"),"exact site")
})
