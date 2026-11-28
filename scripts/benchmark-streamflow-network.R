source("scripts/load-streamflow-network.R")
streamflow_network_benchmark <- run_streamflow_network(
  cutoff=getOption("swc.streamflow.network.cutoff",Sys.Date()-1L),
  mode="incremental_live",download=!identical(getOption("swc.streamflow.download",TRUE),FALSE))
