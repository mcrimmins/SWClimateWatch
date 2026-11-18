# Review existing local pilot PNGs together. No downloads or publication.
directory <- file.path("data", "diagnostics", "snodas-seasonal-anomaly-pilot")
years <- c(2005L, 2018L, 2024L)
files <- unlist(lapply(years, function(year) sprintf(
  "wy%d-peak-swe-%s.png", year, c("departure", "percent-median"))))
if (!all(file.exists(file.path(directory, files))))
  stop("Run scripts/run-snodas-seasonal-anomaly-pilot.R first; six pilot PNGs are required.")

cards <- unlist(lapply(years, function(year) {
  titles <- c("Peak SWE departure", "Peak SWE percent of median")
  maps <- sprintf("wy%d-peak-swe-%s.png", year, c("departure", "percent-median"))
  paste0('<section><h2>WY', year, '</h2><div class="maps">',
    paste(sprintf('<article><h3>%s</h3><a href="%s" target="_blank" rel="noopener"><img src="%s" alt="WY%d %s"></a><p><a href="%s" target="_blank" rel="noopener">Open full-resolution PNG</a></p></article>',
      titles, maps, maps, year, titles, maps), collapse = "\n"), '</div></section>')
}))
html <- c('<!doctype html><html lang="en"><head><meta charset="utf-8">',
  '<meta name="viewport" content="width=device-width,initial-scale=1">',
  '<title>SNODAS seasonal anomaly pilot</title>',
  '<style>body{font:16px system-ui,sans-serif;color:#26363d;background:#f4f6f7;margin:0 auto;padding:24px;max-width:1600px}h1{margin-top:0}p{line-height:1.5}.maps{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}article{background:white;border:1px solid #d8e0e4;border-radius:8px;padding:12px}article h3{font-size:16px;margin:0 0 8px}img{display:block;width:100%;height:auto}a{color:#14647c}@media(max-width:800px){.maps{grid-template-columns:1fr}}</style></head><body>',
  '<h1>Historical seasonal snow anomalies</h1>',
  '<p>Local review only. Each map compares an October-May seasonal peak with the median of screened seasonal peaks from WY2005-WY2025, including the target year. Peak dates may differ among years and pixels; this is not a same-date snow comparison.</p>',
  '<p>Reference support: at least 18 years and 95% daily coverage per eligible year. Percentages require a median peak SWE of at least 1 inch; gray identifies lower medians. These are ratios, not percentiles.</p>',
  '<p>Departure maps: white marks departures within +/-1 inch where median peak SWE is at least 1 inch. Gray marks typically little snow (median peak below 1 inch) only when departure is also within +/-1 inch. Larger departures retain brown/blue colors even in low-snow areas. Beige marks unavailable data or reference support.</p>',
  '<p><a href="pilot-summary.csv">Pilot summary CSV</a> &middot; <a href="methods.csv">Methods CSV</a> &middot; <a href="source-inventory.csv">Source inventory CSV</a></p>',
  cards, '</body></html>')
writeLines(html, file.path(directory, "index.html"), useBytes = TRUE)

port <- 8783L
url <- sprintf("http://127.0.0.1:%d/", port)
response <- tryCatch(httr2::request(url) |> httr2::req_timeout(2) |>
  httr2::req_error(is_error = function(x) FALSE) |> httr2::req_perform(),
  error = function(e) NULL)
if (!is.null(response)) {
  body <- tryCatch(httr2::resp_body_string(response), error = function(e) "")
  if (httr2::resp_status(response) != 200L ||
      !grepl("<title>SNODAS seasonal anomaly pilot</title>", body, fixed = TRUE))
    stop("Port 8783 is in use by another preview; choose another port in this script.")
} else {
  snodas_seasonal_anomaly_server <- servr::httd(dir = directory,
    host = "127.0.0.1", port = port, browser = FALSE, daemon = TRUE)
}
if (interactive()) utils::browseURL(url)
message("SNODAS seasonal anomaly preview: ", url, ". No publication.")
