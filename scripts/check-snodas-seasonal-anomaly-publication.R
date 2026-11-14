source("scripts/load-snodas-seasonal-anomaly-publication.R")
print(validate_snodas_seasonal_anomaly_publication(
  require_rendered = !"--source-only" %in% commandArgs(trailingOnly = TRUE)))
