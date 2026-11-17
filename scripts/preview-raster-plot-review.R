folder <- "data/diagnostics/raster-plot-review"
if(!file.exists(file.path(folder,"index.html")))stop("Run scripts/rebuild-raster-plot-review.R first.")
port <- getOption("swc.raster.plot.port",8793L)
url <- paste0("http://127.0.0.1:",port,"/")
response <- tryCatch(httr2::request(url)|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(is.null(response)) raster_plot_review_server <- servr::httd(folder,host="127.0.0.1",port=port,browser=FALSE,daemon=TRUE) else
  if(!grepl("Raster plotting geometry review",httr2::resp_body_string(response),fixed=TRUE))stop("Preview port is in use; set options(swc.raster.plot.port=8794L).")
if(interactive())utils::browseURL(url)
message("Raster plotting review: ",url,". Keep this R session open. No publication.")
