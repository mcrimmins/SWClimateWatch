source(file.path(project_root,"R/daily-publish.R"))

monthly_summary_fixture <- function(status="COMPLETE",today=as.Date("2026-11-02")) list(summary=data.frame(
  status=status,target_month=swc_monthly_target(today),requests_attempted=if(status=="COMPLETE") 24L else 0L,
  changed_inputs=0L,products_built=if(status=="COMPLETE") 12L else 0L,products_reused=0L,note=""))

testthat::test_that("monthly adapter is disabled without loading data and validates its switch", {
  withr::local_envvar(c(SWC_MONTHLY_MAPS="false"))
  result <- swc_daily_publish_update_monthly(.load=function() stop("must not load"))
  testthat::expect_equal(result$status,"DISABLED")
  withr::local_envvar(c(SWC_MONTHLY_MAPS="invalid"))
  testthat::expect_error(swc_monthly_maps_enabled(),"true or false")
})

testthat::test_that("completed monthly calculation stages its new verified release", {
  calls <- 0L; staged <- FALSE
  held <- function() list(valid=TRUE,end_month=if(staged) "2026-10" else "2026-09",matches_latest=staged)
  result <- swc_daily_publish_update_monthly(as.Date("2026-11-02"),enabled=TRUE,.load=function(){},
    .seed_exists=function() TRUE,.run=function(today) { calls <<- calls+1L; monthly_summary_fixture(today=today) },
    .stage=function(end) { testthat::expect_equal(end,"2026-10"); staged <<- TRUE },.retained=held,log_path=NULL)
  testthat::expect_equal(calls,1L)
  testthat::expect_true(result$publication_ready)
  testthat::expect_false(result$needs_attention)
  testthat::expect_equal(result$built,12L)
  testthat::expect_match(swc_monthly_summary_line(result),"October 2026.*24 checked.*12 built")
})

testthat::test_that("already complete and out-of-window runs do not restage matching maps", {
  for(status in c("ALREADY_COMPLETE","SKIPPED_OUTSIDE_WINDOW")) {
    result <- swc_daily_publish_update_monthly(as.Date("2026-11-08"),enabled=TRUE,.load=function(){},
      .seed_exists=function() TRUE,.run=function(today) monthly_summary_fixture(status,today),
      .stage=function(...) stop("must not restage"),
      .retained=function() list(valid=TRUE,end_month="2026-10",matches_latest=TRUE),log_path=NULL)
    testthat::expect_equal(result$status,status)
    testthat::expect_false(result$needs_attention)
    testthat::expect_equal(result$requests,0L)
  }
})

testthat::test_that("monthly errors and pending downloads preserve a verified release", {
  for(status in c("FAILED","PENDING_DOWNLOAD","PENDING_PRODUCTS")) {
    result <- swc_daily_publish_update_monthly(as.Date("2026-11-02"),enabled=TRUE,.load=function(){},
      .seed_exists=function() TRUE,.run=function(today) monthly_summary_fixture(status,today),
      .stage=function(...) stop("must not stage"),
      .retained=function() list(valid=TRUE,end_month="2026-09",matches_latest=TRUE),log_path=NULL)
    testthat::expect_equal(result$status,status)
    testthat::expect_true(result$publication_ready)
    testthat::expect_true(result$needs_attention)
    testthat::expect_equal(result$published_month,"2026-09")
  }
})

testthat::test_that("a failed stage resumes from completed products without requesting again", {
  result <- swc_daily_publish_update_monthly(as.Date("2026-11-08"),enabled=TRUE,.load=function(){},
    .seed_exists=function() TRUE,.run=function(today) monthly_summary_fixture("ALREADY_COMPLETE",today),
    .stage=function(...) stop("disk unavailable"),
    .retained=function() list(valid=TRUE,end_month="2026-09",matches_latest=FALSE),log_path=NULL)
  testthat::expect_equal(result$status,"FAILED")
  testthat::expect_true(result$publication_ready)
  testthat::expect_match(result$note,"disk unavailable")
  testthat::expect_equal(result$requests,0L)
})

testthat::test_that("same-month staged maps are reconciled after a revised release", {
  staged <- FALSE
  result <- swc_daily_publish_update_monthly(as.Date("2026-11-08"),enabled=TRUE,.load=function(){},
    .seed_exists=function() TRUE,.run=function(today) monthly_summary_fixture("ALREADY_COMPLETE",today),
    .stage=function(...) staged <<- TRUE,
    .retained=function() list(valid=TRUE,end_month="2026-10",matches_latest=staged),log_path=NULL)
  testthat::expect_true(staged)
  testthat::expect_equal(result$status,"ALREADY_COMPLETE")
})

