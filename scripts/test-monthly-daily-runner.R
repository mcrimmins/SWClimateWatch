# Offline scheduler/publication adapter tests: no downloads, rendering or S3.
testthat::test_dir("tests/testthat", filter="^(monthly-publish|daily-publish|prism-monthly-update|production-preflight)$",reporter="summary")
