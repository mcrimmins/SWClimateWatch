for(file in c("acis-station-inventory.R","acis-station-daily-pilot.R","acis-station-current-prototype.R",
  "acis-station-explorer-prototype.R","station-custom-dates-pilot.R","station-history-integration.R","station-history-daily.R"))
  source(file.path(project_root,"R",file),local=TRUE)

testthat::test_that("daily history is opt-in and completes before the atomic stage", {
  withr::local_envvar(c(SWC_STATION_HISTORY="false"));testthat::expect_false(swc_station_history_enabled())
  Sys.setenv(SWC_STATION_HISTORY="true");testthat::expect_true(swc_station_history_enabled())
  Sys.setenv(SWC_STATION_HISTORY="invalid");testthat::expect_error(swc_station_history_enabled(),"Invalid")
  events <- character()
  update <- function(...) {events <<- c(events,"history");data.frame(status="READY",staged=FALSE)}
  stage <- function(...) {events <<- c(events,"stage");list(stations=1L)}
  testthat::expect_null(swc_station_beta_finish(enabled=FALSE,history_update=update,stage=stage)$history)
  testthat::expect_identical(events,"stage");events <- character()
  result <- swc_station_beta_finish(enabled=TRUE,history_update=update,stage=stage)
  testthat::expect_identical(events,c("history","stage"));testthat::expect_true(result$history$staged)
  events <- character()
  testthat::expect_error(swc_station_beta_finish(enabled=TRUE,history_update=function(...)stop("history failed"),stage=stage),"history failed")
  testthat::expect_length(events,0L)
})

testthat::test_that("daily overlay reuses years, revises affected years and rejects shorter caches", {
  withr::local_dir(project_root)
  root <- tempfile(tmpdir="data/diagnostics");dir.create(root);on.exit(unlink(root,recursive=TRUE),add=TRUE)
  src <- file.path(root,"current");dir.create(src);raw <- file.path(root,"raw");dir.create(raw)
  output <- file.path(root,"history")
  station <- data.frame(uid=1L,sid="fixture",name="Fixture",state="AZ",role="fixed")
  days <- as.Date(c("2020-12-30","2020-12-31","2021-01-01","2021-01-02"))
  daily <- do.call(rbind,lapply(c("pcpn","maxt","mint"),function(v)data.frame(date=days,variable=v,numeric_value=if(v=="pcpn")0.1 else if(v=="maxt")70 else 40,observed=TRUE,flag="",source="fixture",trace=FALSE,accumulated=FALSE)))
  cache <- list(schema_version=1L,uid=1L,sid="fixture",as_of=max(days),daily=daily)
  save <- function() {
    saveRDS(cache,file.path(raw,"1.rds"))
    write.csv(data.frame(uid=1L,as_of=as.character(cache$as_of)),file.path(src,"station-explorer-data.csv"),row.names=FALSE)
    writeLines(paste0('<script id="explorer-data" type="application/json">{"as_of":"',cache$as_of,'"}</script>'),file.path(src,"index.html"))
  }
  save();a <- swc_station_history_update(src,output,station,raw)
  testthat::expect_equal(a$built,2L);testthat::expect_false(a$staged)
  b <- swc_station_history_update(src,output,station,raw)
  testthat::expect_equal(b$built,0L);testthat::expect_equal(b$reused,2L);testthat::expect_equal(b$copied_files,0L)
  update <- function(source_dir)swc_station_history_update(source_dir,output,station,raw)
  finished <- swc_station_beta_finish(source_dir=src,enabled=TRUE,history_update=update,stage=function(...)list(stations=1L))
  testthat::expect_true(finished$history$staged)
  testthat::expect_true(read.csv(file.path(output,"daily-summary.csv"))$staged)
  testthat::expect_error(swc_station_beta_finish(source_dir=src,enabled=TRUE,history_update=update,stage=function(...)stop("stage failed")),"stage failed")
  testthat::expect_false(read.csv(file.path(output,"daily-summary.csv"))$staged)
  extra <- cache$daily[cache$daily$date==cache$as_of,];extra$date <- extra$date+1
  cache$daily <- rbind(cache$daily,extra);cache$as_of <- cache$as_of+1;save()
  c <- swc_station_history_update(src,output,station,raw)
  testthat::expect_equal(c$built,1L);testthat::expect_equal(c$reused,1L)
  cache$daily$numeric_value[cache$daily$variable=="pcpn"&cache$daily$date==days[1]] <- 0.25;save()
  d <- swc_station_history_update(src,output,station,raw)
  testthat::expect_equal(d$built,1L);testthat::expect_equal(d$reused,1L)
  testthat::expect_equal(validate_station_history_integration(src)$stations,1L)
  cache$daily <- cache$daily[cache$daily$date>=as.Date("2021-01-01"),];save()
  testthat::expect_error(swc_station_history_update(src,output,station,raw),"Refusing to shorten")
  status <- read.csv(file.path(output,"daily-summary.csv"))
  testthat::expect_identical(status$status,"ERROR");testthat::expect_false(status$staged)
})

testthat::test_that("policy signature is independent of station loader source environments", {
  withr::local_dir(project_root)
  source("R/daily-publish.R",local=TRUE)
  context <- swc_daily_publish_station_context()
  testthat::expect_identical(station_custom_policy_signature(),context$station_custom_policy_signature())
})