testthat::test_that("past-window missing cycles alert and missing seeds never bootstrap history", {
  result <- swc_daily_publish_update_monthly(as.Date("2026-11-08"),enabled=TRUE,.load=function(){},
    .seed_exists=function() TRUE,.run=function(today) monthly_summary_fixture("SKIPPED_OUTSIDE_WINDOW",today),
    .retained=function() list(valid=TRUE,end_month="2026-09",matches_latest=TRUE),log_path=NULL)
  testthat::expect_true(result$needs_attention)
  testthat::expect_match(result$note,"overdue.*manual catch-up")
  result <- swc_daily_publish_update_monthly(as.Date("2026-11-02"),enabled=TRUE,.load=function(){},
    .seed_exists=function() FALSE,.run=function(...) stop("no bootstrap"),
    .retained=function() list(valid=TRUE,end_month="2026-09",matches_latest=TRUE),log_path=NULL)
  testthat::expect_equal(result$status,"FAILED")
  testthat::expect_match(result$note,"manifest missing")
  testthat::expect_equal(result$requests,0L)
})

testthat::test_that("daily runner reports monthly failure but publishes the retained release", {
  warning_sent <- FALSE
  monthly <- list(status="FAILED",published_month="2026-09",publication_ready=TRUE,needs_attention=TRUE,
    note="source unavailable",elapsed_seconds=1)
  result <- run_swc_daily_publish(dry_run=FALSE,force_publish=TRUE,marker_path=tempfile(),log_path=NULL,
    prism_update=function() list(summary=data.frame(data_changed=FALSE)),
    explorer_update=function() list(status="STAGED"),weather_update=function(today) list(status="DISABLED"),
    snow_update=function(today) list(maps=list(status="OUT_OF_SEASON")),station_update=function(today) list(status="UPDATED"),
    monthly_update=function(today) monthly,site_fingerprint=function() "fixture",publish=function(dry_run) list(),
    notify=function(event,message) { if(event=="warning") warning_sent <<- TRUE })
  testthat::expect_equal(result$status,"PUBLISHED")
  testthat::expect_true(warning_sent)
  testthat::expect_true(any(grepl("Monthly Climate.*September 2026.*failed",result$summary_lines)))
})

testthat::test_that("daily runner cannot publish without a verified retained monthly release", {
  published <- FALSE
  testthat::expect_error(run_swc_daily_publish(dry_run=TRUE,force_publish=TRUE,marker_path=tempfile(),log_path=NULL,
    prism_update=function() list(summary=data.frame(data_changed=FALSE)),
    explorer_update=function() list(status="STAGED"),weather_update=function(today) list(status="DISABLED"),
    snow_update=function(today) list(maps=list(status="OUT_OF_SEASON")),station_update=function(today) list(status="UPDATED"),
    monthly_update=function(today) list(status="FAILED",published_month=NA_character_,publication_ready=FALSE,
      needs_attention=TRUE,note="missing release",elapsed_seconds=0),
    site_fingerprint=function() "fixture",publish=function(...) published <<- TRUE),"no verified retained")
  testthat::expect_false(published)
})

testthat::test_that("monthly daily log records the map month and counts without changing daily log schema", {
  path <- tempfile(fileext=".csv"); on.exit(unlink(path),add=TRUE)
  for(i in 1:2) swc_daily_publish_update_monthly(as.Date("2026-11-08"),enabled=TRUE,.load=function(){},
    .seed_exists=function() TRUE,.run=function(today) monthly_summary_fixture("ALREADY_COMPLETE",today),
    .retained=function() list(valid=TRUE,end_month="2026-10",matches_latest=TRUE),log_path=path)
  x <- read.csv(path)
  testthat::expect_equal(nrow(x),2L)
  testthat::expect_true(all(x$requests==0 & x$published_month=="2026-10"))
})

testthat::test_that("new monthly pages change the fingerprint before unchanged-daily publication is assessed", {
  marker <- tempfile(); on.exit(unlink(marker),add=TRUE)
  swc_daily_publish_write_marker(marker,"old")
  staged <- published <- FALSE
  result <- run_swc_daily_publish(dry_run=TRUE,marker_path=marker,log_path=NULL,
    prism_update=function() list(summary=data.frame(data_changed=FALSE)),
    explorer_update=function() list(status="STAGED"),weather_update=function(today) list(status="DISABLED"),
    snow_update=function(today) list(maps=list(status="OUT_OF_SEASON")),station_update=function(today) list(status="UPDATED"),
    monthly_update=function(today) {
      staged <<- TRUE
      list(status="COMPLETE",published_month="2026-10",publication_ready=TRUE,needs_attention=FALSE,
        requests=24L,changed_inputs=0L,built=12L,reused=0L,note="",elapsed_seconds=1)
    },site_fingerprint=function() if(staged) "new" else "old",
    publish=function(...) { published <<- TRUE; list() })
  testthat::expect_true(published)
  testthat::expect_equal(result$monthly$status,"COMPLETE")
})
