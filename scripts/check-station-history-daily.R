source("R/station-history-integration.R")
summary <- read.csv("data/diagnostics/station-custom-dates-pilot/daily-summary.csv",stringsAsFactors=FALSE)
print(summary,row.names=FALSE)
if(nrow(summary)!=1L || summary$status!="READY" || !isTRUE(summary$staged))stop("Historical station refresh/staging did not complete.")
for(root in c("site/stations","site/_site/stations")) {
  result <- validate_station_history_integration(root)
  dates <- unique(read.csv(file.path(root,"station-explorer-data.csv"),stringsAsFactors=FALSE)$as_of)
  if(!identical(as.character(dates),as.character(summary$page_date)))stop("History daily result and published station page dates differ.")
  print(result,row.names=FALSE)
}
staged_hash <- unname(tools::md5sum("site/stations/history-checksums.csv"))
rendered_hash <- unname(tools::md5sum("site/_site/stations/history-checksums.csv"))
if(!identical(staged_hash,rendered_hash))stop("Rendered history differs from the latest staged history.")
message("PASS: historical station refresh matches staged/rendered page date ",summary$page_date,".")
