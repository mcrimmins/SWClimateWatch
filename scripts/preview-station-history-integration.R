serve_station_history_integration <- function(port = 8786L, browser = interactive()) {
  directory <- "data/diagnostics/station-history-integration"
  if (!file.exists(file.path(directory, "index.html"))) stop("Build the integrated station preview first.")
  if (length(port) != 1L || !is.numeric(port) || !is.finite(port) || port < 1024L || port > 65535L || port != as.integer(port)) stop("Invalid preview port.")
  url <- sprintf("http://127.0.0.1:%d/", port)
  response <- tryCatch(httr2::request(paste0(url, "index.html")) |>
    httr2::req_timeout(2) |> httr2::req_error(is_error = function(r) FALSE) |> httr2::req_perform(), error = function(e) NULL)
  if (!is.null(response)) {
    text <- tryCatch(httr2::resp_body_string(response), error = function(e) "")
    if (httr2::resp_status(response) == 200L && grepl('src="station-history-tabs.js"', text, fixed = TRUE)) {
      if (browser) utils::browseURL(url)
      message("Integrated station history preview already running: ", url, " Refresh after rebuilding.")
      return(invisible(list(url = url, reused = TRUE)))
    }
    stop("Port ", port, " belongs to another service. Use serve_station_history_integration(port = 8787).")
  }
  if (!requireNamespace("servr", quietly = TRUE)) stop("Install servr to serve the local preview.")
  server <- servr::httd(dir = directory, host = "127.0.0.1", port = as.integer(port), browser = browser, daemon = TRUE)
  message("Integrated station history preview: ", url)
  invisible(server)
}
swc_station_history_server <- serve_station_history_integration()
