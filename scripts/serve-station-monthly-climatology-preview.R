# Serve diagnostics so the pilot can reuse existing seasonal plot resources.
directory<-"data/diagnostics"
if(!file.exists(file.path(directory,"station-monthly-climatology-preview/index.html")))
  stop("Run scripts/build-station-monthly-climatology-preview.R first.")
url<-"http://127.0.0.1:8779/station-monthly-climatology-preview/"
response<-tryCatch(httr2::request(url)|>httr2::req_timeout(2)|>
  httr2::req_error(is_error=function(x)FALSE)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)) {
  html<-tryCatch(httr2::resp_body_string(response),error=function(e)"")
  if(httr2::resp_status(response)!=200L || !grepl('content="station-monthly-climatology"',html,fixed=TRUE))
    stop("Port 8779 is in use by another preview.")
} else {
  station_monthly_climatology_server<-servr::httd(dir=directory,host="127.0.0.1",port=8779L,browser=FALSE,daemon=TRUE)
}
if(interactive())utils::browseURL(url)
message("Monthly station climatology preview: ",url)
