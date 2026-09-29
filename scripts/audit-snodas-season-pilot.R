# Offline WY2024 grid-quality audit; resumes from date-level CSV checkpoints.
# Run from the project root: source("scripts/audit-snodas-season-pilot.R")
source("R/config.R")
source("R/snodas.R")
source("R/audit-snodas.R")
source("R/snodas-inventory.R")
source("R/snodas-bootstrap.R")
source("R/snodas-quality-pilot.R")
source("R/snodas-season-audit.R")

snodas_season_audit <- audit_snodas_cool_season(2024L)
print(snodas_season_audit$summary, row.names = FALSE)
if (nrow(snodas_season_audit$flags)) {
  print(snodas_season_audit$flags[, c(
    "date", "variable", "negative_cells", "saturated_cells",
    "swe_exceeds_depth_cells", "repair_zero_cells"
  )], row.names = FALSE)
}
