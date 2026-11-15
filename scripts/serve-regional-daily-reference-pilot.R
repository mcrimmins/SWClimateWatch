root <- 'data/diagnostics/regional-daily-reference-pilot'
if (!file.exists(file.path(root,'index.html'))) stop('Build the regional daily references first.')
url <- 'http://127.0.0.1:8789/'
response <- tryCatch(httr2::request(url) |> httr2::req_timeout(2) |> httr2::req_perform(),error=function(e) NULL)
if (!is.null(response)) {
  if (!grepl('Regional daily climate references',httr2::resp_body_string(response),fixed=TRUE)) stop('Port 8789 is already in use by another application.')
} else regional_daily_preview_server <- servr::httd(root,host='127.0.0.1',port=8789L,browser=FALSE,daemon=TRUE)
if (interactive()) utils::browseURL(url)
message('Local daily reference gallery: ',url,'. No publication.')
