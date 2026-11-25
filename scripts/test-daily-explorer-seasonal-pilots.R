testthat::test_file("tests/testthat/test-daily-explorer-july-pilot.R",stop_on_failure=TRUE)
testthat::test_file("tests/testthat/test-daily-explorer-seasonal-pilots.R",stop_on_failure=TRUE)
source("scripts/check-daily-explorer-seasonal-pilots.R")
