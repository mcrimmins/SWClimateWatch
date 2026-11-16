source(file.path(project_root, "R/interactive-map-pilot.R"))
source(file.path(project_root, "R/interactive-map-current.R"))

testthat::test_that("current snapshots bind exact product dates and preserve masks and precision", {
  folder <- tempfile("current-map-"); dir.create(folder)
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  root <- file.path(folder, "grids"); maps <- file.path(folder, "maps")
  spec <- interactive_current_definitions()[interactive_current_definitions()$id == "pcpn_percent_normal_30day",]
  dir.create(file.path(root,spec$folder),recursive=TRUE);dir.create(maps)
  path <- file.path(root,spec$folder,"2026-11-03.tif")
  r <- terra::rast(nrows=2,ncols=2,xmin=-111,xmax=-110,ymin=33,ymax=34,crs="EPSG:4326")
  terra::values(r)<-c(0,100+1/32768,NA,250);terra::time(r)<-as.Date("2026-11-03")
  terra::writeRaster(r,path,datatype="FLT8S")
  writeLines("verified image fixture",file.path(maps,"map.png"))
  config<-list(products=setNames(list(list(image="map.png")),spec$id))
  status<-data.frame(id=spec$id,enabled=TRUE,validation_status="PASS",actual_data_date="2026-11-03",
    image_md5=unname(tools::md5sum(file.path(maps,"map.png"))))
  snapshot<-interactive_current_snapshot(spec,status,config,root,maps)
  testthat::expect_equal(snapshot$start,as.Date("2026-10-05"))
  export<-interactive_current_export(spec$id,snapshot,folder)
  testthat::expect_true(export$checks$passed)
  con<-file(file.path(folder,export$entry$file),"rb")
  v<-readBin(con,"numeric",n=4,size=8,endian="little");close(con)
  testthat::expect_identical(v[is.finite(v)],c(0,100+1/32768,250))
  testthat::expect_identical(is.na(v),c(FALSE,FALSE,TRUE,FALSE))
  testthat::expect_true(interactive_current_export(spec$id,snapshot,folder)$summary$reused)
  # A missing exact-date grid must not fall back to an older neighboring grid.
  terra::time(r)<-as.Date("2026-11-02");terra::writeRaster(r,file.path(root,spec$folder,"2026-11-02.tif"))
  ongoing <- spec; ongoing$period <- "current"
  testthat::expect_equal(interactive_current_snapshot(ongoing,status,config,root,maps)$start,as.Date("2026-11-03"))
  invalid_change <- spec; invalid_change$metric <- "change"
  testthat::expect_error(interactive_current_snapshot(invalid_change,status,config,root,maps),"percentile-point change")
  invalid_share <- spec; invalid_share$metric <- "share"
  testthat::expect_error(interactive_current_snapshot(invalid_share,status,config,root,maps),"precipitation share")
  invalid_count <- spec; invalid_count$metric <- "count"
  testthat::expect_error(interactive_current_snapshot(invalid_count,status,config,root,maps),"day/night count")
  unlink(path)
  testthat::expect_error(interactive_current_snapshot(spec,status,config,root,maps),"Exact dated numerical grid missing")
  # Even a file with the expected name must carry the correct internal date.
  terra::writeRaster(r,path,datatype="FLT8S")
  testthat::expect_error(interactive_current_snapshot(spec,status,config,root,maps),"grid date differs")
  writeLines("changed image",file.path(maps,"map.png"))
  testthat::expect_error(interactive_current_snapshot(spec,status,config,root,maps),"fingerprint mismatch")
  testthat::expect_equal(nrow(interactive_current_definitions()),39)
})
