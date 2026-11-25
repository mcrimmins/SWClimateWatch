seasonal_test_root<-normalizePath(testthat::test_path("..",".."),winslash="/",mustWork=TRUE)
source(file.path(seasonal_test_root,"R/daily-explorer-july-pilot.R"))
source(file.path(seasonal_test_root,"R/daily-explorer-seasonal-pilots.R"))

testthat::test_that("seasonal windows include complete trailing means and precipitation timing",{
  withr::local_dir(seasonal_test_root)
  # Context's root guard is tested separately by the archive pilot tests.
  e<-new.env(parent=environment());sys.source("R/daily-explorer-july-pilot.R",envir=e)
  e$daily_archive_pilot_root<-identity
  windows<-seasonal_explorer_windows()
  testthat::expect_identical(names(windows),c("winter","quiet"))
  for(w in windows) {
    x<-e$july_pilot_context(w)
    testthat::expect_length(x$dates,7L);testthat::expect_length(x$support,36L)
    testthat::expect_false(x$july)
    testthat::expect_identical(x$release,"window-release.json")
    testthat::expect_identical(x$dates[c(1,7)],c(w$start,w$end))
    testthat::expect_identical(x$support[1],as.character(as.Date(w$start)-29L))
    for(end in x$dates)for(n in c(1L,7L,30L))
      testthat::expect_true(all(as.character(seq(as.Date(end)-n+1L,as.Date(end),by="day"))%in%x$support))
    testthat::expect_identical(length(c(as.character(as.Date(w$start)-1),x$dates)),8L)
  }
  bad<-windows$winter;bad$end<-"2025-03-07"
  testthat::expect_error(e$july_pilot_context(bad),"one month")
  bad<-windows$winter;bad$id<-"../production"
  testthat::expect_error(e$july_pilot_context(bad),"Invalid pilot")
  bad<-windows$winter;bad$title<-"<script>"
  testthat::expect_error(e$july_pilot_context(bad),"Invalid pilot")
})

testthat::test_that("seasonal entry points enforce bounded and explicit network permission",{
  testthat::expect_error(prepare_seasonal_explorer(TRUE,11L),"Bound preparation")
  testthat::expect_error(prepare_seasonal_explorer(NA,1L),"Bound preparation")
  testthat::expect_error(build_seasonal_explorer(TRUE,8L),"Bound rendering")
  testthat::expect_error(build_seasonal_explorer("yes",1L),"Bound rendering")
  e<-new.env(parent=environment());sys.source(file.path(seasonal_test_root,"R/daily-explorer-seasonal-pilots.R"),envir=e)
  e$july_pilot_context<-function(w)list(root="unused",support="2025-02-01")
  e$july_pilot_input<-function(...)NULL
  e$build_daily_explorer_july<-function(...)stop("RENDER MUST NOT RUN")
  testthat::expect_error(e$build_seasonal_explorer(),"Finish input preparation")
})

testthat::test_that("shared markers are checked before reuse and do not alter donors",{
  e<-new.env(parent=environment());sys.source(file.path(seasonal_test_root,"R/daily-explorer-seasonal-pilots.R"),envir=e)
  root<-tempfile("seasonal-marker-");dir.create(root)
  withr::defer(unlink(root,recursive=TRUE))
  donor<-file.path(root,"july");target<-file.path(root,"winter")
  e$july_pilot_root<-function()donor
  e$seasonal_explorer_windows<-function()list()
  e$july_pilot_context<-function(w)list(root=target,support=c("2025-02-01","2025-02-02"))
  # The input verifier returns only the first date from the donor; second is invalid.
  e$july_pilot_input<-function(r,d) {
    if(r==donor&&d=="2025-02-01")return(list(date=d,digest="verified"))
    file<-file.path(r,"inputs",d,"complete.rds")
    if(file.exists(file))readRDS(file)else NULL
  }
  testthat::expect_identical(e$seasonal_explorer_seed(list()),1L)
  testthat::expect_identical(e$seasonal_explorer_seed(list()),0L)
  testthat::expect_false(dir.exists(donor))
  testthat::expect_true(file.exists(file.path(target,"inputs/2025-02-01/complete.rds")))
  testthat::expect_false(file.exists(file.path(target,"inputs/2025-02-02/complete.rds")))
})
