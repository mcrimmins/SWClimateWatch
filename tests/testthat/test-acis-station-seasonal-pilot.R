source(file.path(project_root, "R", "acis-station-cumulative-pilot.R"))
source(file.path(project_root, "R", "acis-station-seasonal-pilot.R"))

seasonal_fixture <- function() {
  dates <- seq(as.Date("1989-10-01"), as.Date("2027-09-30"), by="day")
  list(uid=1L, as_of=as.Date("2026-11-03"), daily=data.frame(date=dates,
    variable="pcpn",numeric_value=.1,observed=TRUE,flag="",trace=FALSE,accumulated=FALSE))
}
seasonal_station <- data.frame(uid=1L,sid="test",name="Test",state="AZ",role="fixed")

testthat::test_that("seasons reset independently and use the latest started season", {
  cache <- seasonal_fixture()
  cache$daily$observed[cache$daily$date==as.Date("2025-12-01")] <- FALSE
  monsoon <- acis_station_seasonal_payload(seasonal_station,cache,"monsoon","2026-11-03")$payload
  testthat::expect_equal(monsoon$current$total,10.8)
  testthat::expect_equal(nrow(monsoon$points),108L)
  testthat::expect_equal(monsoon$water_year,2026L)
  testthat::expect_true(monsoon$season_complete)
  cool <- acis_station_seasonal_payload(seasonal_station,cache,"cool","2026-11-03")$payload
  testthat::expect_equal(cool$current$total,3.4)
  testthat::expect_equal(nrow(cool$points),182L)
  testthat::expect_equal(cool$water_year,2027L)
  testthat::expect_false(cool$season_complete)
  spring <- acis_station_seasonal_payload(seasonal_station,cache,"cool","2026-06-01")$payload
  testthat::expect_equal(spring$as_of,"2026-03-31")
  testthat::expect_equal(spring$water_year,2026L)
  before <- acis_station_seasonal_payload(seasonal_station,cache,"monsoon","2026-06-14")$payload
  testthat::expect_equal(before$water_year,2025L)
})

testthat::test_that("matching ranks use prefixes and exclude future information", {
  cache <- seasonal_fixture()
  # An earlier season with a later gap is valid for November comparisons.
  cache$daily$observed[cache$daily$date==as.Date("1995-05-01")] <- FALSE
  result <- acis_station_seasonal_payload(seasonal_station,cache,"water","2026-11-03")
  p <- result$payload
  testthat::expect_equal(p$comparison$historical_years,length(result$history$curves)+1L)
  testthat::expect_equal(p$comparison$wet_rank,1L)
  testthat::expect_equal(p$comparison$percentile,50)
  testthat::expect_equal(p$comparison$departure_inches,0,tolerance=1e-8)
  testthat::expect_true(all(is.na(p$points$current[p$points$date>p$as_of])))
  cache$daily$observed[cache$daily$date==as.Date("2026-10-10")] <- FALSE
  p <- acis_station_seasonal_payload(seasonal_station,cache,"water","2026-11-03")$payload
  testthat::expect_true(is.na(p$current$total))
  testthat::expect_false(p$comparison$available)
  testthat::expect_true(is.na(p$comparison$departure_inches))
  testthat::expect_false(p$closest_match$available)
  testthat::expect_equal(p$current$observed_subtotal,3.3)
})

testthat::test_that("leap days, ties, zero normals and support limits are explicit", {
  cache <- seasonal_fixture()
  p <- acis_station_seasonal_payload(seasonal_station,cache,"cool","2024-02-29")$payload
  testthat::expect_equal(p$as_of,"2024-02-28")
  testthat::expect_match(p$comparison$note,"February 29")
  march <- acis_precipitation_season(cache$daily,"cool",2024L,as.Date("2024-03-01"))
  testthat::expect_equal(march$cumulative_inches[march$date==as.Date("2024-03-01")],15.3)
  cache$daily$numeric_value[] <- 0
  p <- acis_station_seasonal_payload(seasonal_station,cache,"water","2026-11-03")$payload
  testthat::expect_true(is.na(p$comparison$percent_average))
  testthat::expect_equal(p$comparison$percentile,50)
  testthat::expect_equal(p$historical_context$current_status,"TIED_BOTH")
  p <- acis_station_seasonal_payload(seasonal_station,cache,"water","2026-11-03",minimum_history=100L)$payload
  testthat::expect_false(p$comparison$available)
  testthat::expect_true(is.na(p$comparison$wet_rank))
})
