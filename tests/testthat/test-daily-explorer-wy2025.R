wy_test_root<-normalizePath(testthat::test_path("..",".."),winslash="/",mustWork=TRUE)
source(file.path(wy_test_root,"R/daily-explorer-wy2025.R"))

testthat::test_that("WY2025 has twelve whole months and complete supporting windows",{
  source(file.path(wy_test_root,"R/daily-explorer-july-pilot.R"),local=TRUE)
  windows<-wy2025_explorer_windows()
  testthat::expect_length(windows,12L)
  dates<-unlist(lapply(windows,function(w)as.character(seq(as.Date(w$start),as.Date(w$end),by="day"))),use.names=FALSE)
  testthat::expect_identical(dates,as.character(seq(as.Date("2024-10-01"),as.Date("2025-09-30"),by="day")))
  testthat::expect_identical(length(dates)*16L,5840L)
  e<-new.env(parent=environment());sys.source(file.path(wy_test_root,"R/daily-explorer-july-pilot.R"),envir=e)
  e$daily_archive_pilot_root<-identity
  for(w in windows) {
    context<-e$july_pilot_context(w)
    testthat::expect_identical(context$lookback,30L)
    testthat::expect_identical(min(context$support),as.character(as.Date(w$start)-29L))
    for(end in context$dates)for(n in c(1L,7L,30L))
      testthat::expect_true(all(as.character(seq(as.Date(end)-n+1L,as.Date(end),by="day"))%in%context$support))
  }
  testthat::expect_identical(e$july_pilot_context(windows[[1]])$support[1],"2024-09-02")
})
testthat::test_that("month batches are capped before any work or downloads",{
  testthat::expect_error(run_wy2025_explorer_batch(download="yes"),"TRUE/FALSE")
  testthat::expect_error(run_wy2025_explorer_batch(max_input_dates=11L),"TRUE/FALSE")
  testthat::expect_error(run_wy2025_explorer_batch(max_end_dates=8L),"TRUE/FALSE")
  testthat::expect_error(run_wy2025_explorer_batch(month="2024-09"),"Invalid WY2025")
  e<-new.env(parent=environment());sys.source(file.path(wy_test_root,"R/daily-explorer-wy2025.R"),envir=e)
  e$wy2025_explorer_plan<-function(...)data.frame(month=c("2024-10","2024-11"),status="RELEASE_PRESENT")
  e$wy2025_explorer_source<-function(...)stop("NO WORK SHOULD RUN")
  testthat::expect_identical(e$run_wy2025_explorer_batch()$status,"ALL_RELEASES_PRESENT")
})
testthat::test_that("a preparation checkpoint returns without rendering incomplete means",{
  e<-new.env(parent=environment());sys.source(file.path(wy_test_root,"R/daily-explorer-wy2025.R"),envir=e)
  root<-tempfile("wy-batch-");dir.create(root);withr::defer(unlink(root,recursive=TRUE))
  calls<-list()
  e$wy2025_explorer_root<-function()root
  e$wy2025_explorer_plan<-function(...)data.frame(month="2024-10",status="PENDING")
  e$wy2025_explorer_source<-function(...)list(root=root,release="missing.json",window=list(id="test"))
  e$wy2025_explorer_seed<-function(month)NULL
  e$prepare_daily_explorer_july<-function(download,max_new_dates,window) {
    calls[[length(calls)+1L]]<<-list(download,max_new_dates)
    data.frame(status="PARTIAL",ready=10L,required=60L)
  }
  e$build_daily_explorer_july<-function(...)stop("RENDER MUST NOT RUN")
  x<-e$run_wy2025_explorer_batch(download=FALSE)
  testthat::expect_identical(x$status,"PREPARING")
  testthat::expect_identical(calls,list(list(FALSE,10L)))
  testthat::expect_true(file.exists(file.path(root,"last-batch.csv")))
  dir.create(file.path(root,"viewer"));writeLines("invalid",file.path(root,"viewer/missing.json"))
  e$validate_daily_explorer_july<-function(...)stop("Changed asset")
  repaired<-e$run_wy2025_explorer_batch(month="2024-10",download=FALSE)
  testthat::expect_identical(repaired$status,"PREPARING")
  testthat::expect_false(file.exists(file.path(root,"viewer/missing.json")))
})

testthat::test_that("monthly report coverage includes all thirty preceding dates without HTTP",{
  withr::local_dir(wy_test_root)
  e<-new.env(parent=globalenv());sys.source("R/storm-reports-pilot.R",envir=e)
  root<-tempfile("wy-report-lookback-",tmpdir="data/diagnostics")
  dir.create(file.path(root,"source"),recursive=TRUE)
  withr::defer(unlink(root,recursive=TRUE))
  dates<-as.character(seq(as.Date("2024-10-01"),as.Date("2024-10-31"),by="day"))
  keys<-c("pcpn-observed","maxt-observed","maxt-departure","mint-observed","mint-departure","tmean-observed","tmean-departure")
  payload<-list(schema_version=1L,latest_cached_date=max(dates),days=lapply(dates,function(d)
    list(date=d,water_year=2025L,images=as.list(setNames(paste0("maps/",d,"-",keys,".png"),gsub("-","_",keys))))))
  jsonlite::write_json(payload,file.path(root,"source/daily-data.json"),auto_unbox=TRUE)
  snapshot<-list(reports=list(),snapshots=list(),stale_dates=character(),
    available_dates=as.character(seq(as.Date("2024-09-01"),as.Date("2024-10-31"),by="day")))
  e$read_storm_reports_cache<-function(...)stop("NETWORK MUST NOT RUN")
  e$build_storm_reports_pilot(source_dir=file.path(root,"source"),output_dir=file.path(root,"viewer"),
    copy_maps=FALSE,full_window=TRUE,snapshot=snapshot,lookback_days=30L)
  p<-jsonlite::read_json(file.path(root,"viewer/storm-reports-manifest.json"))
  testthat::expect_identical(p$start,"2024-09-01")
  testthat::expect_identical(p$end_exclusive,"2024-11-01")
  testthat::expect_length(p$days,61L)
  testthat::expect_true(all(vapply(p$days,function(d)d$status=="EMPTY",logical(1))))
  testthat::expect_true(all(vapply(p$timeline$prism,function(d)isTRUE(d$complete),logical(1))))
  # Hazard query chunks cover exactly the same padding, capped at 31 days each.
  h<-new.env(parent=globalenv());sys.source("R/nws-hazards-explorer.R",envir=h)
  # Capture in a closure independent of the production helper's environment.
  h$build_nws_hazards_pilot<-local({capture<-environment();function(cases,...) {
    assign("captured_cases",cases,envir=capture);stop("STOP BEFORE ARCHIVE DOWNLOAD")
  }})
  testthat::expect_error(h$build_nws_hazards_explorer(source_dir=file.path(root,"source"),
    output_dir=file.path(root,"hazards"),copy_maps=FALSE,full_window=TRUE,report_snapshot=snapshot,
    lookback_days=30L),"STOP BEFORE ARCHIVE DOWNLOAD")
  captured<-get("captured_cases",envir=environment(h$build_nws_hazards_pilot))
  testthat::expect_identical(min(captured$start),"2024-09-01")
  testthat::expect_identical(max(captured$end),"2024-11-01")
  testthat::expect_true(all(as.Date(captured$end)-as.Date(captured$start)<=31L))
})
