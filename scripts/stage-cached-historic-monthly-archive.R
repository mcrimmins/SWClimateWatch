# The portable release is an explicit local opt-in; unseeded sites stay unchanged.
if (dir.exists("data/processed/historic-monthly-backfill-release") &&
    !dir.exists("data/processed/historic-monthly-release")) stop("Transfer/restore the existing WY1982-2025 publication bundle before enabling the backfill.")
if (dir.exists("data/processed/historic-monthly-release")) {
  source("scripts/load-historic-monthly-publication.R")
  invisible(stage_historic_monthly_release())
  message("Staged 44 Historic Years with 924 verified monthly maps; daily detail and Snow retained.")
}
if (dir.exists("data/processed/historic-monthly-backfill-release")) {
  source("scripts/load-historic-monthly-backfill-publication.R")
  invisible(stage_historic_monthly_backfill_release())
  message("Staged 86 earlier Historic Years with 1806 maps; combined navigation spans WY1896-WY2025.")
}
