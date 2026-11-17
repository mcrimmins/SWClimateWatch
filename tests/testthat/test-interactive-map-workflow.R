source(file.path(project_root,"R/interactive-map-pilot.R"))
source(file.path(project_root,"R/interactive-map-staging.R"))
source(file.path(project_root,"R/interactive-map-workflow.R"))
source(file.path(project_root,"R/daily-publish.R"))

testthat::test_that("monthly windows follow the release across years", {
  d <- interactive_pilot_definitions("2026-11")
  testthat::expect_equal(d$`temperature-01month`$period,"November 2026")
  testthat::expect_equal(d$`precipitation-12month`$period,"December 2025 to November 2026")
  testthat::expect_equal(interactive_pilot_definitions("2027-01")$`spi-03month`$period,"November 2026 to January 2027")
  testthat::expect_error(interactive_pilot_definitions("2026-13"),"Invalid monthly")
})

testthat::test_that("monthly viewer cache handles revisions, retention, corruption and new release failures", {
  root <- tempfile("monthly-viewer-");dir.create(root)
  on.exit(unlink(root,recursive=TRUE),add=TRUE)
  builds <- 0L; signature <- "first"
  build <- function(output_dir,end,...) {
    builds <<- builds+1L;dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
    layers <- lapply(names(interactive_pilot_definitions(end)),function(id) {
      name <- paste0(id,"-",signature,".bin"); path <- file.path(output_dir,name)
      writeBin(as.raw(c(1,2,3,builds)),path);writeLines(unname(tools::md5sum(path)),paste0(path,".md5"))
      list(file=name,bytes=4L)
    });names(layers) <- names(interactive_pilot_definitions(end))
    writeLines("{}",file.path(output_dir,"boundaries.json"))
    list(manifest=list(end_month=end,layers=layers))
  }
  args <- list(release=list(end_month="2026-10",version="2026-10-abc"),output_dir=file.path(root,"out"),
    cache_root=file.path(root,"cache"),.sources=function(...)signature,.build=build)
  first <- do.call(interactive_refresh_monthly,args)
  testthat::expect_equal(builds,1L);testthat::expect_false(first$monthly_reused)
  testthat::expect_true(do.call(interactive_refresh_monthly,args)$monthly_reused)
  signature <- "revised"
  revised <- do.call(interactive_refresh_monthly,args)
  testthat::expect_equal(builds,2L);testthat::expect_equal(revised$manifest$monthly_release$signature,"revised")
  args$.sources <- function(...)stop("incomplete monthly refresh")
  held <- do.call(interactive_refresh_monthly,args)
  testthat::expect_true(held$monthly_retained)
  testthat::expect_identical(held$manifest$layers,revised$manifest$layers)
  args$release <- list(end_month="2026-11",version="2026-11-def")
  testthat::expect_error(do.call(interactive_refresh_monthly,args),"No matching verified")
  args$release <- list(end_month="2026-11",version="2026-11-def")
  args$.sources <- function(...)"november"
  next_month <- do.call(interactive_refresh_monthly,args)
  testthat::expect_equal(next_month$manifest$end_month,"2026-11")
  testthat::expect_equal(next_month$manifest$monthly_release$version,"2026-11-def")
  args$release <- list(end_month="2026-10",version="2026-10-abc")
  args$.sources <- function(...)stop("incomplete monthly refresh")
  writeBin(as.raw(9:6),file.path(root,"cache/2026-10-abc",revised$manifest$layers[[1]]$file))
  testthat::expect_error(do.call(interactive_refresh_monthly,args),"No matching verified")
})

testthat::test_that("monthly numerical fields must match the accepted map release", {
  withr::local_dir(project_root)
  root <- tempfile("monthly-binding-");dir.create(root)
  on.exit(unlink(root,recursive=TRUE),add=TRUE)
  release <- list(end_month="2026-10",version="2026-10-abc",products=data.frame())
  defs <- interactive_pilot_definitions("2026-10",root,root)
  for(d in defs) {
    dir.create(d$folder,recursive=TRUE,showWarnings=FALSE)
    png <- file.path(d$folder,if(d$family=="spi")"spi.png" else paste0(d$family,"-ranking.png"))
    grid <- file.path(d$folder,"value.tif")
    writeLines("verified map",png);writeLines("verified numerical data",grid)
    files <- c(png,grid)
    saveRDS(list(files=files,md5=unname(tools::md5sum(files))),file.path(d$folder,"complete.rds"))
    release$products <- rbind(release$products,data.frame(family=d$family,duration=d$duration,md5=unname(tools::md5sum(png))))
  }
  testthat::expect_type(interactive_monthly_sources(release,root,root),"character")
  d <- defs[[1]];path <- file.path(d$folder,"complete.rds");m <- readRDS(path)
  writeLines("revised map",m$files[1]);m$md5 <- unname(tools::md5sum(m$files));saveRDS(m,path)
  testthat::expect_error(interactive_monthly_sources(release,root,root),"differ from the accepted")
  writeLines("corrupt numerical data",m$files[2])
  testthat::expect_error(interactive_monthly_sources(release,root,root),"source integrity failed")
})

testthat::test_that("viewer runs before unchanged detection and failures stop publication", {
  root <- tempfile("viewer-order-");dir.create(root)
  on.exit(unlink(root,recursive=TRUE),add=TRUE)
  marker <- file.path(root,"success.csv");swc_daily_publish_write_marker(marker,"old")
  calls <- character(); fingerprint <- "old"; published <- 0L
  report <- list(status="READY",daily_bundles=120L,daily_through="2026-11-15",current_products=39L,current_unavailable=0L,monthly_end="2026-10")
  args <- list(today=as.Date("2026-11-16"),dry_run=FALSE,marker_path=marker,log_path=NULL,
    prism_update=function()list(summary=data.frame(data_changed=FALSE)),explorer_update=function()list(status="STAGED"),
    weather_update=function(today)list(status="DISABLED"),snow_update=function(today)list(maps=list(status="OUT_OF_SEASON")),
    station_update=function(today)list(status="UPDATED"),monthly_update=function(today){calls<<-c(calls,"monthly");list(status="DISABLED")},
    interactive_update=function(today){calls<<-c(calls,"viewer");fingerprint<<-"new";report},
    site_fingerprint=function(){calls<<-c(calls,"fingerprint");fingerprint},
    publish=function(dry_run){published<<-published+1L;list()},notify=function(...)NULL)
  result <- do.call(run_swc_daily_publish,args)
  testthat::expect_equal(calls[1:3],c("monthly","viewer","fingerprint"))
  testthat::expect_equal(published,1L)
  testthat::expect_true(any(grepl("Interactive Maps:",result$summary_lines,fixed=TRUE)))
  testthat::expect_equal(do.call(run_swc_daily_publish,args)$status,"SKIPPED_UNCHANGED")
  testthat::expect_equal(published,1L)
  args$interactive_update <- function(today)stop("viewer failed")
  testthat::expect_error(do.call(run_swc_daily_publish,args),"viewer failed")
  testthat::expect_equal(published,1L)
  testthat::expect_identical(swc_daily_publish_read_marker(marker),"new")
})
