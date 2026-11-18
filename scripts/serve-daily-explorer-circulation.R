directory <- file.path("data","diagnostics","daily-explorer-circulation")
if (!file.exists(file.path(directory,"index.html"))) stop("Run scripts/build-daily-explorer-circulation-preview.R first.")
if (!requireNamespace("servr",quietly=TRUE)) stop("Install the R package servr first.")
swc_circulation_server <- servr::httd(dir=directory,host="127.0.0.1",port=8767L,
  browser=TRUE,daemon=TRUE)
