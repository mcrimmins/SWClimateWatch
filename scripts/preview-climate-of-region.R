# Render the local site for complete sidebar navigation review; no upload.
source("scripts/load-prism-monthly.R")
source("R/regional-seasonal-reference.R")
source("R/regional-climate-site.R")
source("R/regional-precipitation-share.R")
source("scripts/deploy-site-s3.R") # Defines functions only.
preview_climate_of_region <- function(full_site = TRUE) {
  if (!file.exists("site/pages/climate-of-region.qmd")) stop("Run scripts/build-climate-of-region-preview.R first.")
  quarto <- swc_deploy_quarto()
  if (.Platform$OS.type == "windows") quarto <- utils::shortPathName(quarto)
  target <- if (full_site) "site" else "site/pages/climate-of-region.qmd"
  status <- system2(quarto, c("render", target), stdin = if (.Platform$OS.type == "windows") "NUL" else "")
  if (status != 0L) stop("Climate of the Region render failed; nothing published.")
  print(validate_regional_climate_reference_site(rendered = TRUE))
  source("scripts/serve-climate-of-region-preview.R")
}
preview_climate_of_region(full_site = getOption("swc.climate_region.full_site", TRUE))
