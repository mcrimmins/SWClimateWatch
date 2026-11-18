# Local pilot using the existing completed seasonal grids, not daily downloads.
source("scripts/load-snodas-seasonal-anomaly.R")
snodas_seasonal_anomaly_pilot <- build_snodas_seasonal_anomaly_pilot()
print(snodas_seasonal_anomaly_pilot$summary)
