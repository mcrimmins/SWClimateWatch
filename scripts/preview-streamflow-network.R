directory<-"data/diagnostics/streamflow-network-pilot/viewer"
if(!file.exists(file.path(directory,"streamflow-data.json")))stop("Build the expanded streamflow assessment first.")
url<-"http://127.0.0.1:8799/"
response<-tryCatch(httr2::request(paste0(url,"streamflow-data.json"))|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)) {
  if(!isTRUE(httr2::resp_body_json(response)$network_assessment))stop("Port 8799 belongs to another preview.")
} else streamflow_network_server<-servr::httd(directory,host="127.0.0.1",port=8799L,browser=FALSE,daemon=TRUE)
if(interactive())utils::browseURL(url)
message("Expanded local streamflow assessment: ",url)
