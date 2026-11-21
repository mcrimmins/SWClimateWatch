source(file.path(project_root,"R/station-history-csv-check.R"))
testthat::test_that("saved CSV validation preserves zero, trace, gaps and flags and rejects altered rows", {
  root <- tempfile();dir.create(root);on.exit(unlink(root,recursive=TRUE),add=TRUE)
  jsonlite::write_json(list(stations=list(list(uid=1,sid="ID1",name="Example",index="index.json"))),file.path(root,"catalog.json"),auto_unbox=TRUE)
  jsonlite::write_json(list(years=data.frame(start="2000-01-01",end="2000-01-02",file="year.json")),file.path(root,"index.json"),auto_unbox=TRUE,dataframe="rows")
  jsonlite::write_json(list(start="2000-01-01",end="2000-01-02",pcpn=list(0,NULL),maxt=list(70,NULL),mint=list(40,NULL),
    pcpn_status=c(2,3),maxt_status=c(1,0),mint_status=c(1,0)),file.path(root,"year.json"),auto_unbox=TRUE,null="null")
  path <- file.path(root,"station-1-2000-01-01-to-2000-01-02.csv")
  x <- data.frame(station_uid=1,station_id="ID1",station_name="Example",date=c("2000-01-01","2000-01-02"),
    precipitation_inches=c(0,NA),high_f=c(70,NA),low_f=c(40,NA),precipitation_status=c("TRACE","FLAGGED"),high_status=c("AVAILABLE","MISSING"),low_status=c("AVAILABLE","MISSING"))
  write.csv(x,path,row.names=FALSE,na="")
  result <- check_station_history_csv(path,root)
  testthat::expect_equal(result$trace,1);testthat::expect_equal(result$flagged_values,1);testthat::expect_equal(result$missing_values,3)
  x$precipitation_inches[2] <- 0;write.csv(x,path,row.names=FALSE,na="")
  testthat::expect_error(check_station_history_csv(path,root))
})
