if (!file.exists("site/_site/pages/interactive-maps.html")) stop("Render scripts/preview-interactive-map-site.R first.")
url <- "http://127.0.0.1:8791/"
response <- tryCatch(httr2::request(paste0(url, "pages/interactive-maps.html")) |> httr2::req_timeout(2) |>
  httr2::req_error(is_error = function(x) FALSE) |> httr2::req_perform(), error = function(e) NULL)
if (!is.null(response)) {
  if (httr2::resp_status(response) != 200L || !grepl("interactive-map-frame", httr2::resp_body_string(response), fixed = TRUE))
    stop("Port 8791 is in use by another preview. Stop it first.")
} else interactive_map_site_server <- servr::httd("site/_site", host = "127.0.0.1", port = 8791L, browser = FALSE, daemon = TRUE)
page <- paste0(url, "pages/interactive-maps.html")
if (interactive()) utils::browseURL(page)
message("Local site preview: ", page, ". Keep this R session open. No publication.")
