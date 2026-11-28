network_root<-normalizePath(testthat::test_path("../.."),winslash="/",mustWork=TRUE)
source(file.path(network_root,"R/streamflow-pilot.R"))
source(file.path(network_root,"R/streamflow-statistics.R"))
source(file.path(network_root,"R/streamflow-network.R"))
network_feature<-function(date,value="1")list(type="Feature",properties=list(
  monitoring_location_id="USGS-09506000",time_series_id="series",parameter_code="00060",statistic_id="00003",
  unit_of_measure="ft^3/s",time=date,value=value,approval_status="Provisional"),geometry=list(coordinates=list(-111,34)))

testthat::test_that("the strategic network contains 16 unique gauges per state",{
  x<-streamflow_network_sites()
  testthat::expect_equal(nrow(x),32L)
  testthat::expect_equal(anyDuplicated(x$id),0L)
  testthat::expect_equal(as.integer(table(x$state)),c(16L,16L))
  testthat::expect_true(all(streamflow_sites()$id%in%x$id))
  testthat::expect_error(run_streamflow_network(as.Date("2026-11-26"),"incremental_live",FALSE),"requires downloads")
})

testthat::test_that("revision windows replace missing and revised days without filling gaps",{
  old<-streamflow_rows(list(network_feature("2026-11-01"),network_feature("2026-11-20","8"),network_feature("2026-11-21","2")))
  new<-streamflow_rows(list(network_feature("2026-11-21","0"),network_feature("2026-11-22","3")))
  x<-streamflow_merge_window(old,new,as.Date("2026-11-20"),as.Date("2026-11-22"),as.Date("2026-11-02"))
  testthat::expect_equal(x$date,c("2026-11-21","2026-11-22"))
  testthat::expect_equal(x$cfs,c(0,3))
})

testthat::test_that("incremental updates force a short recheck and retain verified data on failure",{
  directory<-tempfile();dir.create(directory);on.exit(unlink(directory,recursive=TRUE))
  events<-new.env();events$rows<-list();seen<-list()
  initial<-function(collection,query,refresh_override){seen[[length(seen)+1L]]<<-list(query=query,refresh=refresh_override);list(network_feature("2026-11-25"))}
  p<-streamflow_network_provider(directory,"bootstrap",TRUE,events)
  p("USGS-09506000","series",as.Date("2026-08-28"),as.Date("2026-11-25"),initial)
  testthat::expect_false(seen[[1]]$refresh)
  p<-streamflow_network_provider(directory,"incremental_live",TRUE,events)
  p("USGS-09506000","series",as.Date("2026-08-29"),as.Date("2026-11-26"),initial)
  testthat::expect_true(seen[[2]]$refresh)
  testthat::expect_equal(seen[[2]]$query$datetime,"2026-11-13/2026-11-27")
  testthat::expect_equal(events$rows[[2]]$old_through,"2026-11-25")
  testthat::expect_equal(events$rows[[2]]$changed_dates,0L)
  failed<-function(...)stop("network unavailable")
  x<-p("USGS-09506000","series",as.Date("2026-08-30"),as.Date("2026-11-27"),failed)
  testthat::expect_equal(attr(x,"refresh_status"),"STALE_RETAINED")
  testthat::expect_equal(readRDS(file.path(directory,"USGS-09506000.rds"))$through,"2026-11-26")
  # Content corruption is never accepted as a recovery source.
  saveRDS(list(bad=TRUE),file.path(directory,"USGS-09506000.rds"))
  testthat::expect_error(p("USGS-09506000","series",as.Date("2026-08-30"),as.Date("2026-11-27"),failed),"network unavailable")
})
