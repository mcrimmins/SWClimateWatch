# Cached template only. Publication invokes this after data/station updates.
source("R/conditions-synopsis-site.R")
synopsis_stage_args <- commandArgs(trailingOnly = TRUE)
synopsis_site_result <- stage_conditions_synopsis(destination = if (length(synopsis_stage_args)) synopsis_stage_args[[1L]] else Sys.getenv("SWC_S3_DESTINATION", "local-preview"))
