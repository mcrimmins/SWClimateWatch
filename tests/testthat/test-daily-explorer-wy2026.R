wy_test_root<-normalizePath(testthat::test_path("..",".."),winslash="/",mustWork=TRUE)
source(file.path(wy_test_root,"R/daily-explorer-wy2026.R"))

testthat::test_that("WY2026 reuses verified WY2025 support markers without changing donors",{
  withr::local_dir(wy_test_root)
  e<-new.env(parent=globalenv());sys.source("R/daily-explorer-wy2026.R",envir=e)
  root<-tempfile("wy2026-seed-");dir.create(root);withr::defer(unlink(root,recursive=TRUE))
  donor<-file.path(root,"wy2025");target<-file.path(root,"wy2026");dir.create(donor);dir.create(target)
  writeLines("accepted",file.path(donor,"release.txt"));before<-tools::md5sum(file.path(donor,"release.txt"))
  e$wy2026_explorer_source<-function(...)list(root=target,window=list())
  e$july_pilot_context<-function(...)list(support="2025-09-02",dates=character())
  e$july_pilot_root<-function()file.path(root,"july")
  e$seasonal_explorer_windows<-function()list()
  e$wy2025_explorer_windows<-function()list(list(root=donor))
  e$wy2026_explorer_windows<-function()list(list(root=target))
  e$july_pilot_input<-function(root,date) {
    if(identical(root,donor))return(list(date=date,verified=TRUE))
    f<-file.path(root,"inputs",date,"complete.rds")
    if(file.exists(f))readRDS(f)else NULL
  }
  e$wy2026_explorer_seed("2025-10")
  testthat::expect_identical(readRDS(file.path(target,"inputs/2025-09-02/complete.rds")),list(date="2025-09-02",verified=TRUE))
  testthat::expect_identical(before,tools::md5sum(names(before)))
})

testthat::test_that("partial-year navigation seals only the selected WY2026 month",{
  withr::local_dir(wy_test_root)
  source("scripts/load-daily-explorer-wy2026.R",local=FALSE)
  e<-new.env(parent=globalenv());sys.source("R/daily-explorer-wy2026.R",envir=e)
  root<-tempfile("wy2026-nav-",tmpdir="data/diagnostics");dir.create(root);withr::defer(unlink(root,recursive=TRUE))
  source_dir<-file.path(root,"month/viewer");dir.create(source_dir,recursive=TRUE)
  dates<-as.character(seq(as.Date("2025-10-01"),as.Date("2025-10-31"),by="day"))
  writeLines('<head><script src="explorer.js" defer></script></head><body><main>review</main></body>',file.path(source_dir,"index.html"))
  writeLines('fetch("daily-data.json")',file.path(source_dir,"explorer.js"))
  jsonlite::write_json(list(days=lapply(dates,function(d)list(date=d))),file.path(source_dir,"daily-data.json"),auto_unbox=TRUE)
  files<-c("index.html","explorer.js","daily-data.json")
  jsonlite::write_json(list(files=lapply(files,function(p)list(path=p,md5=unname(tools::md5sum(file.path(source_dir,p)))))),
    file.path(source_dir,"window-release.json"),auto_unbox=TRUE)
  e$wy2026_explorer_root<-function()root
  e$validate_wy2026_explorer<-function(...)data.frame(month="2025-10",status="READY")
  e$wy2026_explorer_source<-function(...)list(root=file.path(root,"month"),release="window-release.json",window=list())
  e$validate_daily_explorer_july<-function(...)invisible(TRUE)
  e$build_wy2026_explorer_navigation(require_complete=FALSE)
  preview<-file.path(root,"preview")
  release<-jsonlite::read_json(file.path(preview,"wy2026-release.json"))
  testthat::expect_identical(release$water_year,2026L)
  testthat::expect_false(release$complete)
  testthat::expect_match(paste(readLines(file.path(preview,"index.html")),collapse=""),"WY2026 local archive",fixed=TRUE)
  testthat::expect_identical(e$validate_wy2026_explorer_navigation(preview,FALSE)$dates,31L)
  testthat::expect_error(e$validate_wy2026_explorer_navigation(preview,TRUE),"Incomplete WY2026")
  writeLines("changed",file.path(preview,"months/2025-10/explorer.js"))
  testthat::expect_error(e$validate_wy2026_explorer_navigation(preview,FALSE),"Changed/missing")
})

