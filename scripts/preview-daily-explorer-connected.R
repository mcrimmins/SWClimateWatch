source("scripts/load-daily-explorer-connected.R")
url<-"http://127.0.0.1:8805/"
response<-tryCatch(httr2::request(paste0(url,"connected-catalog.json"))|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)) {
  if(!isTRUE(httr2::resp_body_json(response)$connected_explorer))stop("Port 8805 belongs to another preview.")
  # Restart this session's server so a changed source choice uses the new mounts.
  if(exists("connected_server",inherits=FALSE)){httpuv::stopServer(connected_server);connected_server<-serve_connected_explorer()}
  else if(!identical(httr2::resp_header(response,"x-swc-connected-preview"),"multi-year-v3"))stop("An older preview server owns port 8805. Stop it in the R session that started it, then rerun this preview script.")
}else connected_server<-serve_connected_explorer()
if(interactive())utils::browseURL(url)
message("Connected current/archive review: ",url)
message("Local cache dates can be older than production. To stop: httpuv::stopServer(connected_server).")
