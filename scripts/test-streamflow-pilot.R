testthat::test_file("tests/testthat/test-streamflow-pilot.R",stop_on_failure=TRUE)
testthat::test_file("tests/testthat/test-streamflow-statistics.R",stop_on_failure=TRUE)
source("scripts/find-streamflow-test-node.R")
node<-find_streamflow_test_node(required=FALSE)
if(!nzchar(node)) {
  message("R checks passed. Optional JavaScript checks: set options(swc.streamflow.node='C:/path/to/node.exe') and rerun.")
} else {
  for(asset in c("streamflow.js","streamflow-model.js"))
    if(system2(node,c("--check",shQuote(file.path("scripts/streamflow-assets",asset))))!=0L)stop("Streamflow browser syntax check failed.")
  if(system2(node,shQuote("tests/streamflow-model.cjs"))!=0L)stop("Streamflow browser model checks failed.")
}
payload<-"data/diagnostics/streamflow-pilot/streamflow-data.json"
if(file.exists(payload)) {
  p<-jsonlite::read_json(payload)
  stopifnot(identical(p$pilot,"swc-streamflow"),length(p$gauges)>0L,!anyDuplicated(vapply(p$gauges,`[[`,character(1),"id")))
  for(g in p$gauges) {
    stopifnot(g$state%in%c("AZ","NM"),is.numeric(g$lat),is.numeric(g$lon),
      grepl("^hydrographs/USGS-[0-9]+[.]json$",g$hydrograph))
    d<-jsonlite::read_json(file.path(dirname(payload),g$hydrograph))
    stopifnot(identical(d$id,g$id),length(d$rows)==90L,
      identical(d$rows[[90]]$date,p$cutoff),!anyDuplicated(vapply(d$rows,`[[`,character(1),"date")))
  }
  message("PASS: local pilot payload and ",length(p$gauges)," 90-day hydrographs.")
}
