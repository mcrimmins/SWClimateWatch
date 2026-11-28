source("scripts/load-streamflow-network.R")
# Seed the day before the target, then benchmark a real next-day update.
streamflow_network_assessment <- run_streamflow_network(
  cutoff=getOption("swc.streamflow.network.cutoff",Sys.Date()-1L)-1L,
  mode="bootstrap",download=!identical(getOption("swc.streamflow.download",TRUE),FALSE))
