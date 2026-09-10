testthat::test_that("bootstrap summary reports bounded progress", {
  raw_dir <- tempfile("raw-")
  plan <- plan_prism_download(
    "bootstrap",
    variables = "maxt",
    start = as.Date("2020-01-01"),
    end = as.Date("2020-04-30"),
    raw_dir = raw_dir
  )
  dir.create(dirname(plan$path[1L]), recursive = TRUE)
  file.create(plan$path[1L])

  status <- summarize_prism_bootstrap(plan, max_requests = 2L)

  testthat::expect_equal(status$total_requests, 4L)
  testthat::expect_equal(status$downloaded_files, 1L)
  testthat::expect_equal(status$remaining_requests, 3L)
  testthat::expect_equal(status$scheduled_this_run, 2L)
  testthat::expect_equal(status$deferred, 1L)
})

testthat::test_that("bounded workflow defaults remain conservative", {
  arguments <- formals(run_prism_bootstrap_batch)
  testthat::expect_equal(eval(arguments$max_requests), 25L)
  testthat::expect_equal(eval(arguments$delay_seconds), swc_prism$request_delay_seconds)
  testthat::expect_equal(eval(arguments$jitter_seconds), swc_prism$request_jitter_seconds)
})
