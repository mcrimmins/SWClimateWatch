testthat::test_file("tests/testthat/test-streamflow-network.R",stop_on_failure=TRUE)
source("scripts/test-streamflow-pilot.R")
root<-"data/diagnostics/streamflow-network-pilot"
if(file.exists(file.path(root,"eligibility.csv"))) {
  e<-read.csv(file.path(root,"eligibility.csv"));p<-jsonlite::read_json(file.path(root,"viewer/streamflow-data.json"))
  stopifnot(nrow(e)==32L,!anyDuplicated(e$id),isTRUE(p$network_assessment),p$configured_gauges==32L)
  for(g in p$gauges) {
    d<-jsonlite::read_json(file.path(root,"viewer",g$hydrograph))
    stopifnot(identical(d$id,g$id),length(d$rows)==90L,identical(d$rows[[90]]$date,p$cutoff))
    n<-read.csv(file.path(root,"viewer/normals",paste0(g$id,".csv")))
    if(identical(g$eligibility,"ELIGIBLE"))stopifnot(sum(n$supported)>=330L,g$historical_samples>=30L)
    x<-read.csv(file.path(root,"viewer",g$csv));stopifnot(nrow(x)==90L,identical(as.character(x$date),vapply(d$rows,`[[`,character(1),"date")))
  }
  message("PASS: 32-gauge assessment, eligibility thresholds, CSV dates and 90-day hydrographs.")
}
