hazard_explorer_root<-normalizePath(testthat::test_path("..",".."),winslash="/",mustWork=TRUE)
withr::with_dir(hazard_explorer_root,source(file.path(hazard_explorer_root,"R/nws-hazards-explorer.R")))
testthat::test_that("daily hazard summaries count events once with region and exact timing",{
  segment<-function(start,end,states)list(start=start,end=end,states=as.list(states))
  events<-list(list(title="Flood Watch",segments=list(
    segment("2024-02-28T18:00:00Z","2024-03-01T12:00:00Z","AZ"),
    segment("2024-02-28T18:00:00Z","2024-03-01T12:00:00Z","NM"))),
    list(title="Flash Flood Warning",segments=list(segment("2024-02-29T12:00:00Z","2024-02-29T13:00:00Z","NM"))))
  result<-nws_hazards_timeline(events,c("2024-02-28","2024-02-29","2024-03-01"),"2024-02-28","2024-03-02")
  testthat::expect_equal(result$prism[[2]]$regions$AZNM$total,1L)
  testthat::expect_equal(result$prism[[3]]$regions$AZNM$total,2L)
  testthat::expect_equal(result$utc[[2]]$regions$AZNM$total,2L)
  testthat::expect_equal(result$utc[[2]]$regions$AZ$total,1L)
  testthat::expect_equal(result$utc[[2]]$regions$NM$total,2L)
  testthat::expect_equal(result$utc[[2]]$regions$AZNM$types$`Flood Watch`,1L)
  testthat::expect_false(result$prism[[1]]$complete)
  testthat::expect_true(result$prism[[1]]$available)
  absent<-nws_hazards_timeline(list(),"2024-02-27","2024-02-28","2024-03-02")
  testthat::expect_false(absent$utc[[1]]$available)
  testthat::expect_equal(absent$utc[[1]]$regions$AZNM$total,0L)
})
