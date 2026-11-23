directory<-"data/diagnostics/daily-explorer-nws-hazards"
if(!file.exists(file.path(directory,"hazard-timeline.json")))stop("Build scripts/build-daily-explorer-nws-hazards.R first.")
url<-"http://127.0.0.1:8798/"
response<-tryCatch(httr2::request(paste0(url,"daily-data.json"))|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)){
  if(!isTRUE(httr2::resp_body_json(response)$nws_hazards_preview))stop("Port 8798 belongs to another preview.")
}else nws_hazards_explorer_server<-servr::httd(directory,host="127.0.0.1",port=8798L,browser=FALSE,daemon=TRUE)
if(interactive())utils::browseURL(url)
message("Daily Explorer + reports + hazards: ",url)
