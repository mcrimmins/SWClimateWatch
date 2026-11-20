# An isolated three-page Quarto site; no changes to site/ or publication bundles.
source("scripts/check-historic-monthly-early-pilot.R")
source("R/map-product-site.R")
source("R/historic-monthly-site-preview.R")
source("scripts/deploy-site-s3.R") # Definitions only.
historic_early_page_root <- build_historic_monthly_site_preview(
  pilot_dir = historic_monthly_early_root(), output_dir = historic_monthly_early_site(),
  expected_years = historic_monthly_early_years(), allow_early = TRUE)
historic_early_quarto <- swc_deploy_quarto()
if (.Platform$OS.type == "windows") historic_early_quarto <- utils::shortPathName(historic_early_quarto)
historic_early_status <- system2(historic_early_quarto,
  c("render", shQuote(historic_early_page_root), "--no-clean"),
  stdin = if (.Platform$OS.type == "windows") "NUL" else "")
if (historic_early_status != 0L) stop("Early pilot page render failed. No published archive files changed.")
print(validate_historic_monthly_site_preview(historic_early_page_root, rendered = TRUE,
  expected_years = historic_monthly_early_years(), allow_early = TRUE), row.names = FALSE)
