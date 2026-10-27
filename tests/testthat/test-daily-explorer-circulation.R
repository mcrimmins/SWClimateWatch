testthat::test_that("circulation render cache verifies inputs, renderer and PNG hashes", {
  env <- new.env(parent=globalenv())
  sys.source(file.path(project_root,"R","daily-explorer-circulation.R"),envir=env)
  env$weather_core_decode <- function(...) NULL
  env$weather_core_grid <- env$weather_gaussian_latitudes <- env$weather_contour_labels <-
    env$weather_streamlines <- function(...) NULL
  env$weather_core_download <- function(date,directory) {
    dir.create(directory,recursive=TRUE,showWarnings=FALSE)
    path <- file.path(directory,"source.grb"); writeBin(charToRaw("source"),path)
    list(plan=data.frame(date=as.character(date)),paths=path,requests=0,transferred_bytes=0)
  }
  env$weather_circulation_plot <- function(rasters,date,directory) {
    for (file in c("height500.png","jet250.png")) writeBin(charToRaw("map"),file.path(directory,file))
  }
  root <- tempfile(); on.exit(unlink(root,recursive=TRUE),add=TRUE)
  date <- as.Date("2026-10-03")
  testthat::expect_equal(env$build_weather_circulation_pair_cached(date,root)$status,"BUILT")
  testthat::expect_equal(env$build_weather_circulation_pair_cached(date,root)$status,"REUSED")
  writeBin(charToRaw("corrupted"),file.path(root,as.character(date),"height500.png"))
  testthat::expect_equal(env$build_weather_circulation_pair_cached(date,root)$status,"BUILT")
  env$weather_circulation_plot <- function(rasters,date,directory) {
    for (file in c("height500.png","jet250.png")) writeBin(charToRaw("new renderer"),file.path(directory,file))
  }
  testthat::expect_equal(env$build_weather_circulation_pair_cached(date,root)$status,"BUILT")
  env$weather_core_download <- function(...) stop("simulated network failure")
  result <- env$build_weather_circulation_pair_cached(date,root)
  testthat::expect_equal(result$status,"FAILED")
  testthat::expect_match(result$note,"network failure")
})

testthat::test_that("three-map cache reuses moisture, repairs damage and isolates failures", {
  env <- new.env(parent=globalenv())
  sys.source(file.path(project_root,"R","daily-explorer-circulation.R"),envir=env)
  root <- tempfile(); dir.create(root); on.exit(unlink(root,recursive=TRUE),add=TRUE)
  date <- as.Date("2026-10-03"); directory <- file.path(root,as.character(date)); dir.create(directory)
  env$weather_renderer_signature <- function() "fixture"
  env$build_weather_circulation_pair_cached <- function(...) data.frame(date=as.character(date),
    status="REUSED",requests=0,transferred_bytes=0,elapsed_seconds=0,note="")
  env$calls <- 0L; env$refresh_seen <- FALSE
  env$run_weather_moisture_pilot <- function(dates,output_dir,refresh=FALSE) {
    env$calls <- env$calls+1L; env$refresh_seen <- refresh
    writeLines("source",file.path(directory,"day-flx-source.grb"))
    path <- file.path(directory,"pwat-mslp-wind850.png"); writeLines("map",path)
    list(summary=data.frame(requests=if(refresh) 22 else 0,transferred_bytes=100,
      map=path,map_reused=refresh))
  }
  testthat::expect_equal(env$build_weather_circulation_cached(date,root)$status,"BUILT")
  testthat::expect_equal(env$build_weather_circulation_cached(date,root)$status,"REUSED")
  testthat::expect_equal(env$calls,1L)
  writeLines("damaged",file.path(directory,"moisture.png"))
  testthat::expect_equal(env$build_weather_circulation_cached(date,root)$status,"BUILT")
  checked <- env$build_weather_circulation_cached(date,root,refresh=TRUE)
  testthat::expect_true(env$refresh_seen)
  testthat::expect_equal(checked$requests,22)
  testthat::expect_equal(checked$status,"REUSED")
  env$run_weather_moisture_pilot <- function(...) stop("moisture outage")
  failed <- env$build_weather_circulation_cached(date,root,refresh=TRUE)
  testthat::expect_equal(failed$status,"FAILED")
  testthat::expect_match(failed$note,"moisture outage")
})
