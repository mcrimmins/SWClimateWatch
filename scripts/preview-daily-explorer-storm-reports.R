directory<-"data/diagnostics/daily-explorer-storm-reports"
if(!file.exists(file.path(directory,"storm-reports-manifest.json")))
  stop("Build scripts/build-daily-explorer-storm-reports-pilot.R first.")
url<-"http://127.0.0.1:8796/"
response<-tryCatch(httr2::request(paste0(url,"daily-data.json"))|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)) {
  payload<-tryCatch(httr2::resp_body_json(response),error=function(e)NULL)
  if(!isTRUE(payload$storm_reports_preview))stop("Port 8796 is occupied by another preview.")
} else storm_reports_server<-servr::httd(directory,host="127.0.0.1",port=8796L,browser=FALSE,daemon=TRUE)
if(interactive())utils::browseURL(url)
message("Local storm reports: ",url)
