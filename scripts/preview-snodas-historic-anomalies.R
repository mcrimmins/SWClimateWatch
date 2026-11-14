# Prepare and render isolated Historic Years pages. No downloads or S3 calls.
source("scripts/stage-snodas-historic-site.R")
source("R/snodas-seasonal-anomaly.R")
source("R/snodas-seasonal-anomaly-site.R")
source("scripts/deploy-site-s3.R") # Definitions only; no deployment.
snodas_historic_preview_dir <- build_snodas_historic_anomaly_preview()
snodas_historic_quarto <- swc_deploy_quarto()
if (.Platform$OS.type == "windows") snodas_historic_quarto <- utils::shortPathName(snodas_historic_quarto)
status <- system2(snodas_historic_quarto, c("render", shQuote(snodas_historic_preview_dir)),
  stdin = if (.Platform$OS.type == "windows") "NUL" else "")
if (status != 0L) stop("Historic snow preview render failed; nothing published.")
for (year in c(2005L, 2018L, 2024L)) {
  page <- file.path(snodas_historic_preview_dir, "_site/pages/archive", sprintf("wy%d.html", year))
  html <- paste(readLines(page, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expected <- c("peak_swe.png", "snow_days.png", "peak_swe_departure.png", "peak_swe_percent_median.png")
  for (name in expected) if (!grepl(name, html, fixed = TRUE))
    stop("Rendered snow preview is missing a map link: ", name)
  refs <- unique(regmatches(html, gregexpr("\\.\\./\\.\\./maps/[A-Za-z0-9_./-]+\\.png", html))[[1]])
  if (!length(refs) || !all(file.exists(file.path(dirname(page), refs))))
    stop("Rendered historic preview has missing local map assets: WY", year)
  message("Historic snow page check: PASS; WY", year, "; four snow maps and all local image links.")
}
source("scripts/serve-snodas-historic-anomalies.R")
