directory <- file.path("data", "diagnostics", "daily-explorer")
if (!file.exists(file.path(directory, "index.html"))) {
  stop("Build the daily explorer first: source('scripts/build-daily-explorer.R').")
}
if (!requireNamespace("servr", quietly = TRUE)) stop("Install the R package servr first.")
swc_daily_explorer_server <- servr::httd(
  dir = directory, host = "127.0.0.1", port = 8766L,
  browser = TRUE, daemon = TRUE
)
