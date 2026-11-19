# The portable release is an explicit local opt-in; unseeded sites stay unchanged.
if (dir.exists("data/processed/historic-monthly-release")) {
  source("scripts/load-historic-monthly-publication.R")
  invisible(stage_historic_monthly_release())
  message("Staged 44 Historic Years with 924 verified monthly maps; daily detail and Snow retained.")
}
