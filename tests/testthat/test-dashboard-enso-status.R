enso_fixture <- function(status="El Ni&ntilde;o Advisory",date="8 October 2026") paste0(
  "<html><body>ENSO DIAGNOSTIC DISCUSSION issued by NOAA ",date,
  " ENSO Alert System Status: ",status," Synopsis: Current discussion.</body></html>")

testthat::test_that("RONI strength labels handle both signs and exact category boundaries", {
  values <- c(0,.49,.5,.99,1,1.49,1.5,1.99,2,2.5)
  levels <- c("Neutral-range","Neutral-range","Weak","Weak","Moderate","Moderate","Strong","Strong","Very strong","Very strong")
  for(i in seq_along(values)) for(sign in c(-1,1)) {
    label <- swc_roni_strength_label(sign*values[i])
    testthat::expect_true(startsWith(label,levels[i]))
    if(values[i]>=.5) testthat::expect_true(grepl(if(sign<0) "La" else "El",label,fixed=TRUE))
  }
  testthat::expect_error(swc_roni_strength_label(NA_real_),"finite")
})

testthat::test_that("NOAA status is parsed independently with an explicit issue date", {
  today <- as.Date("2026-10-28")
  x <- swc_parse_enso_status(enso_fixture(),today)
  testthat::expect_equal(x$issued,as.Date("2026-10-08"))
  testthat::expect_equal(x$status,"El Ni\u00f1o Advisory")
  combined <- swc_parse_enso_status(enso_fixture("La Ni&ntilde;a Advisory / El Ni&ntilde;o Watch"),today)
  testthat::expect_match(combined$status,"Advisory / El")
  testthat::expect_equal(swc_parse_enso_status(enso_fixture("Not Active"),today)$status,"Not Active")
  testthat::expect_error(swc_parse_enso_status(enso_fixture("Something new"),today),"category")
  testthat::expect_error(swc_parse_enso_status(enso_fixture(date="8 November 2026"),today),"future")
  testthat::expect_error(swc_parse_enso_status("<html>offline</html>",today),"not recognized")
})

testthat::test_that("advisory cache survives failures and dates old status honestly", {
  path <- tempfile(); on.exit(unlink(path),add=TRUE)
  today <- as.Date("2026-10-28"); calls <- 0L
  fetch <- function() {calls <<- calls+1L; enso_fixture()}
  first <- swc_read_enso_status(path,today,TRUE,fetch)
  testthat::expect_identical(first,swc_read_enso_status(path,today,TRUE,fetch))
  testthat::expect_equal(calls,1L)
  old <- suppressMessages(swc_read_enso_status(path,today+40,TRUE,function() stop("offline")))
  testthat::expect_true(old$cached)
  testthat::expect_true(old$stale)
  testthat::expect_match(swc_dashboard_enso_status_text(old),"Last reported NOAA status")
  testthat::expect_match(swc_dashboard_enso_status_text(old),"over 45 days old")
  regression <- suppressMessages(swc_read_enso_status(path,today+1,TRUE,function() enso_fixture(date="8 September 2026")))
  testthat::expect_equal(regression$issued,first$issued)
  testthat::expect_null(suppressMessages(swc_read_enso_status(tempfile(),today,TRUE,function() stop("offline"))))
  # A warm RONI does not fabricate an advisory when the official source is absent.
  card <- paste(swc_dashboard_roni_text(list(value=1.7,period="JAS",end_month=as.Date("2026-09-01")),status=NULL),collapse=" ")
  testthat::expect_match(card,"Strong El")
  testthat::expect_match(card,"NOAA status:.*unavailable")
  testthat::expect_false(grepl("El Ni\u00f1o Advisory",card,fixed=TRUE))
})
