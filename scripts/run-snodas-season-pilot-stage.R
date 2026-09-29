# Continue WY2024 October-May by at most four five-request batches.
# Each daily request is paced; a stage never exceeds 20 new archives.
# Rerun manually only after reviewing its cumulative status and disk space.
source("R/config.R")
source("R/snodas.R")
source("R/audit-snodas.R")
source("R/snodas-inventory.R")
source("R/snodas-bootstrap.R")

snodas_season_pilot_status <- run_snodas_cool_season_stage(
  2024L, retain_raw = FALSE
)
print(snodas_season_pilot_status, row.names = FALSE)
