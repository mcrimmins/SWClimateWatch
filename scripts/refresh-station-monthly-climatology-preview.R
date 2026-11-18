# Refresh chart display only; retain existing monthly reference JSON files.
directory<-"data/diagnostics/station-monthly-climatology-preview"
if(!file.exists(file.path(directory,"index.html")))
  stop("Run scripts/build-station-monthly-climatology-preview.R first.")
assets<-file.path("scripts/station-monthly-climatology-assets",c("monthly-climatology.js","monthly-climatology.css"))
if(!all(file.copy(assets,directory,overwrite=TRUE)))stop("Could not refresh monthly chart assets.")
message("Monthly station charts refreshed. No reference recalculation, downloads or publication.")
