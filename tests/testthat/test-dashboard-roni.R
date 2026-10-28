roni_fixture <- function(year, values) paste0("<table><tr><td>", year,
  "</td>", paste0("<td>", values, "</td>", collapse=""), "</tr></table>")

testthat::test_that("latest RONI uses published complete seasons and handles year boundaries", {
  html <- roni_fixture(2026, c(-.9,-.8,-.4,0,.5,1,1.4,1.7,rep("",4)))
  x <- swc_parse_roni(html, as.Date("2026-10-28"))
  testthat::expect_equal(x$period, "JAS")
  testthat::expect_equal(x$end_month, as.Date("2026-09-01"))
  testthat::expect_equal(x$value, 1.7)
  testthat::expect_equal(swc_parse_roni(roni_fixture(2026,rep(.2,8)),
    as.Date("2026-10-28"))$period,"JAS")
  testthat::expect_equal(swc_parse_roni(roni_fixture(2025,1:12/10),
    as.Date("2026-02-10"))$end_month, as.Date("2026-01-01"))
  testthat::expect_equal(swc_parse_roni(html, as.Date("2026-09-20"))$period,"JJA")
  testthat::expect_error(swc_parse_roni("<html>unavailable</html>"),"not recognized")
})

testthat::test_that("RONI fetch is cached daily and failures retain dated information", {
  path <- tempfile(); on.exit(unlink(path),add=TRUE)
  calls <- 0L
  fetch <- function() {calls <<- calls+1L; roni_fixture(2026,c(rep(.1,8),rep("",4)))}
  day <- as.Date("2026-10-28")
  x <- swc_read_dashboard_roni(path,day,TRUE,fetch)
  y <- swc_read_dashboard_roni(path,day,TRUE,fetch)
  testthat::expect_equal(calls,1L)
  testthat::expect_identical(x,y)
  z <- suppressMessages(swc_read_dashboard_roni(path,day+1,TRUE,function() stop("offline")))
  testthat::expect_true(z$cached)
  testthat::expect_equal(z$value,x$value)
  testthat::expect_match(paste(swc_dashboard_roni_text(z),collapse=" "),"Cached source last checked")
  testthat::expect_null(suppressMessages(swc_read_dashboard_roni(tempfile(),day,TRUE,function() stop("offline"))))
})

testthat::test_that("home RONI ranges and station disclosure remain explicit", {
  for (value in c(-.5,0,.5)) {
    text <- paste(swc_dashboard_roni_text(list(value=value,period="DJF",
      end_month=as.Date("2026-02-01"))),collapse=" ")
    testthat::expect_match(text,"Dec 2025.*Feb 2026")
    testthat::expect_match(text,"one period does not establish")
    testthat::expect_match(text,if(value<0) "Weak La" else if(value>0) "Weak El" else "Neutral-range")
  }
  html <- paste(readLines(file.path(project_root,"scripts","station-explorer-assets","index.html")),collapse="\n")
  testthat::expect_match(html,'<details class="methods">\\s*<summary>Reading this preview</summary>')
  testthat::expect_false(grepl('<details[^>]*class="methods"[^>]*open',html))
})
