cleanup_root <- normalizePath(testthat::test_path("../.."), winslash="/", mustWork=TRUE)
source(file.path(cleanup_root,"R/map-cleanup-audit.R"))

testthat::test_that("audit protects references, latest dates, stable names and recent writes without changing maps", {
  root <- tempfile();dir.create(root);withr::defer(unlink(root,recursive=TRUE))
  for(copy in c("site","site/_site")) {
    folder<-file.path(root,copy,"maps/generated/prism/temperature")
    dir.create(folder,recursive=TRUE)
    for(name in c(paste0("maxt-value-2025-01-0",1:6,".png"),"maxt-value-latest.png","recent-2024-01-01.png")) {
      path<-file.path(folder,name);writeBin(as.raw(1:20),path)
      Sys.setFileTime(path,as.POSIXct("2025-01-01",tz="UTC"))
    }
    Sys.setFileTime(file.path(folder,"recent-2024-01-01.png"),as.POSIXct("2026-11-25",tz="UTC"))
  }
  dir.create(file.path(root,"site/pages"))
  writeLines('<img src="../maps/generated/prism/temperature/maxt-value-2025-01-01.png">',file.path(root,"site/pages/map.qmd"))
  dir.create(file.path(root,"data/processed"),recursive=TRUE)
  writeLines(c('"https://example/maps/maxt%2Dvalue%2D2025%2D01%2D02.png"',
    '"%00%02dmonth.png"', '"%ZZ%00%02dmonth.png"', '"bad%XXmonth.png"'),
    file.path(root,"data/processed/catalog.json"))
  allmaps<-list.files(file.path(root,"site"),pattern="png$",recursive=TRUE,full.names=TRUE)
  before<-tools::md5sum(allmaps)
  x<-audit_map_cleanup(root,today="2026-11-26")
  testthat::expect_equal(nrow(x$candidates),4)
  testthat::expect_setequal(unique(x$candidates$filename),paste0("maxt-value-2025-01-0",3:4,".png"))
  testthat::expect_true(all(x$inventory$status[grepl("latest|recent",x$inventory$filename)]=="KEEP"))
  testthat::expect_equal(nrow(x$scan_issues),0)
  testthat::expect_identical(before,tools::md5sum(allmaps))
  withr::local_options(swc.cleanup.rg="")
  y<-audit_map_cleanup(root,today="2026-11-26")
  testthat::expect_identical(x$candidates,y$candidates)
  testthat::expect_error(audit_map_cleanup(root,report_dir="site/maps"),"under data/diagnostics")
  testthat::expect_error(audit_map_cleanup(root,report_dir="data/diagnostics/../bad"),"under data/diagnostics")
})

testthat::test_that("an incomplete reference scan holds otherwise unreferenced maps", {
  root<-tempfile();dir.create(root);withr::defer(unlink(root,recursive=TRUE))
  folder<-file.path(root,"site/maps/generated/prism/precipitation");dir.create(folder,recursive=TRUE)
  for(day in 1:4) {
    p<-file.path(folder,paste0("pcpn-total-2020-01-0",day,".png"));writeLines("png",p)
    Sys.setFileTime(p,as.POSIXct("2020-01-01",tz="UTC"))
  }
  # Oversize metadata must not silently permit cleanup proposals.
  writeBin(c(charToRaw("pcpn-total-2020-01-01.png"),raw(25*1024^2+1)),file.path(root,"site/huge.json"))
  x<-audit_map_cleanup(root,today="2026-11-26")
  testthat::expect_equal(nrow(x$candidates),0)
  testthat::expect_equal(sum(x$inventory$status=="HOLD"),2)
  testthat::expect_equal(nrow(x$scan_issues),1)
})

testthat::test_that("an empty map inventory produces usable empty reports", {
  root<-tempfile();dir.create(file.path(root,"site"),recursive=TRUE);withr::defer(unlink(root,recursive=TRUE))
  x<-audit_map_cleanup(root)
  testthat::expect_equal(nrow(x$inventory),0)
  testthat::expect_true(file.exists(file.path(x$report_dir,"proposed-cleanup.csv")))
})
