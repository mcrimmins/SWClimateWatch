# Run after build-station-cumulative-pilot.R from the project root.
serve_station_cumulative_pilot <- function(port = 8770L, browser = interactive()) {
  directory <- file.path("data", "diagnostics", "station-cumulative-pilot")
  if (!file.exists(file.path(directory, "index.html"))) stop("Build the cumulative pilot first.")
  if (length(port) != 1L || !is.numeric(port) || is.na(port) || !is.finite(port) ||
      port < 1024L || port > 65535L || port != as.integer(port)) stop("Invalid preview port.")
  url <- sprintf("http://127.0.0.1:%d/", port)
  # Verify this is our preview rather than assuming any occupied port is safe
  # to reuse. Do not terminate a server owned by RStudio or another application.
  response <- tryCatch(httr2::request(paste0(url, "index.html")) |>
    httr2::req_timeout(2) |>
    httr2::req_error(is_error = function(response) FALSE) |>
    httr2::req_perform(), error = function(error) NULL)
  if (!is.null(response)) {
    html <- tryCatch(httr2::resp_body_string(response), error = function(error) "")
    if (httr2::resp_status(response) == 200L &&
        grepl("<title>Station cumulative precipitation", html, fixed = TRUE) &&
        grepl('src="cumulative.js', html, fixed = TRUE)) {
      message("Cumulative pilot is already running: ", url, " Refresh the browser after rebuilding.")
      if (browser) utils::browseURL(url)
      return(invisible(list(url = url, reused = TRUE)))
    }
    stop("Port ", port, " is being used by another local service. Use ",
         "serve_station_cumulative_pilot(port = 8771) to choose another port.")
  }
  if (!requireNamespace("servr", quietly = TRUE)) stop("Install the R package servr to serve the pilot.")
  tryCatch(servr::httd(dir = directory, host = "127.0.0.1", port = as.integer(port),
    browser = browser, daemon = TRUE), error = function(error) {
      stop("Could not start the preview on port ", port, ". If it is occupied, use ",
           "serve_station_cumulative_pilot(port = 8771). Details: ", conditionMessage(error), call. = FALSE)
    })
}

swc_station_cumulative_server <- serve_station_cumulative_pilot()
