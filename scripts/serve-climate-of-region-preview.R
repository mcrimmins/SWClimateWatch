if (!file.exists("site/_site/pages/climate-of-region.html")) stop("Run scripts/preview-climate-of-region.R first.")
url <- "http://127.0.0.1:8788/"
response <- tryCatch(httr2::request(url) |> httr2::req_timeout(2) |>
  httr2::req_error(is_error = function(x) FALSE) |> httr2::req_perform(), error = function(e) NULL)
if (!is.null(response)) {
  body <- tryCatch(httr2::resp_body_string(response), error = function(e) "")
  if (httr2::resp_status(response) != 200L || !grepl("Southwest Climate Watch", body, fixed = TRUE))
    stop("Port 8788 is in use by another preview.")
} else climate_region_preview_server <- servr::httd("site/_site",
  host = "127.0.0.1", port = 8788L, browser = FALSE, daemon = TRUE)
page <- paste0(url, "pages/climate-of-region.html")
if (interactive()) utils::browseURL(page)
message("Climate of the Region local preview: ", page, ". No publication.")
