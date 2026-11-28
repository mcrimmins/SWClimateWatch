source("R/streamflow-transfer.R")
args<-commandArgs(trailingOnly=TRUE)
if(length(args)!=1L)stop("Usage: Rscript scripts/import-streamflow-staging.R /path/to/swc-streamflow-seed.tar.gz")
import_streamflow_transfer(args[[1]],apply=TRUE)
