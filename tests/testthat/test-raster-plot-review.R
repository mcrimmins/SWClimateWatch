source(file.path(project_root,"R/raster-plot-review.R"))

testthat::test_that("Git discovery handles R sessions without Git in PATH", {
  folder <- tempfile("git install with spaces ");dir.create(folder)
  on.exit(unlink(folder,recursive=TRUE),add=TRUE)
  executable <- file.path(folder,"git.exe");writeLines("fixture",executable)
  absent <- function(command)""
  testthat::expect_equal(raster_plot_git(configured="",candidates=executable,.which=absent),normalizePath(executable,winslash="/"))
  testthat::expect_equal(raster_plot_git(configured=executable,candidates=character(),.which=absent),normalizePath(executable,winslash="/"))
  testthat::expect_error(raster_plot_git(configured=file.path(folder,"missing.exe")),"does not exist")
  testthat::expect_error(raster_plot_git(configured="",candidates=character(),.which=absent),"swc.raster.plot.git")
})
