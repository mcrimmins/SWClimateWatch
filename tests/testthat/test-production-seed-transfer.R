source(file.path(project_root, "scripts", "transfer-production-seed.R"),
       local = TRUE)

testthat::test_that("seed inventory and verification detect incomplete copies", {
  root <- tempfile("swc-seed-")
  dir.create(file.path(root, "site", "stations"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeLines("station page", file.path(root, "site", "stations", "index.html"))
  writeLines("id,value", file.path(root, "site", "stations", "data.csv"))

  local <- swc_seed_inventory_local(root, "site/stations")
  samples <- swc_seed_samples(local)
  testthat::expect_equal(nrow(local), 2L)
  testthat::expect_true("index.html" %in% local$path)

  remote <- list(files = local[, c("path", "size")],
                 hashes = stats::setNames(
                   unname(tools::md5sum(samples$local_path)), samples$path))
  testthat::expect_true(swc_seed_matches(local, samples, remote))
  remote$files$size[[1L]] <- remote$files$size[[1L]] - 1
  testthat::expect_false(swc_seed_matches(local, samples, remote))
  remote$files <- local[, c("path", "size")]
  remote$hashes[[samples$path[[1L]]]] <- "wrong"
  testthat::expect_false(swc_seed_matches(local, samples, remote))
})

testthat::test_that("remote shell encoding does not expose find format tokens", {
  encoded <- swc_seed_remote_shell("find /tmp -printf '%P\\t%s\\n'")
  testthat::expect_false(grepl("%", encoded, fixed = TRUE))
  testthat::expect_match(encoded, "base64 -d")
})
