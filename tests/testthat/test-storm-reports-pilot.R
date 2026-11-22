source(testthat::test_path("..","..","R","storm-reports-pilot.R"))

testthat::test_that("new relative output paths resolve before the containment guard",{
  withr::local_dir(testthat::test_path("..",".."))
  source_dir<-"site/daily-explorer"
  candidate<-tempfile("new-storm-output-",tmpdir="data/diagnostics")
  target<-file.path(candidate,"nested")
  testthat::expect_false(dir.exists(candidate))
  resolved<-storm_reports_output_path(target,source_dir)
  resolver<-storm_reports_output_path
  environment(resolver)<-list2env(list(normalizePath=function(path,...) {
    if(!dir.exists(path))stop("Must resolve an existing ancestor, not a nonexistent path.")
    base::normalizePath(path,...)
  }),parent=environment(storm_reports_output_path))
  testthat::expect_identical(resolver(target,source_dir),resolved)
  testthat::expect_true(startsWith(resolved,paste0(normalizePath("data/diagnostics",winslash="/"),"/")))
  testthat::expect_true(endsWith(resolved,paste0(basename(candidate),"/nested")))
  testthat::expect_false(dir.exists(candidate)) # Guard does not create anything.
  testthat::expect_error(storm_reports_output_path("data/diagnostics-elsewhere/new",source_dir),"under data/diagnostics")
  testthat::expect_error(storm_reports_output_path("data/diagnostics/../outside",source_dir),"dot segments")
  testthat::expect_error(storm_reports_output_path("data/diagnostics",source_dir),"under data/diagnostics")
  testthat::expect_error(storm_reports_output_path("data/diagnostics","data/diagnostics"),"under data/diagnostics")
  testthat::expect_error(storm_reports_output_path(source_dir,source_dir),"under data/diagnostics")
})
storm_fixture<-function(valid="2026-09-01T00:00:00Z",...) {
  list(type="Feature",properties=modifyList(list(valid=valid,state="AZ",typetext="HAIL",magnitude="0",unit="INCH",
    qualifier="M",city="Test",county="Test",source="Public",remark="<script>alert('x')</script>",
    wfo="TWC",product_id="202609010100-KTWC-NWUS55-LSRTWC",lat=32.2,lon=-110.9),list(...)))
}
testthat::test_that("UTC boundaries, exact duplicates and differing text survive correctly",{
  a<-storm_fixture();b<-storm_fixture(remark="Correction")
  raw<-list(type="FeatureCollection",features=list(a,a,b,storm_fixture("2026-09-02T00:00:00Z")))
  x<-normalize_storm_reports(raw,"2026-09-01","2026-09-02")
  testthat::expect_length(x,2)
  testthat::expect_equal(x[[1]]$magnitude,"0")
  testthat::expect_true(all(vapply(x,`[[`,logical(1),"mapped")))
  testthat::expect_true(any(vapply(x,`[[`,character(1),"remark")==a$properties$remark))
})
testthat::test_that("empty results differ from malformed responses and invalid times",{
  testthat::expect_identical(normalize_storm_reports(list(type="FeatureCollection",features=list()),"2026-09-01","2026-09-02"),list())
  testthat::expect_error(normalize_storm_reports(list(error="unavailable"),"2026-09-01","2026-09-02"))
  testthat::expect_error(normalize_storm_reports(list(type="FeatureCollection",features=list(storm_fixture("bad"))),"2026-09-01","2026-09-02"))
})
testthat::test_that("missing positions remain in table; no magnitude or units are invented",{
  raw<-list(type="FeatureCollection",features=list(storm_fixture(lat="bad",magnitude="",unit=""),storm_fixture(state="CO")))
  x<-normalize_storm_reports(raw,"2026-09-01","2026-09-02")
  testthat::expect_length(x,1);testthat::expect_false(x[[1]]$mapped)
  testthat::expect_null(x[[1]]$lat);testthat::expect_identical(x[[1]]$magnitude,"")
})

testthat::test_that("timeline counts match UTC/PRISM days, states, types and source coverage",{
  raw<-list(type="FeatureCollection",features=list(
    storm_fixture("2026-08-31T12:00:00Z",typetext="RAIN"),
    storm_fixture("2026-09-01T11:59:59Z",state="NM",typetext="FLASH FLOOD",lat="bad"),
    storm_fixture("2026-09-01T12:00:00Z",typetext="TSTM WND GST")))
  rows<-normalize_storm_reports(raw,"2026-08-31","2026-09-03")
  x<-storm_reports_timeline(rows,c("2026-09-01","2026-09-02"),c("2026-08-31","2026-09-01"))
  testthat::expect_true(x$prism[[1]]$complete)
  testthat::expect_equal(x$prism[[1]]$regions$AZNM$total,2)
  testthat::expect_equal(x$prism[[1]]$regions$NM$types[["FLASH FLOOD"]],1)
  testthat::expect_equal(x$prism[[1]]$regions$AZ$types$RAIN,1)
  testthat::expect_false(x$prism[[2]]$complete)
  testthat::expect_equal(x$prism[[2]]$regions$AZNM$types[["TSTM WND GST"]],1)
  testthat::expect_equal(x$utc[[1]]$regions$AZNM$total,2)
  testthat::expect_equal(x$utc[[1]]$regions$AZNM$types[["FLASH FLOOD"]],1)
  testthat::expect_equal(x$utc[[2]]$regions$AZNM$total,0)
  testthat::expect_false(x$utc[[2]]$complete)
})
