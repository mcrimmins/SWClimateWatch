source('scripts/load-regional-daily-reference.R')
regional_daily_reference <- build_regional_daily_reference_pilot()
print(regional_daily_reference,row.names=FALSE)
