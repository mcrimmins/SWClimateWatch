source("scripts/load-historic-monthly-backfill-publication.R")
early_pages <- file.path("site/pages/archive", paste0("wy", 1896:1981, ".qmd"))
if (dir.exists(historic_monthly_backfill_release_root()) || any(file.exists(early_pages))) {
  print(validate_historic_monthly_backfill_publication(
    rendered = !"--source-only" %in% commandArgs(TRUE)), row.names = FALSE)
} else message("Earlier Historic Years publication is not enabled on this checkout.")
