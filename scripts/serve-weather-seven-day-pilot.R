directory<-"data/diagnostics/weather-seven-day-pilot"
if(!file.exists(file.path(directory,"index.html")))stop("Run scripts/run-weather-seven-day-pilot.R first.")
url<-"http://127.0.0.1:8780/"
response<-tryCatch(httr2::request(url)|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)) {
  if(!grepl("<title>Seven-day weather means</title>",httr2::resp_body_string(response),fixed=TRUE))stop("Port 8780 is in use by another preview.")
} else weather_mean_server<-servr::httd(directory,host="127.0.0.1",port=8780L,browser=FALSE,daemon=TRUE)
if(interactive())utils::browseURL(url)
message("Seven-day weather pilot preview: ",url)
