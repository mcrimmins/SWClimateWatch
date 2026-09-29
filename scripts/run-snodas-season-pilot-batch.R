# One capped batch (up to five daily archives) for WY2024 October-May.
# Rerunning resumes from the local archive and processed-file state.
source("R/config.R")
source("R/snodas.R")
source("R/audit-snodas.R")
source("R/snodas-inventory.R")
source("R/snodas-bootstrap.R")

snodas_season_pilot_status <- run_snodas_cool_season_batch(
  2024L, retain_raw = FALSE
)
print(snodas_season_pilot_status, row.names = FALSE)
