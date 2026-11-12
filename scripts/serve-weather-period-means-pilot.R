directory<-"data/diagnostics/weather-period-means-pilot"
if(!file.exists(file.path(directory,"index.html")))stop("Run scripts/run-weather-period-means-pilot.R first.")
url<-"http://127.0.0.1:8781/"
response<-tryCatch(httr2::request(url)|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)) {
  if(!grepl("<title>Weather period means</title>",httr2::resp_body_string(response),fixed=TRUE))stop("Port 8781 is in use by another preview.")
} else weather_period_server<-servr::httd(directory,host="127.0.0.1",port=8781L,browser=FALSE,daemon=TRUE)
if(interactive())utils::browseURL(url)
message("Weather period means preview: ",url)
