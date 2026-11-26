source("scripts/load-daily-explorer-wy2026.R")
wy2026_preview<-file.path(wy2026_explorer_root(),"preview")
if(!file.exists(file.path(wy2026_preview,"wy2026-release.json")))
  stop("Build the WY2026 navigation first: source('scripts/build-daily-explorer-wy2026-navigation.R').")
validate_wy2026_explorer_navigation(wy2026_preview,require_complete=isTRUE(getOption("swc.wy2026.require_complete",TRUE)))
url<-"http://127.0.0.1:8808/"
response<-tryCatch(httr2::request(paste0(url,"archive-catalog.json"))|>httr2::req_timeout(2)|>httr2::req_perform(),error=function(e)NULL)
if(!is.null(response)) {
  if(!isTRUE(httr2::resp_body_json(response)$wy2026_pilot))stop("Port 8808 belongs to another preview.")
}else wy2026_server<-servr::httd(wy2026_preview,host="127.0.0.1",port=8808L,browser=FALSE,daemon=TRUE)
if(interactive())utils::browseURL(url)
message("WY2026 local archive: ",url)
