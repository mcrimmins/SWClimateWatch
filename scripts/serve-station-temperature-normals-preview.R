# Serve diagnostics over localhost so the existing seasonal files can be reused.
serve_station_temperature_normals_preview <- function(port=8776L,browser=interactive()) {
  stopifnot(length(port)==1L,is.finite(port),port==as.integer(port),port>=1024L,port<=65535L)
  root<-"data/diagnostics"
  page<-"station-temperature-normals-preview/index.html"
  if(!file.exists(file.path(root,page)))stop("Build the temperature normals preview first.")
  url<-sprintf("http://127.0.0.1:%d/station-temperature-normals-preview/",port)
  response<-tryCatch(httr2::request(paste0(url,"index.html"))|>
    httr2::req_timeout(2)|>httr2::req_error(is_error=function(x)FALSE)|>httr2::req_perform(),error=function(e)NULL)
  if(!is.null(response)) {
    html<-tryCatch(httr2::resp_body_string(response),error=function(e)"")
    if(httr2::resp_status(response)==200L && grepl('content="station-temperature-normals"',html,fixed=TRUE)) {
      if(browser)utils::browseURL(url)
      message("Temperature normals preview already running: ",url)
      return(invisible(list(url=url,reused=TRUE)))
    }
    stop("Port is in use; try serve_station_temperature_normals_preview(port=8777).")
  }
  servr::httd(dir=root,host="127.0.0.1",port=as.integer(port),browser=FALSE,daemon=TRUE)
  if(browser)utils::browseURL(url)
  message("Temperature normals preview: ",url)
  invisible(list(url=url,reused=FALSE))
}

station_temperature_normals_server <- serve_station_temperature_normals_preview()
