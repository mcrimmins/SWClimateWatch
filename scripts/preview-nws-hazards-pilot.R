directory<-"data/diagnostics/nws-hazards-pilot"
if(!file.exists(file.path(directory,"catalog.json")))stop("Run scripts/build-nws-hazards-pilot.R first.")
url<-"http://127.0.0.1:8797/"
response<-tryCatch(httr2::request(paste0(url,"catalog.json"))|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)) {
  if(!isTRUE(httr2::resp_body_json(response)$pilot))stop("Port 8797 belongs to another preview.")
} else nws_hazards_server<-servr::httd(directory,host="127.0.0.1",port=8797L,browser=FALSE,daemon=TRUE)
if(interactive())utils::browseURL(url)
message("Local hazard pilot: ",url)
