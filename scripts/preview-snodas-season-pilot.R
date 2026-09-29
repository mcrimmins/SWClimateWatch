# Local-only preview for the WY2024 October-May pilot; no network requests.
source("R/config.R")
source("R/snodas.R")
source("R/audit-snodas.R")
source("R/snodas-inventory.R")
source("R/snodas-bootstrap.R")

snodas_season_pilot_plan <- plan_snodas_cool_season(2024L)
snodas_season_pilot_processed <- snodas_cool_season_processed(
  snodas_season_pilot_plan
)$complete
snodas_season_pilot_preview <- preview_snodas_download(
  snodas_season_pilot_plan[!snodas_season_pilot_processed, , drop = FALSE]
)
snodas_season_pilot_status <- snodas_cool_season_status(
  snodas_season_pilot_plan
)
print(snodas_season_pilot_status, row.names = FALSE)
