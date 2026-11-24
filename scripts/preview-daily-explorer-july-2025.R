source("R/daily-explorer-july-pilot.R")
july_pilot_load()
validate_daily_explorer_july()
directory<-file.path(july_pilot_root(),"viewer")
url<-"http://127.0.0.1:8800/"
response<-tryCatch(httr2::request(paste0(url,"daily-data.json"))|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)) {
  if(!isTRUE(httr2::resp_body_json(response)$july_full_pilot))stop("Port 8800 belongs to another preview.")
}else july_pilot_server<-servr::httd(directory,host="127.0.0.1",port=8800L,browser=FALSE,daemon=TRUE)
if(interactive())utils::browseURL(url)
message("Full July benchmark, local only: ",url)
