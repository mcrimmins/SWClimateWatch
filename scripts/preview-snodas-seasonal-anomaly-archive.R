# Stage the reviewed maps into the standard local site and render it; no upload.
source("scripts/stage-cached-snodas-seasonal-anomalies.R")
source("scripts/stage-cached-prism-monthly-site.R") # Reconcile the existing release; no requests.
source("scripts/deploy-site-s3.R")
snow_quarto <- swc_deploy_quarto()
if (.Platform$OS.type == "windows") snow_quarto <- utils::shortPathName(snow_quarto)
status <- system2(snow_quarto, c("render", "site"),
  stdin = if (.Platform$OS.type == "windows") "NUL" else "")
if (status != 0L) stop("Local site render failed; nothing published.")
print(validate_snodas_seasonal_anomaly_publication(require_rendered = TRUE))
for (file in c("config.R", "acis-prism.R", "process-prism.R", "map-product-site.R", "map-hotlinks.R"))
  source(file.path("R", file))
snow_hotlinks <- stage_map_hotlinks("site/_site", "s3://cales-climate-reports/climate/watch/")
validate_map_hotlinks("site/_site")
snow_anomaly_links <- snow_hotlinks[grepl(
  "^maps/generated/snodas/seasonal-archive/wy[0-9]{4}/peak_swe_(departure|percent_median)[.]png$", snow_hotlinks$path), ]
if (nrow(snow_anomaly_links) != 42L) stop("Expected 42 seasonal snow anomaly catalog links.")
message("Historical snow catalog: PASS; 42 stable dated anomaly links.")
source("scripts/serve-snodas-seasonal-anomaly-archive.R")
message("Local Historic Years ready. No downloads or S3 sync.")
