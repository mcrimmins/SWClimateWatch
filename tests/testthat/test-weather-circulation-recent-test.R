source(file.path(project_root,"R","weather-circulation-pilot.R"))
source(file.path(project_root,"R","weather-circulation-recent-test.R"))

testthat::test_that("recent probes distinguish absent, failed and incomplete indexes", {
  date <- as.Date("2026-10-25")
  lines <- paste0(1:4,":",c(0,100,200,300),":d=2026102500:",
    c("HGT:500 mb","UGRD:250 mb","VGRD:250 mb","TMP:surface"),
    ":8@3 hour ave(anl),missing=0:")
  body <- charToRaw(paste(lines,collapse="\n"))
  testthat::expect_equal(weather_core_probe_response(200,body,date)$status,"AVAILABLE")
  testthat::expect_equal(weather_core_probe_response(404,raw(),date)$status,"NOT_POSTED")
  testthat::expect_equal(weather_core_probe_response(500,raw(),date)$status,"ERROR")
  testthat::expect_equal(weather_core_probe_response(403,raw(),date)$status,"ERROR")
  testthat::expect_equal(weather_core_probe_response(200,charToRaw("broken"),date)$status,"INVALID_INDEX")
  testthat::expect_equal(weather_core_probe_response(200,body,date+1)$status,"INVALID_INDEX")
  testthat::expect_error(check_weather_core_recent(date,11),"1-10")
  testthat::expect_error(run_weather_circulation_recent_test(sample_days=5),"1-4")
})
