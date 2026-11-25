source("R/daily-explorer-seasonal-pilots.R")
seasonal_explorer_load()
seasonal_check<-check_seasonal_explorer()
for(w in seasonal_explorer_windows()) {
  message(w$title)
  print(read.csv(file.path(w$root,"storage.csv")),row.names=FALSE)
  print(read.csv(file.path(w$root,"run-history.csv")),row.names=FALSE)
}
