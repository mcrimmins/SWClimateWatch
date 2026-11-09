source(file.path(project_root,"R/conditions-synopsis-evidence.R"))
source(file.path(project_root,"R/conditions-synopsis-template.R"))

snow_test_config <- function() {
  x<-synopsis_config(file.path(project_root,"config/conditions-synopsis.yml"))
  x$snow$minimum_area_km2<-1
  x
}

testthat::test_that("snow deficits include zero current SWE but exclude low-median desert area", {
  config<-snow_test_config()
  x<-synopsis_snow_stats(c(0,4,100),c(2,2,0),c(21,21,21),NULL,c(1,3,100),config)
  testthat::expect_equal(x$storage$values[["area_below_median_percent"]],25)
  testthat::expect_equal(x$storage$values[["area_above_median_percent"]],75)
  testthat::expect_equal(x$storage$area_km2,4)
  testthat::expect_equal(x$change$status,"NO_EXACT_PRIOR")
  x<-synopsis_snow_stats(c(0,4,1),c(2,2,.2),c(17,18,21),NULL,c(1,3,100),config)
  testthat::expect_equal(x$storage$area_km2,3)
})

testthat::test_that("snow summaries withhold insufficient support and missing endpoints", {
  config<-snow_test_config()
  x<-synopsis_snow_stats(c(NA,2),c(2,2),c(21,21),c(2,NA),c(1,1),config)
  testthat::expect_equal(x$storage$status,"LOW_COVERAGE")
  testthat::expect_equal(x$change$status,"LOW_COVERAGE")
  testthat::expect_null(x$change$values)
  config$snow$minimum_area_km2<-500
  x<-synopsis_snow_stats(c(0,2),c(2,2),c(21,21),c(2,0),c(1,1),config)
  testthat::expect_equal(x$storage$status,"SMALL_REFERENCE_AREA")
  testthat::expect_error(synopsis_snow_stats(c(-1,2),c(2,2),c(21,21),NULL,c(1,1),config),"Negative")
})

testthat::test_that("early snow change works even when median is too low for a ratio", {
  config<-snow_test_config()
  x<-synopsis_snow_stats(c(1,0,0),c(0,0,0),c(21,21,21),c(0,1,0),c(1,1,50),config)
  testthat::expect_equal(x$storage$status,"SMALL_REFERENCE_AREA")
  testthat::expect_equal(x$change$area_km2,2)
  testthat::expect_equal(x$change$values[["area_gain_percent"]],50)
  testthat::expect_equal(x$change$values[["area_loss_percent"]],50)
})

testthat::test_that("proof audit rejects unresolved claims and provides direct dated evidence", {
  root<-tempfile();dir.create(root);on.exit(unlink(root,recursive=TRUE),add=TRUE)
  evidence<-list(snapshot_date="2026-11-03",facts=data.frame(fact_id="good",region="AZ",metric="mean_departure",value=2,units="degreeF",period_start="2026-10-05",period_end="2026-11-03",reference="1991–2020"))
  blocks<-list(list(section="Past 30 days",text="Arizona was 2 degrees above normal.",fact_ids="good",links="pages/temperature-departures.html"),
    list(section="Past 30 days",text="Unsupported statement.",fact_ids="absent",links="pages/daily-explorer.html"))
  result<-synopsis_attach_support(blocks,evidence,project_root,root)
  testthat::expect_length(result,1L)
  testthat::expect_true(file.exists(file.path(root,result[[1]]$support_link)))
  doc<-xml2::read_html(file.path(root,result[[1]]$support_link))
  testthat::expect_match(xml2::xml_text(doc),"2026-10-05",fixed=TRUE)
  testthat::expect_equal(read.csv(file.path(root,"highlight-link-audit.csv"))$status,c("SUPPORTED","MISSING_FACT"))
  testthat::expect_equal(synopsis_support_href(result[[1]]$support_link),result[[1]]$support_link)
})

testthat::test_that("weekly temperature claims require their actual seven-day map", {
  root<-tempfile();dir.create(root);on.exit(unlink(root,recursive=TRUE),add=TRUE)
  evidence<-list(snapshot_date="2026-11-03",facts=data.frame(fact_id="tmean_departure_07day:AZNM:mean_departure"))
  result<-synopsis_attach_support(list(list(section="Past 7 days",text="A weekly departure.",
    fact_ids=evidence$facts$fact_id,links="pages/daily-explorer.html")),evidence,project_root,root)
  testthat::expect_length(result,0L)
  testthat::expect_equal(read.csv(file.path(root,"highlight-link-audit.csv"))$status,"MATCHING_MAP_UNAVAILABLE")
})


testthat::test_that("snow stories respond to season, snow support, gains and losses", {
  source(file.path(project_root,"R/conditions-synopsis-seasonal-review.R"))
  root<-tempfile();dir.create(root);on.exit(unlink(root,recursive=TRUE),add=TRUE)
  review<-review_conditions_synopsis_snow(project_root,root)
  testthat::expect_equal(nrow(review$summary),7L)
  testthat::expect_true(all(review$summary$status=="PASS"))
  testthat::expect_true(all(review$summary$selected_snow[review$summary$case %in% c("winter-missing","small-reference","summer-inactive")]==0))
})
