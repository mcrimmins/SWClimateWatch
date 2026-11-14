directory <- "data/diagnostics/snodas-historic-anomaly-preview/_site"
if (!file.exists(file.path(directory, "index.html"))) stop("Run scripts/preview-snodas-historic-anomalies.R first.")
url <- "http://127.0.0.1:8784/"
response <- tryCatch(httr2::request(url) |> httr2::req_timeout(2) |>
  httr2::req_error(is_error = function(x) FALSE) |> httr2::req_perform(), error = function(e) NULL)
if (!is.null(response)) {
  body <- tryCatch(httr2::resp_body_string(response), error = function(e) "")
  if (httr2::resp_status(response) != 200L || !grepl("Historic Snow - Local Review", body, fixed = TRUE))
    stop("Port 8784 is in use by another preview.")
} else snodas_historic_preview_server <- servr::httd(directory,
  host = "127.0.0.1", port = 8784L, browser = FALSE, daemon = TRUE)
if (interactive()) utils::browseURL(url)
message("Historic snow page review: ", url, ". No publication.")
