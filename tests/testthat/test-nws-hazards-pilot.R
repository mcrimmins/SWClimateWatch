hazard_root<-normalizePath(testthat::test_path("..",".."),winslash="/",mustWork=TRUE)
source(file.path(hazard_root,"R/nws-hazards-pilot.R"))
hazard_fixture<-function() {
  poly<-sf::st_polygon(list(matrix(c(-112,33,-111,33,-111,34,-112,34,-112,33),ncol=2,byrow=TRUE)))
  sf::st_sf(WFO=c("PSR","PSR","PSR","ABQ","ABQ"),ISSUED=c(rep("202407010000",3),"202406301200","202407010000"),
    EXPIRED=c("202407020000","202407020000","202407020000","202407011200","202407010000"),
    INIT_ISS=rep("202406301000",5),PHENOM=c("SV","SV","SV","ZZ","ZZ"),GTYPE=c("P","P","C","C","C"),
    SIG=c("W","W","W","Y","Y"),ETN=c(1L,1L,1L,2L,3L),STATUS=c("NEW","CON","CAN","CAN","CAN"),
    NWS_UGC=c("","","AZC013","NMC001","NMC001"),
    POLY_BEG=c("202407010000","202407011200",NA,NA,NA),POLY_END=c("202407011200","202407020000",NA,NA,NA),
    PROD_ID=rep("202407010000-KPSR-WWUS55-SVRPSR",5),VTEC_YR=rep(2024L,5),
    geometry=sf::st_sfc(rep(list(poly),5),crs=4326))
}
testthat::test_that("normalization keeps intervals, carry-in, unknown types and unique event counting",{
  withr::local_dir(hazard_root)
  x<-nws_hazards_normalize(hazard_fixture(),"2024-07-01","2024-07-03")
  testthat::expect_length(x$events,2L)
  testthat::expect_length(x$events[[1]]$segments,2L)
  testthat::expect_equal(x$events[[1]]$geometry_type,"Storm polygon")
  testthat::expect_match(x$events[[2]]$title,"Hazard ZZ Advisory")
  testthat::expect_equal(x$events[[2]]$segments[[1]]$end,"2024-07-01T12:00:00Z")
  testthat::expect_null(names(x$events))
  testthat::expect_lt(x$display_vertices,x$original_vertices+1L)
  json<-jsonlite::toJSON(list(events=x$events),auto_unbox=TRUE,digits=6,null="null")
  decoded<-jsonlite::fromJSON(json,simplifyVector=FALSE)
  testthat::expect_null(names(decoded$events))
  testthat::expect_null(names(decoded$events[[1]]$segments))
  testthat::expect_equal(x$geometries[[1]]$type,"Polygon")
  shape<-sf::st_read(jsonlite::toJSON(x$geometries[[1]],auto_unbox=TRUE,digits=6),quiet=TRUE)
  testthat::expect_true(all(sf::st_is_valid(shape)))
})
testthat::test_that("invalid times and changed source schemas stop a build",{
  x<-hazard_fixture();x$EXPIRED[1]<-"broken"
  testthat::expect_error(nws_hazards_normalize(x,"2024-07-01","2024-07-03"),"timestamp")
  x<-hazard_fixture();x$PHENOM<-NULL
  testthat::expect_error(nws_hazards_normalize(x,"2024-07-01","2024-07-03"),"schema")
})
testthat::test_that("followup polygon start substitutes for an absent source issue timestamp",{
  withr::local_dir(hazard_root)
  x<-hazard_fixture();x$ISSUED[2]<-NA_character_
  result<-nws_hazards_normalize(x,"2024-07-01","2024-07-03")
  testthat::expect_equal(result$events[[1]]$segments[[2]]$start,"2024-07-01T12:00:00Z")
  x$POLY_BEG[2]<-NA_character_
  testthat::expect_error(nws_hazards_normalize(x,"2024-07-01","2024-07-03"),"usable effective start")
})
testthat::test_that("optional tags preserve units and suppress empty or not-applicable placeholders",{
  withr::local_dir(hazard_root)
  x<-hazard_fixture();x$WINDTAG<-c(60,70,NA,0,-1);x$HAILTAG<-c(1.25,NA,NA,0,NA)
  x$TORNTAG<-c("RADAR INDICATED",NA,NA,NA,NA);x$DAMAGTAG<-c("CONSIDERABLE",NA,NA,NA,NA)
  x$EMERGENC<-c(TRUE,FALSE,NA,FALSE,FALSE)
  x$HV_SEV<-c("0","2","0","0","0");x$HV_REC<-"OO";x$HV_NWSLI<-"00000";x$HV_CAUSE<-"ER"
  result<-nws_hazards_normalize(x,"2024-07-01","2024-07-03")
  tag<-result$events[[1]]$segments[[1]]$tags
  testthat::expect_equal(tag$wind_mph,60);testthat::expect_equal(tag$hail_inches,1.25)
  testthat::expect_true(tag$emergency_lifecycle);testthat::expect_equal(tag$flood_cause,"ER")
  testthat::expect_null(tag$flood_severity);testthat::expect_null(tag$flood_record);testthat::expect_null(tag$gauge_id)
  testthat::expect_equal(result$events[[1]]$segments[[2]]$tags$flood_severity,"2")
  testthat::expect_null(nws_hazards_tags(x,4)$wind_mph)
  testthat::expect_length(nws_hazards_tags(hazard_fixture(),1),0L)
})
