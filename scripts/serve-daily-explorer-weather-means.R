directory<-"data/diagnostics/daily-explorer-weather-means"
if(!file.exists(file.path(directory,"daily-data.json")))stop("Run scripts/build-daily-explorer-weather-means-preview.R first.")
url<-"http://127.0.0.1:8782/"
response<-tryCatch(httr2::request(paste0(url,"daily-data.json"))|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)) {
  payload<-tryCatch(httr2::resp_body_json(response),error=function(e)NULL)
  if(!isTRUE(payload$circulation_period_means_preview))stop("Port 8782 is occupied by another preview.")
} else weather_means_explorer_server<-servr::httd(directory,host="127.0.0.1",port=8782L,browser=FALSE,daemon=TRUE)
if(interactive())utils::browseURL(url)
message("Daily Explorer with weather means: ",url)
