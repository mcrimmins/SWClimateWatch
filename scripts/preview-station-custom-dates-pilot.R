# Local HTTP is needed for on-demand annual JSON files and the browser worker.
serve_station_custom_dates_pilot <- function(port = 8784L, browser = interactive()) {
  directory <- "data/diagnostics/station-custom-dates-pilot"
  if (!file.exists(file.path(directory, "catalog.json"))) stop("Run scripts/build-station-custom-dates-pilot.R first.")
  if (length(port) != 1L || !is.numeric(port) || !is.finite(port) || port < 1024L || port > 65535L || port != as.integer(port)) stop("Invalid preview port.")
  url <- sprintf("http://127.0.0.1:%d/", port)
  response <- tryCatch(httr2::request(paste0(url, "index.html")) |>
    httr2::req_timeout(2) |> httr2::req_error(is_error = function(r) FALSE) |> httr2::req_perform(), error = function(e) NULL)
  if (!is.null(response)) {
    if (httr2::resp_status(response) == 200L && grepl("<title>Station custom date pilot</title>", httr2::resp_body_string(response), fixed = TRUE)) {
      if (browser) utils::browseURL(url)
      message("Custom-date pilot already running: ", url, " Refresh after rebuilding.")
      return(invisible(list(url = url, reused = TRUE)))
    }
    stop("Port ", port, " belongs to another service. Use serve_station_custom_dates_pilot(port = 8785).")
  }
  if (!requireNamespace("servr", quietly = TRUE)) stop("Install the R package servr for the local preview.")
  server <- servr::httd(dir = directory, host = "127.0.0.1", port = as.integer(port), browser = browser, daemon = TRUE)
  message("Custom-date pilot: ", url)
  invisible(server)
}
swc_station_custom_dates_server <- serve_station_custom_dates_pilot()
