source("R/storm-reports-staging.R")
for(directory in c("site/daily-explorer","site/_site/daily-explorer"))
  validate_storm_reports_publication(directory)
