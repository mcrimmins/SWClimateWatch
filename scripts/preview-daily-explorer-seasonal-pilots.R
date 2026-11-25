source("R/daily-explorer-seasonal-pilots.R")
seasonal_explorer_load()
check_seasonal_explorer()
seasonal_urls<-character()
for(id in names(seasonal_explorer_windows())) {
  w<-seasonal_explorer_windows()[[id]]
  port<-if(id=="winter")8802L else 8803L
  url<-paste0("http://127.0.0.1:",port,"/")
  response<-tryCatch(httr2::request(paste0(url,"daily-data.json"))|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
  if(!is.null(response)) {
    if(!identical(httr2::resp_body_json(response)$seasonal_window_pilot,id))stop("Port ",port," belongs to another preview.")
  }else servr::httd(file.path(w$root,"viewer"),host="127.0.0.1",port=port,browser=FALSE,daemon=TRUE)
  seasonal_urls[id]<-url
  if(interactive())utils::browseURL(url)
  message(w$title,": ",url)
}
