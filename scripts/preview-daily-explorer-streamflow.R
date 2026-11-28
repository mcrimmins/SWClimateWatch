source("R/streamflow-explorer.R")
url<-"http://127.0.0.1:8807/"
response<-tryCatch(httr2::request(paste0(url,"streamflow-release.json"))|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)){
  if(!isTRUE(httr2::resp_body_json(response)$local_streamflow_explorer))stop("Port 8807 belongs to another preview.")
}else streamflow_explorer_server<-serve_streamflow_explorer()
if(interactive())utils::browseURL(url)
message("Daily Explorer + Streamflow local review: ",url)
