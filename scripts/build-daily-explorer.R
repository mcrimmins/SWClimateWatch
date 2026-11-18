# Local prototype only. Reuses processed PRISM inputs; no requests or S3 sync.
source("scripts/load-daily-explorer.R")
swc_daily_explorer <- build_daily_explorer()
message("Daily Explorer ready: ", swc_daily_explorer$page)
message("Run source('scripts/serve-daily-explorer.R') to open it.")
