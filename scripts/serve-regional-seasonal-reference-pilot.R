directory <- "data/diagnostics/regional-seasonal-reference-pilot"
if (!file.exists(file.path(directory, "index.html"))) stop("Run scripts/build-regional-seasonal-reference-pilot.R first.")
url <- "http://127.0.0.1:8787/"
response <- tryCatch(httr2::request(url) |> httr2::req_timeout(2) |>
  httr2::req_error(is_error = function(x) FALSE) |> httr2::req_perform(), error = function(e) NULL)
if (!is.null(response)) {
  body <- tryCatch(httr2::resp_body_string(response), error = function(e) "")
  if (httr2::resp_status(response) != 200L || !grepl("<title>Annual and seasonal regional climate reference</title>", body, fixed = TRUE))
    stop("Port 8787 is in use by another preview.")
} else regional_seasonal_reference_server <- servr::httd(directory,
  host = "127.0.0.1", port = 8787L, browser = FALSE, daemon = TRUE)
if (interactive()) utils::browseURL(url)
message("Annual and seasonal reference preview: ", url, ". No publication.")
