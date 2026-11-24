source("R/daily-explorer-archive-pilot.R")
source("R/daily-explorer.R")
directory<-"data/diagnostics/daily-explorer-archive-pilot"
validate_daily_explorer_archive_pilot(directory)
url<-"http://127.0.0.1:8799/"
response<-tryCatch(httr2::request(paste0(url,"archive-catalog.json"))|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)) {
  if(!isTRUE(httr2::resp_body_json(response)$archive_pilot))stop("Port 8799 belongs to another preview.")
} else daily_archive_pilot_server<-servr::httd(directory,host="127.0.0.1",port=8799L,browser=FALSE,daemon=TRUE)
if(interactive())utils::browseURL(url)
message("Unpublished PRISM archive pilot: ",url)
