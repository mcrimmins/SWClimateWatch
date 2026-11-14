directory <- "site/_site"
if (!file.exists(file.path(directory, "assets/snodas-seasonal-anomalies.json")))
  stop("Run scripts/preview-snodas-seasonal-anomaly-archive.R first.")
url <- "http://127.0.0.1:8785/"
response <- tryCatch(httr2::request(url) |> httr2::req_timeout(2) |>
  httr2::req_error(is_error = function(x) FALSE) |> httr2::req_perform(), error = function(e) NULL)
if (!is.null(response)) {
  body <- tryCatch(httr2::resp_body_string(response), error = function(e) "")
  if (httr2::resp_status(response) != 200L || !grepl("Southwest Climate Watch", body, fixed = TRUE))
    stop("Port 8785 is in use by another preview.")
} else snodas_anomaly_archive_server <- servr::httd(directory,
  host = "127.0.0.1", port = 8785L, browser = FALSE, daemon = TRUE)
page <- paste0(url, "pages/archive/wy2024.html#snow-season")
if (interactive()) utils::browseURL(page)
message("Full-site historical snow preview: ", page)
