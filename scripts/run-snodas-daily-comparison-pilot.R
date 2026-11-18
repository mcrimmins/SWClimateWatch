# Uses verified cached regional data and references; no downloads or sync.
source("scripts/load-snodas-daily-comparison-pilot.R")
snodas_daily_comparison_pilot <- build_snodas_daily_comparison_pilot()
print(snodas_daily_comparison_pilot$summary)