testthat::test_that("WY2026 has twelve whole months and complete supporting windows",{
  source(file.path(wy_test_root,"R/daily-explorer-july-pilot.R"),local=TRUE)
  windows<-wy2026_explorer_windows()
  testthat::expect_length(windows,12L)
  dates<-unlist(lapply(windows,function(w)as.character(seq(as.Date(w$start),as.Date(w$end),by="day"))),use.names=FALSE)
  testthat::expect_identical(dates,as.character(seq(as.Date("2025-10-01"),as.Date("2026-09-30"),by="day")))
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
  testthat::expect_identical(e$july_pilot_context(windows[[1]])$support[1],"2025-09-02")
})
testthat::test_that("month batches are capped before any work or downloads",{
  testthat::expect_error(run_wy2026_explorer_batch(download="yes"),"TRUE/FALSE")
  testthat::expect_error(run_wy2026_explorer_batch(max_input_dates=11L),"TRUE/FALSE")
  testthat::expect_error(run_wy2026_explorer_batch(max_end_dates=8L),"TRUE/FALSE")
  testthat::expect_error(run_wy2026_explorer_batch(month="2025-09"),"Invalid WY2026")
  e<-new.env(parent=environment());sys.source(file.path(wy_test_root,"R/daily-explorer-wy2026.R"),envir=e)
  e$wy2026_explorer_plan<-function(...)data.frame(month=c("2025-10","2025-11"),status="RELEASE_PRESENT")
  e$wy2026_explorer_source<-function(...)stop("NO WORK SHOULD RUN")
  testthat::expect_identical(e$run_wy2026_explorer_batch()$status,"ALL_RELEASES_PRESENT")
})
testthat::test_that("a preparation checkpoint returns without rendering incomplete means",{
  e<-new.env(parent=environment());sys.source(file.path(wy_test_root,"R/daily-explorer-wy2026.R"),envir=e)
  root<-tempfile("wy-batch-");dir.create(root);withr::defer(unlink(root,recursive=TRUE))
  calls<-list()
  e$wy2026_explorer_root<-function()root
  e$wy2026_explorer_plan<-function(...)data.frame(month="2025-10",status="PENDING")
  e$wy2026_explorer_source<-function(...)list(root=root,release="missing.json",window=list(id="test"))
  e$wy2026_explorer_seed<-function(month)NULL
  e$prepare_daily_explorer_july<-function(download,max_new_dates,window) {
    calls[[length(calls)+1L]]<<-list(download,max_new_dates)
    data.frame(status="PARTIAL",ready=10L,required=60L)
  }
  e$build_daily_explorer_july<-function(...)stop("RENDER MUST NOT RUN")
  x<-e$run_wy2026_explorer_batch(download=FALSE)
  testthat::expect_identical(x$status,"PREPARING")
  testthat::expect_identical(calls,list(list(FALSE,10L)))
  testthat::expect_true(file.exists(file.path(root,"last-batch.csv")))
  dir.create(file.path(root,"viewer"));writeLines("invalid",file.path(root,"viewer/missing.json"))
  e$validate_daily_explorer_july<-function(...)stop("Changed asset")
  repaired<-e$run_wy2026_explorer_batch(month="2025-10",download=FALSE)
  testthat::expect_identical(repaired$status,"PREPARING")
  testthat::expect_false(file.exists(file.path(root,"viewer/missing.json")))
})

testthat::test_that("monthly report coverage includes all thirty preceding dates without HTTP",{
  withr::local_dir(wy_test_root)
  e<-new.env(parent=globalenv());sys.source("R/storm-reports-pilot.R",envir=e)
  root<-tempfile("wy-report-lookback-",tmpdir="data/diagnostics")
  dir.create(file.path(root,"source"),recursive=TRUE)
  withr::defer(unlink(root,recursive=TRUE))
  dates<-as.character(seq(as.Date("2025-10-01"),as.Date("2025-10-31"),by="day"))
  keys<-c("pcpn-observed","maxt-observed","maxt-departure","mint-observed","mint-departure","tmean-observed","tmean-departure")
  payload<-list(schema_version=1L,latest_cached_date=max(dates),days=lapply(dates,function(d)
    list(date=d,water_year=2026L,images=as.list(setNames(paste0("maps/",d,"-",keys,".png"),gsub("-","_",keys))))))
  jsonlite::write_json(payload,file.path(root,"source/daily-data.json"),auto_unbox=TRUE)
  snapshot<-list(reports=list(),snapshots=list(),stale_dates=character(),
    available_dates=as.character(seq(as.Date("2025-09-01"),as.Date("2025-10-31"),by="day")))
  e$read_storm_reports_cache<-function(...)stop("NETWORK MUST NOT RUN")
  e$build_storm_reports_pilot(source_dir=file.path(root,"source"),output_dir=file.path(root,"viewer"),
    copy_maps=FALSE,full_window=TRUE,snapshot=snapshot,lookback_days=30L)
  p<-jsonlite::read_json(file.path(root,"viewer/storm-reports-manifest.json"))
  testthat::expect_identical(p$start,"2025-09-01")
  testthat::expect_identical(p$end_exclusive,"2025-11-01")
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
  testthat::expect_identical(min(captured$start),"2025-09-01")
  testthat::expect_identical(max(captured$end),"2025-11-01")
  testthat::expect_true(all(as.Date(captured$end)-as.Date(captured$start)<=31L))
})
