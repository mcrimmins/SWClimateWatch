# Explicit one-time/resumable archive build; never called by the daily publisher.
source("scripts/load-snodas-seasonal-anomaly-publication.R")
invisible(snodas_historic_validate_triage())
snodas_anomaly_archive <- build_snodas_seasonal_anomaly_pilot(
  target_years = snodas_anomaly_publication_years(), publication_ready = TRUE,
  output_dir = snodas_anomaly_archive_dir())
print(snodas_anomaly_archive$summary[, c("water_year", "quality_status", "event", "percent_valid_cells")])
