source("scripts/load-daily-explorer-wy2025.R")
wy2025_preview<-build_wy2025_explorer_navigation(require_complete=isTRUE(getOption("swc.wy2025.require_complete",TRUE)))
url<-"http://127.0.0.1:8804/"
response<-tryCatch(httr2::request(paste0(url,"archive-catalog.json"))|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)) {
  if(!isTRUE(httr2::resp_body_json(response)$wy2025_pilot))stop("Port 8804 belongs to another preview.")
}else wy2025_server<-servr::httd(wy2025_preview,host="127.0.0.1",port=8804L,browser=FALSE,daemon=TRUE)
if(interactive())utils::browseURL(url)
message("WY2025 local month archive: ",url)
