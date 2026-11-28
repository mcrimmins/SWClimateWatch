# Optional local rehearsal of the exact static staging URL layout.
source("R/streamflow-staging.R")
trial<-"data/diagnostics/streamflow-staging-local/viewer"
base<-"data/diagnostics/daily-explorer-connected/static-review-two-years"
validate_streamflow_trial(trial,base)
streamflow_static_review_server<-httpuv::startServer("127.0.0.1",8810L,list(staticPaths=list(
  "/climate/watch-staging/daily-explorer/archive/wy2025"=httpuv::staticPath(normalizePath("data/diagnostics/daily-explorer-wy2025/preview",winslash="/"),indexhtml=TRUE,headers=list("Cache-Control"="no-store")),
  "/climate/watch-staging/daily-explorer/archive/wy2026"=httpuv::staticPath(normalizePath("data/diagnostics/daily-explorer-wy2026/preview",winslash="/"),indexhtml=TRUE,headers=list("Cache-Control"="no-store")),
  "/climate/watch-staging/daily-explorer/streamflow-trial"=httpuv::staticPath(normalizePath(trial,winslash="/"),indexhtml=TRUE,headers=list("Cache-Control"="no-store")),
  "/climate/watch-staging/daily-explorer"=httpuv::staticPath(normalizePath(base,winslash="/"),indexhtml=TRUE,headers=list("Cache-Control"="no-store")))))
message("Static staging rehearsal: http://127.0.0.1:8810/climate/watch-staging/daily-explorer/streamflow-trial/")
