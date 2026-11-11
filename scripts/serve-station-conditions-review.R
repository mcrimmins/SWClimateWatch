# Preview the integrated Station Conditions build without publishing.
directory <- file.path("data","diagnostics","acis-stations","station-explorer-prototype")
if (!file.exists(file.path(directory,"index.html")))
  stop("Run scripts/build-acis-station-explorer-prototype.R first.")
port <- 8778L
url <- sprintf("http://127.0.0.1:%d/",port)
response <- tryCatch(httr2::request(url) |> httr2::req_timeout(2) |>
  httr2::req_error(is_error=function(x)FALSE) |> httr2::req_perform(),error=function(e)NULL)
if (!is.null(response)) {
  body <- tryCatch(httr2::resp_body_string(response),error=function(e)"")
  if (httr2::resp_status(response)!=200L || !grepl('id="explorer-data"',body,fixed=TRUE))
    stop("Port 8778 is in use by another preview.")
} else {
  station_conditions_review_server <- servr::httd(dir=directory,
    host="127.0.0.1",port=port,browser=FALSE,daemon=TRUE)
}
if (interactive()) utils::browseURL(url)
message("Integrated Station Conditions preview: ",url,". No publication.")
