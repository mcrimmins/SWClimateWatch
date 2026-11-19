# Render all existing years in a separate local review site. No staging/upload.
source("scripts/load-prism-monthly.R")
source("R/historic-monthly-pilot.R")
source("R/historic-monthly-archive.R")
message("Validating the completed archive map batch...")
print(check_historic_monthly_archive_maps(), row.names = FALSE)
source("R/map-product-site.R")
source("R/historic-monthly-site-preview.R")
source("scripts/deploy-site-s3.R") # Definitions only.
historic_archive_page_root <- build_historic_monthly_site_preview(
  pilot_dir = "data/diagnostics/historic-monthly-archive",
  output_dir = "data/diagnostics/historic-monthly-archive-site",
  expected_years = historic_monthly_archive_years())
historic_archive_quarto <- swc_deploy_quarto()
if (.Platform$OS.type == "windows") historic_archive_quarto <- utils::shortPathName(historic_archive_quarto)
message("Rendering ", length(historic_monthly_archive_years()), " isolated Historic Years pages...")
historic_archive_render <- system2(historic_archive_quarto,
  c("render", shQuote(historic_archive_page_root), "--no-clean"), stdin = if (.Platform$OS.type == "windows") "NUL" else "")
if (historic_archive_render != 0L) stop("Archive preview render failed; nothing staged or published.")
print(validate_historic_monthly_site_preview(historic_archive_page_root, rendered = TRUE,
  expected_years = historic_monthly_archive_years()), row.names = FALSE)
