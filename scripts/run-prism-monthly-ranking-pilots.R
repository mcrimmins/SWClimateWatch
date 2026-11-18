# Local review maps only: verified monthly inputs, no downloads or publishing.
source("scripts/load-prism-monthly.R")
source("R/map-reference-layers.R")
source("R/map-product-scales.R")
source("R/map-southwest.R")
monthly_ranking_pilots <- build_prism_monthly_ranking_pilots(
  temperature_durations = getOption("swc.monthly.temperature.durations", c(1L, 3L, 6L, 12L)),
  precipitation_durations = getOption("swc.monthly.precipitation.durations", c(1L, 3L, 6L, 12L)),
  force = isTRUE(getOption("swc.monthly.force.pilots", FALSE)))
print(monthly_ranking_pilots$summary, row.names = FALSE)
print(monthly_ranking_pilots$results, row.names = FALSE)
if (monthly_ranking_pilots$summary$status != "READY") {
  stop("Some monthly ranking pilots failed; inspect last-batch.csv and rerun to resume.", call. = FALSE)
}
message("Local monthly ranking gallery: ", monthly_ranking_pilots$gallery)
