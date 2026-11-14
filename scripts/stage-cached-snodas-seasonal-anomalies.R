# Reconcile verified historical pages/assets only; no calculations or downloads.
source("scripts/load-snodas-seasonal-anomaly-publication.R")
invisible(stage_snodas_seasonal_anomaly_archive(dry_run = FALSE))
print(validate_snodas_seasonal_anomaly_publication(require_rendered = FALSE))
