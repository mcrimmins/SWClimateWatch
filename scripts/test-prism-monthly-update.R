# Offline tests only. Synthetic temporary grids; no service requests/publication.
testthat::test_dir("tests/testthat", filter = "^prism-monthly-update$", reporter = "summary")
