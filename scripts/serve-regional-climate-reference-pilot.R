directory <- "data/diagnostics/regional-climate-reference-pilot"
if (!file.exists(file.path(directory, "index.html"))) stop("Run scripts/build-regional-climate-reference-pilot.R first.")
url <- "http://127.0.0.1:8786/"
response <- tryCatch(httr2::request(url) |> httr2::req_timeout(2) |>
  httr2::req_error(is_error = function(x) FALSE) |> httr2::req_perform(), error = function(e) NULL)
if (!is.null(response)) {
  body <- tryCatch(httr2::resp_body_string(response), error = function(e) "")
  if (httr2::resp_status(response) != 200L || !grepl("<title>Regional climate reference pilot</title>", body, fixed = TRUE))
    stop("Port 8786 is in use by another preview.")
} else regional_reference_server <- servr::httd(directory,
  host = "127.0.0.1", port = 8786L, browser = FALSE, daemon = TRUE)
if (interactive()) utils::browseURL(url)
message("Regional climate reference preview: ", url, ". No publication.")
