source("R/streamflow-explorer.R")
validate_streamflow_explorer()
stopifnot(streamflow_explorer_response(list(REQUEST_METHOD="POST",PATH_INFO="/"))$status==405L,
  streamflow_explorer_response(list(REQUEST_METHOD="GET",PATH_INFO="/streamflow/%2e%2e/index.html"))$status==400L,
  streamflow_explorer_response(list(REQUEST_METHOD="GET",PATH_INFO="/streamflow/missing.json"))$status==404L)
head_response<-streamflow_explorer_response(list(REQUEST_METHOD="HEAD",PATH_INFO="/streamflow/streamflow-data.json"))
stopifnot(head_response$status==200L,length(head_response$body)==0L)
source("scripts/load-daily-explorer-connected.R")
sources<-streamflow_explorer_sources()
panel<-paste(readLines(file.path(streamflow_explorer_root(),"streamflow-panel.html"),warn=FALSE),collapse="\n")
injected_head<-'<link rel="stylesheet" href="/explorer-streamflow.css"><script src="/explorer-streamflow.js" defer></script>'
for(path in c("/current/index.html","/archive/wy2025/months/2025-07/index.html","/archive/wy2026/months/2026-01/index.html")){
  request<-list(REQUEST_METHOD="GET",PATH_INFO=path)
  original<-connected_explorer_response(request,sources=sources)
  integrated<-streamflow_explorer_response(request,sources=sources)
  stopifnot(original$status==200L,integrated$status==200L)
  html<-rawToChar(integrated$body)
  stopifnot(grepl('id="streamflow-panel"',html,fixed=TRUE),grepl('</html>',html,fixed=TRUE))
  # Byte-for-byte round trip protects all existing markup, including UTF-8
  # symbols, from corruption when inserting the local section.
  restored<-sub(paste0(panel,"\n"),"",html,fixed=TRUE,useBytes=TRUE)
  restored<-sub(injected_head,"",restored,fixed=TRUE,useBytes=TRUE)
  stopifnot(identical(charToRaw(restored),original$body))
}
message("PASS: inline section and byte-preserved current/WY2025/WY2026 pages.")
source("scripts/find-streamflow-test-node.R")
node<-find_streamflow_test_node()
message("Browser-controller checks using Node: ",node)
for(asset in c("streamflow.js","streamflow-explorer-model.js","explorer-streamflow.js"))
  if(system2(node,c("--check",shQuote(file.path("scripts/streamflow-assets",asset))))!=0L)stop("Browser syntax check failed: ",asset)
if(system2(node,shQuote("tests/streamflow-explorer.cjs"))!=0L)stop("Streamflow Explorer checks failed.")
source("scripts/test-streamflow-network.R")
