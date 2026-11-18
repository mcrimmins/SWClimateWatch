folder <- "data/diagnostics/interactive-map-snow-pilot"
if (!file.exists(file.path(folder, "manifest.json"))) stop("Run scripts/build-interactive-map-snow-pilot.R first.")
port <- getOption("swc.interactive.snow.port", 8794L)
url <- paste0("http://127.0.0.1:", port, "/")
response <- tryCatch(httr2::request(url) |> httr2::req_timeout(2) |> httr2::req_perform(), error = function(e) NULL)
if (is.null(response)) interactive_snow_server <- servr::httd(folder, host = "127.0.0.1", port = port, browser = FALSE, daemon = TRUE) else {
  remote <- tryCatch(jsonlite::fromJSON(paste0(url, "manifest.json")), error = function(e) NULL)
  if (is.null(remote$current$variables$snow)) stop("Port is occupied; set options(swc.interactive.snow.port=8795L).")
}
if (interactive()) utils::browseURL(url)
message("Snow viewer pilot: ", url, " Keep this R session open. Nothing published.")
