source("R/streamflow-pilot.R")
streamflow_pilot <- build_streamflow_pilot(
  cutoff=getOption("swc.streamflow.cutoff",Sys.Date()-1L),
  refresh=isTRUE(getOption("swc.streamflow.refresh",FALSE)),
  download=!identical(getOption("swc.streamflow.download",TRUE),FALSE))
source("R/streamflow-statistics.R")
streamflow_pilot$statistics <- add_streamflow_statistics(
  directory=streamflow_pilot$directory,
  download=!identical(getOption("swc.streamflow.download",TRUE),FALSE),
  refresh=isTRUE(getOption("swc.streamflow.statistics.refresh",FALSE)))
