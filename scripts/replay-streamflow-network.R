source("scripts/load-streamflow-network.R")
streamflow_network_replay <- run_streamflow_network(
  cutoff=getOption("swc.streamflow.network.cutoff",Sys.Date()-1L),mode="cache_replay",download=FALSE)
