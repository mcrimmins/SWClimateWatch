directories<-c("data/diagnostics/streamflow-pilot","data/diagnostics/streamflow-network-pilot/viewer")
directories<-directories[file.exists(file.path(directories,"streamflow-data.json"))]
if(!length(directories))stop("Build a local streamflow pilot first.")
for(directory in directories) {
if(!identical(jsonlite::read_json(file.path(directory,"streamflow-data.json"))$pilot,"swc-streamflow"))
  stop("Unexpected local streamflow pilot: ",directory)
for(asset in c("index.html","streamflow.css","streamflow.js","streamflow-model.js","streamflow-explorer-model.js")) {
  if(!file.copy(file.path("scripts/streamflow-assets",asset),file.path(directory,asset),overwrite=TRUE))
    stop("Could not refresh local pilot asset: ",asset)
}
message("Refreshed local streamflow browser assets: ",directory)
}
message("Refreshed local streamflow browser assets. Observations and historical statistics unchanged; no downloads.")
