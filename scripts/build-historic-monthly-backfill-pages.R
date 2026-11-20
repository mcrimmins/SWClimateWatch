# Prepare/render 86 isolated earlier pages, leaving the existing archive intact.
source("scripts/check-historic-monthly-backfill-maps.R")
source("R/map-product-site.R")
source("R/historic-monthly-site-preview.R")
source("scripts/deploy-site-s3.R") # Definitions only; no upload.
historic_backfill_page_root <- build_historic_monthly_site_preview(
  pilot_dir = historic_monthly_backfill_root(), output_dir = historic_monthly_backfill_site(),
  expected_years = historic_monthly_backfill_years(), allow_early = TRUE)
historic_backfill_quarto <- swc_deploy_quarto()
if (.Platform$OS.type == "windows") historic_backfill_quarto <- utils::shortPathName(historic_backfill_quarto)
message("Rendering 86 local Historic Years pages; years are grouped by decade in the sidebar...")
historic_backfill_render <- system2(historic_backfill_quarto,
  c("render", shQuote(historic_backfill_page_root), "--no-clean"),
  stdin = if (.Platform$OS.type == "windows") "NUL" else "")
if (historic_backfill_render != 0L) stop("Backfill preview render failed; no archive pages were published.")
print(validate_historic_monthly_site_preview(historic_backfill_page_root, TRUE,
  expected_years = historic_monthly_backfill_years(), allow_early = TRUE), row.names = FALSE)
