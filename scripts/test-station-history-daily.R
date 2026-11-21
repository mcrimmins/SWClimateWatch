# Local automated checks only: no live station updates, renders or publication.
testthat::test_dir("tests/testthat",reporter="summary",stop_on_failure=TRUE,
  filter="^(station-history-daily|station-custom-dates-pilot|station-history-integration|acis-station-site|daily-publish|station-update-loader)$")
message("PASS: historical daily reuse/revision guards, atomic staging, loader and daily publisher checks.")
