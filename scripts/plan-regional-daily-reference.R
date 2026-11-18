source('scripts/load-regional-daily-reference.R')
regional_daily_plan <- plan_regional_daily_reference()
print(table(regional_daily_plan$complete))
if (any(!regional_daily_plan$complete)) print(regional_daily_plan[!regional_daily_plan$complete,c('month','variable','note')],row.names=FALSE)
