# Prepare the reviewed layout and monthly release, then render locally only.
source("scripts/stage-current-map-groups.R")
source("scripts/stage-prism-monthly-site.R")
source("scripts/deploy-site-s3.R") # Defines helpers; no deployment is invoked.
swc_climate_quarto <- swc_deploy_quarto()
if (.Platform$OS.type == "windows") swc_climate_quarto <- utils::shortPathName(swc_climate_quarto)
swc_climate_render_status <- system2(swc_climate_quarto,c("render","site"))
if (swc_climate_render_status != 0L) stop("Local site render failed; nothing published.")
source("scripts/check-current-map-groups.R")
source("scripts/check-prism-monthly-publication.R")
if (interactive()) utils::browseURL(normalizePath("site/_site/index.html"))
message("Local site ready: site/_site/index.html. No S3 sync performed.")
