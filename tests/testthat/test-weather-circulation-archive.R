source(file.path(project_root,"R","weather-circulation-archive.R"))

testthat::test_that("weather metadata preserves climate precision and unchanged payload bytes", {
  path <- tempfile(fileext=".json"); on.exit(unlink(path),add=TRUE)
  value <- list(precip=1.12345678912345,circulation_enabled=TRUE)
  weather_write_json(value,path)
  testthat::expect_equal(jsonlite::read_json(path)$precip,value$precip,tolerance=1e-14)
  before <- unname(tools::md5sum(path)); stamp <- file.info(path)$mtime
  weather_write_json(value,path)
  testthat::expect_equal(unname(tools::md5sum(path)),before)
  testthat::expect_equal(file.info(path)$mtime,stamp)
})

testthat::test_that("archive plan grows without rolling older dates out", {
  dates <- as.character(seq(as.Date("2026-10-01"),as.Date("2026-11-05"),by="day"))
  plan <- weather_archive_plan(dates,today=as.Date("2026-11-06"),max_new_dates=3,recheck_days=0)
  testthat::expect_equal(plan$date,c("2026-11-05","2026-11-04","2026-11-03"))
  plan <- weather_archive_plan(dates,known_dates=tail(dates,3),start_date="2026-10-01",
    today=as.Date("2026-11-06"),max_new_dates=2,recheck_days=0)
  testthat::expect_equal(plan$date,c("2026-11-02","2026-11-01"))
  plan <- weather_archive_plan(dates,known_dates=tail(dates,3),start_date="2026-10-01",
    today=as.Date("2026-11-06"),max_new_dates=0,recheck_days=3,checked_dates="2026-11-05")
  testthat::expect_equal(plan$date,c("2026-11-03","2026-11-04"))
  testthat::expect_true(all(plan$action=="RECHECK"))
  testthat::expect_error(weather_archive_plan(dates,max_new_dates=31),"0-30")
})

testthat::test_that("archive checkpoints, retains prior-year dates and isolates failed builds", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root,recursive=TRUE),add=TRUE)
  explorer <- file.path(root,"explorer"); dir.create(explorer)
  archive <- file.path(root,"archive")
  write_payload <- function(dates) jsonlite::write_json(list(schema_version=1L,publication_mode=TRUE,
    days=lapply(dates,function(d) list(date=d,images=list()))),file.path(explorer,"daily-data.json"),auto_unbox=TRUE)
  env <- new.env(parent=globalenv())
  sys.source(file.path(project_root,"R","weather-circulation-archive.R"),envir=env)
  env$weather_renderer_signature <- function() "fixture-renderer"
  env$fail_dates <- character(); env$refreshes <- character()
  env$build_weather_circulation_cached <- function(dates,output_dir,refresh=FALSE) {
    date <- as.character(dates)
    if (refresh) env$refreshes <- c(env$refreshes,date)
    fail <- date %in% env$fail_dates
    if (!fail) {
      directory <- file.path(output_dir,date); dir.create(directory,recursive=TRUE,showWarnings=FALSE)
      for (name in c("height500.png","jet250.png","moisture.png")) writeLines(date,file.path(directory,name))
    }
    data.frame(date=date,status=if(fail) "FAILED" else "BUILT",requests=0,
      transferred_bytes=0,elapsed_seconds=0,note=if(fail) "simulated outage" else "")
  }
  write_payload(c("2026-09-29","2026-09-30","2026-10-01"))
  first <- env$update_weather_circulation_archive(explorer,archive,today=as.Date("2026-10-02"),max_new_dates=2,recheck_days=0)
  testthat::expect_equal(first$days,2)
  # The next year's Explorer may no longer include September; retained weather
  # records must survive that change independently of current PRISM navigation.
  write_payload(c("2026-10-01","2026-10-02"))
  second <- env$update_weather_circulation_archive(explorer,archive,today=as.Date("2026-10-03"),max_new_dates=1,recheck_days=0)
  manifest <- jsonlite::read_json(file.path(explorer,"circulation-manifest.json"))
  testthat::expect_equal(second$days,3)
  testthat::expect_true("2026-09-30" %in% vapply(manifest$days,`[[`,character(1),"date"))
  testthat::expect_silent(validate_weather_circulation_assets(explorer))
  env$fail_dates <- "2026-10-03"
  write_payload(c("2026-10-01","2026-10-02","2026-10-03"))
  failed <- env$update_weather_circulation_archive(explorer,archive,today=as.Date("2026-10-04"),max_new_dates=1,recheck_days=0)
  testthat::expect_equal(failed$status,"PARTIAL")
  testthat::expect_equal(failed$days,3)
  testthat::expect_equal(failed$pending,1)
  testthat::expect_true(file.exists(file.path(archive,"archive-state.rds")))
  env$fail_dates <- character()
  resumed <- env$update_weather_circulation_archive(explorer,archive,today=as.Date("2026-10-04"),max_new_dates=1,recheck_days=0)
  testthat::expect_equal(resumed$days,4)
  testthat::expect_equal(resumed$pending,0)
  env$update_weather_circulation_archive(explorer,archive,today=as.Date("2026-10-04"),max_new_dates=0,recheck_days=3)
  testthat::expect_equal(sort(env$refreshes),c("2026-10-01","2026-10-02"))
  env$refreshes <- character()
  env$update_weather_circulation_archive(explorer,archive,today=as.Date("2026-10-04"),max_new_dates=0,recheck_days=3)
  testthat::expect_length(env$refreshes,0)
  # A damaged archived PNG is removed from the known set and repaired on resume.
  writeLines("bad",file.path(archive,"daily","2026-10-02","height500.png"))
  repaired <- env$update_weather_circulation_archive(explorer,archive,today=as.Date("2026-10-04"),max_new_dates=1,recheck_days=0)
  testthat::expect_equal(repaired$days,4)
  testthat::expect_equal(repaired$built,1)
  env$weather_renderer_signature <- function() "new-renderer"
  changed <- env$update_weather_circulation_archive(explorer,archive,today=as.Date("2026-10-04"),max_new_dates=1,recheck_days=0)
  testthat::expect_equal(changed$days,4) # Keep verified prior images while rebuilding in batches.
  testthat::expect_equal(changed$built,1)
  testthat::expect_equal(changed$pending,2)
  testthat::expect_error(env$backfill_weather_circulation_archive(explorer,archive,batch_size=0),"1-30")
})
