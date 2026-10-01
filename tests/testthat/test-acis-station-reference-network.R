source(file.path(project_root, "R", "acis-station-inventory.R"))
source(file.path(project_root, "R", "acis-station-reference-network.R"))

reference_test_record <- function(uid, id, name, state, longitude = NULL,
                                  latitude = NULL, start = "1980-01-01",
                                  end = "2026-09-28", threadex = FALSE) {
  list(uid = uid, name = name, state = state,
       sids = list(paste(id, if (threadex) "9" else "2")),
       ll = if (is.null(longitude)) NULL else list(longitude, latitude),
       valid_daterange = replicate(3L, list(start, end), simplify = FALSE))
}

reference_test_csv <- function(path, rows) {
  writeLines(c(
    '"Southeast Regional Climate Center",',
    '"Regional Climate Perspectives product generated on 2026-09-29",',
    '"Maximum Temperature on 2026-09-28",',
    '"Station","Name","City","State","Lat","Lon","Year Count",',
    rows
  ), path)
}

testthat::test_that("reference exports preserve IDs and use the project footprint", {
  first <- tempfile(fileext = ".csv")
  second <- tempfile(fileext = ".csv")
  reference_test_csv(first, c(
    '"028820","Tucson Intl Ap","Tucson","AZ","32.13153","-110.95638","97",',
    '"040927","Blythe Asos","Blythe","CA","33.62","-114.72","40",',
    '"010116","Alabaster","Alabaster","AL","33.17","-86.78","20",'
  ))
  reference_test_csv(second, c(
    '"028820","Tucson Intl Ap","Tucson","AZ","32.13153","-110.95638","97",',
    '"040927","Blythe Asos","Blythe","CA","33.62","-114.72","40",'
  ))
  roster <- acis_reference_roster(c(first, second))
  testthat::expect_setequal(roster$reference_id, c("028820", "040927"))
  testthat::expect_equal(roster$exports_present, c(2L, 2L))
  testthat::expect_true(is.character(roster$reference_id))
  testthat::expect_error(acis_reference_roster("not-present.csv"),
                         "does not exist")
})

testthat::test_that("ACIS coordinate matching resolves reused IDs and separates ThreadEx", {
  metadata <- list(
    reference_test_record(1L, "028820", "TUCSON WBO", "AZ", -110.9167, 32.18333),
    reference_test_record(2L, "028820", "TUCSON INTERNATIONAL AIRPORT",
                          "AZ", -110.9564, 32.13153),
    reference_test_record(3L, "PHXthr", "Phoenix Area", "AZ", threadex = TRUE)
  )
  roster <- data.frame(
    reference_id = c("028820", "PHXthr"),
    reference_name = c("Tucson Intl Ap", "Phoenix Area"),
    state = c("AZ", "AZ"),
    reference_longitude = c(-110.95638, -112.0),
    reference_latitude = c(32.13153, 33.4),
    exports_present = 2L
  )
  network <- acis_reference_network(roster, metadata, shortlist_uids = 2L,
                                    pilot_uids = c(2L, 3L),
                                    coverage_dir = tempfile("coverage-"),
                                    today = as.Date("2026-09-29"))
  testthat::expect_equal(network$acis_uid, c(2L, 3L))
  testthat::expect_equal(network$match_method[[1L]], "ID_STATE_AND_COORDINATES")
  testthat::expect_true(network$in_daily_pilot[[1L]])
  testthat::expect_true(network$maxt_metadata_20year_screen[[1L]])
  testthat::expect_true(is.na(network$maxt_20year_annual_screen[[1L]]))
  testthat::expect_true(is.na(network$map_longitude[[2L]]))
  testthat::expect_true(network$threadex[[2L]])
  testthat::expect_equal(network$annual_audit, c("PENDING", "PENDING"))
})

testthat::test_that("missing border-area ThreadEx metadata can be fetched by ID", {
  roster <- data.frame(reference_id = c("ALSthr", "009999"),
                       reference_name = c("Alamosa Area", "Station"),
                       state = c("CO", "AZ"),
                       reference_longitude = c(-105.86, -110),
                       reference_latitude = c(37.44, 34))
  mock_fetch <- function(endpoint, params) {
    testthat::expect_equal(endpoint, "StnMeta")
    testthat::expect_equal(params$sids, "ALSthr 9")
    list(meta = list(reference_test_record(4L, "ALSthr", "Alamosa Area",
                                           "CO", threadex = TRUE)))
  }
  found <- acis_reference_missing_threadex(roster, list(), mock_fetch)
  testthat::expect_equal(length(found), 1L)
  testthat::expect_equal(found[[1L]]$uid, 4L)
})

testthat::test_that("reference annual audits are capped and resume from cache", {
  directory <- tempfile("reference-network-")
  dir.create(directory)
  metadata <- list(
    reference_test_record(1L, "001111", "Station one", "AZ", -111, 34,
                          "2019-01-01", "2020-12-31"),
    reference_test_record(2L, "002222", "Station two", "AZ", -110, 35,
                          "2019-01-01", "2020-12-31")
  )
  saveRDS(metadata, file.path(directory, "metadata.rds"))
  csv <- tempfile(fileext = ".csv")
  reference_test_csv(csv, c(
    '"001111","Station one","","AZ","34","-111","2",',
    '"002222","Station two","","AZ","35","-110","2",'
  ))
  calls <- 0L
  mock_fetch <- function(endpoint, params) {
    calls <<- calls + 1L
    list(data = list(
      list("2019", list("80", 0L), list("60", 0L), list("3", 0L)),
      list("2020", list("80", 0L), list("60", 0L), list("3", 0L))
    ))
  }
  first <- run_acis_reference_network(csv, max_new_stations = 1L,
                                      today = as.Date("2021-01-01"),
                                      directory = directory, fetch = mock_fetch)
  testthat::expect_equal(first$pending, 1L)
  testthat::expect_equal(first$audited_this_run, 1L)
  second <- run_acis_reference_network(csv, max_new_stations = 2L,
                                       today = as.Date("2021-01-01"),
                                       directory = directory, fetch = mock_fetch)
  testthat::expect_equal(second$pending, 0L)
  testthat::expect_equal(calls, 2L)
  testthat::expect_true(all(second$network$maxt_years_90pct == 2L))
  testthat::expect_true(all(!second$network$maxt_20year_annual_screen))
  testthat::expect_true(file.exists(second$path))
})
