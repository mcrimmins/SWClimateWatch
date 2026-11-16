folder <- "data/diagnostics/interactive-map-pilot"
if (!file.exists(file.path(folder, "manifest.json"))) stop("Run scripts/build-interactive-map-pilot.R first.")
url <- "http://127.0.0.1:8790/"
response <- tryCatch(httr2::request(url) |> httr2::req_timeout(2) |>
  httr2::req_error(is_error = function(x) FALSE) |> httr2::req_perform(), error = function(e) NULL)
if (!is.null(response)) {
  if (httr2::resp_status(response) != 200L || !grepl("SWC Interactive Map Pilot", httr2::resp_body_string(response), fixed = TRUE))
    stop("Port 8790 is in use by another preview. Stop that preview first.")
} else interactive_map_pilot_server <- servr::httd(folder, host = "127.0.0.1", port = 8790L, browser = FALSE, daemon = TRUE)
if (interactive()) utils::browseURL(url)
message("Interactive map local preview: ", url, ". Keep this R session open; no publication.")
