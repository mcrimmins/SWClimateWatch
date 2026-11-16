source(file.path(project_root,"R/interactive-map-pilot.R"))
source(file.path(project_root,"R/interactive-map-staging.R"))

testthat::test_that("monthly transfer excludes daily/current data and rejects corrupt seeds before replacement", {
  root <- tempfile("interactive-seed-"); dir.create(root)
  on.exit(unlink(root,recursive=TRUE),add=TRUE)
  from <- file.path(root,"from"); to <- file.path(root,"to"); dir.create(from)
  layers <- lapply(names(interactive_pilot_definitions()),function(id) {
    name <- paste0(id,".bin"); path <- file.path(from,name)
    writeBin(as.raw(1:4),path); writeLines(unname(tools::md5sum(path)),paste0(path,".md5"))
    list(file=name,bytes=4L)
  })
  names(layers) <- names(interactive_pilot_definitions())
  layers$`current-test` <- list(file="must-not-transfer.bin",bytes=9)
  writeLines("{}",file.path(from,"boundaries.json"))
  jsonlite::write_json(list(end_month="2026-10",layers=layers,current=list(test=TRUE),daily=list(test=TRUE)),
    file.path(from,"manifest.json"),auto_unbox=TRUE)
  seed <- copy_interactive_monthly_seed(from,to)$manifest
  testthat::expect_length(seed$layers,12)
  testthat::expect_null(seed$current); testthat::expect_null(seed$daily)
  testthat::expect_false(file.exists(file.path(to,"must-not-transfer.bin")))
  before <- unname(tools::md5sum(file.path(to,"manifest.json")))
  writeBin(as.raw(4:1),file.path(from,layers[[1]]$file))
  testthat::expect_error(copy_interactive_monthly_seed(from,to),"Unverified monthly seed")
  testthat::expect_identical(unname(tools::md5sum(file.path(to,"manifest.json"))),before)
})
