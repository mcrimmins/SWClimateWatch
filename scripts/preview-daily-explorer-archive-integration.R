source("scripts/load-daily-explorer-archive-integration.R")
directory<-"data/diagnostics/daily-explorer-archive-integrated"
validate_daily_explorer_archive_integration(directory)
url<-"http://127.0.0.1:8801/"
response<-tryCatch(httr2::request(paste0(url,"archive-catalog.json"))|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)) {
  if(!isTRUE(httr2::resp_body_json(response)$archive_integration_pilot))stop("Port 8801 belongs to another preview.")
}else archive_integrated_server<-servr::httd(directory,host="127.0.0.1",port=8801L,browser=FALSE,daemon=TRUE)
if(interactive())utils::browseURL(url)
message("Full July + archive navigation: ",url)
