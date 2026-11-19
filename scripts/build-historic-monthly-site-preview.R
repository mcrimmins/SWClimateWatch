# Render only an isolated three-page review site. No operational page writes.
message("Checking the 63 cached pilot maps before preparing Historic Years pages...")
source("scripts/check-historic-monthly-pilot.R")
source("R/map-product-site.R")
source("R/historic-monthly-site-preview.R")
source("scripts/deploy-site-s3.R") # Definitions only; no deployment calls.
historic_monthly_site_preview <- build_historic_monthly_site_preview()
historic_review_quarto <- swc_deploy_quarto()
if (.Platform$OS.type == "windows") historic_review_quarto <- utils::shortPathName(historic_review_quarto)
message("Rendering three isolated Historic Years pages...")
historic_review_status <- system2(historic_review_quarto,
  c("render", shQuote(historic_monthly_site_preview), "--no-clean"),
  stdin = if (.Platform$OS.type == "windows") "NUL" else "")
if (historic_review_status != 0L) stop("Local Historic Years render failed. No archive pages were replaced.")
print(validate_historic_monthly_site_preview(historic_monthly_site_preview, rendered = TRUE), row.names = FALSE)
message("Local page review: ", file.path(historic_monthly_site_preview, "_site/index.html"))
