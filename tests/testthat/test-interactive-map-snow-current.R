source(file.path(project_root, "R/snodas-current-site.R"))
source(file.path(project_root, "R/interactive-map-snow-current.R"))

testthat::test_that("staging Snow accepts only the verified Current Snow date, source and images", {
  root <- tempfile("snow-release-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  maps <- file.path(root, "maps/generated/snodas/current")
  dir.create(maps, recursive = TRUE); dir.create(file.path(root, "pages"))
  names <- c("swe-observed.png", "swe-departure.png", "swe-percent-median.png")
  for (name in names) writeLines(name, file.path(maps, name))
  page <- file.path(root, "pages/current-snow.qmd"); writeLines("verified page fixture", page)
  row <- data.frame(water_year = 2027L, date = "2026-11-15", source_signature = "verified-source",
    observed_md5 = unname(tools::md5sum(file.path(maps, names[1]))),
    departure_md5 = unname(tools::md5sum(file.path(maps, names[2]))),
    percent_md5 = unname(tools::md5sum(file.path(maps, names[3]))),
    change_available = FALSE, change_md5 = "", page_md5 = unname(tools::md5sum(page)))
  publication <- file.path(root, "publication.csv"); write.csv(row, publication, row.names = FALSE)
  signature <- function(date) "verified-source"
  checked <- interactive_snow_current_release(root, publication, signature)
  testthat::expect_identical(checked$date, row$date)
  testthat::expect_length(checked$images, 3L)
  testthat::expect_false(checked$change_available)
  testthat::expect_error(interactive_snow_current_release(root, publication, function(date) "revised-source"), "differ")
  writeLines("changed page", page)
  testthat::expect_error(interactive_snow_current_release(root, publication, signature), "differ")
  writeLines("verified page fixture", page)
  row$change_available <- TRUE; row$change_md5 <- "missing"
  write.csv(row, publication, row.names = FALSE)
  testthat::expect_error(interactive_snow_current_release(root, publication, signature), "differ")
  writeLines("verified change fixture", file.path(maps, "swe-change-7day.png"))
  row$change_md5 <- unname(tools::md5sum(file.path(maps, "swe-change-7day.png")))
  write.csv(row, publication, row.names = FALSE)
  testthat::expect_length(interactive_snow_current_release(root, publication, signature)$images, 4L)
})
