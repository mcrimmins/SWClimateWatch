source(file.path(project_root, "R", "weather-circulation-pilot.R"))

testthat::test_that("streamlines follow wind direction and stop at domain edges or calm flow", {
  grid <- expand.grid(x=seq(120,160,2),y=seq(10,40,2))
  grid$u250 <- 20; grid$v250 <- 0
  lines <- weather_streamlines(grid)
  testthat::expect_gt(nrow(lines),0)
  testthat::expect_true(all(is.finite(as.matrix(lines))))
  testthat::expect_true(all(lines$x >= 120 & lines$x < 160 & lines$y >= 10 & lines$y < 40))
  testthat::expect_true(all(vapply(split(lines,lines$group),function(p)
    all(diff(p$x)>0) && max(p$y)-min(p$y)<1e-10,logical(1))))
  grid$u250 <- 0; grid$v250 <- 20
  north <- weather_streamlines(grid)
  testthat::expect_gt(nrow(north),0)
  testthat::expect_true(all(vapply(split(north,north$group),function(p)
    all(diff(p$y)>0) && max(p$x)-min(p$x)<1e-10,logical(1))))
  grid$v250 <- 0
  testthat::expect_equal(nrow(weather_streamlines(grid)),0)
})

testthat::test_that("contour labels preserve levels on the native latitude grid", {
  grid <- expand.grid(x=seq(120,300,2),y=c(10,17,25,34,44,55,70))
  grid$height_dm <- 500.13+grid$y
  labels <- weather_contour_labels(grid)
  testthat::expect_gt(nrow(labels),0)
  testthat::expect_true(all(labels$label %in% seq(420,630,6)))
  testthat::expect_equal(labels$label,500.13+labels$y,tolerance=1e-8)
  testthat::expect_true(all(labels$x>124 & labels$x<296 & labels$y>12 & labels$y<68))
})

testthat::test_that("CORe plan selects only three bounded complete daily records", {
  date <- as.Date("2023-03-01")
  lines <- paste0(1:4, ":", c(0,100,200,300), ":d=2023030100:",
    c("HGT:500 mb", "UGRD:250 mb", "VGRD:250 mb", "TMP:surface"),
    ":8@3 hour ave(anl),missing=0:")
  plan <- weather_core_plan(lines, date)
  testthat::expect_identical(plan$field, c("height500","u250","v250"))
  testthat::expect_equal(plan$bytes, rep(100,3))
  testthat::expect_error(weather_core_plan(lines, date+1), "date or complete")
  testthat::expect_error(weather_core_plan(sub("missing=0","missing=1",lines), date), "averaging")
  testthat::expect_error(weather_core_plan(lines[1:3], date), "Unbounded")
  testthat::expect_error(weather_core_plan(lines, date, max_field_bytes=50), "oversized")
  testthat::expect_error(weather_core_plan(c(lines, lines[1]), date), "strictly increasing")
  testthat::expect_error(weather_core_plan(lines[-2], date), "exactly one")
  testthat::expect_error(weather_core_plan("broken",date), "Malformed")
  testthat::expect_error(weather_core_url(as.Date(NA)), "Choose one")
})

testthat::test_that("partial downloads cannot silently become full files or corrupt GRIBs", {
  body <- c(charToRaw("GRIB"), as.raw(c(0,0,0,2)), as.raw(c(rep(0,7),20)), charToRaw("7777"))
  testthat::expect_invisible(weather_core_check_response(body, 206L, "bytes 100-119/1000", 100, 119))
  testthat::expect_error(weather_core_check_response(body, 200L, NULL, 100, 119), "exact requested")
  testthat::expect_error(weather_core_check_response(body, 206L, "bytes 101-120/1000", 100, 119), "exact requested")
  testthat::expect_error(weather_core_check_response(body[-1], 206L, "bytes 100-119/1000", 100, 119), "exact requested")
  body[16] <- as.raw(19)
  testthat::expect_error(weather_core_check_response(body, 206L, "bytes 100-119/1000", 100, 119), "message length")
  body[1] <- as.raw(0)
  testthat::expect_error(weather_core_check_response(body, 206L, "bytes 100-119/1000", 100, 119), "Invalid GRIB")
})

testthat::test_that("Gaussian coordinates retain nonuniform latitude spacing", {
  latitude <- weather_gaussian_latitudes(256)
  testthat::expect_length(latitude,256)
  testthat::expect_equal(latitude, -rev(latitude), tolerance=1e-10)
  testthat::expect_equal(latitude[1], 89.462822, tolerance=1e-6)
  testthat::expect_true(all(diff(latitude) < 0))
  testthat::expect_true(max(abs(diff(diff(latitude)))) > 1e-4)
  testthat::expect_equal(weather_gaussian_latitudes(2), c(1,-1)*asin(1/sqrt(3))*180/pi)
  testthat::expect_error(weather_gaussian_latitudes(3), "even Gaussian")
})

testthat::test_that("verified pilot cache is reused without an index request", {
  root <- tempfile(); dir.create(root)
  on.exit(unlink(root, recursive=TRUE), add=TRUE)
  paths <- file.path(root,c("source.idx","height500.grb","u250.grb","v250.grb"))
  for (path in paths) writeBin(as.raw(1:5),path)
  saveRDS(list(url=weather_core_url(as.Date("2023-03-01")),plan=data.frame(),
    paths=setNames(paths[-1],c("height500","u250","v250")),
    files=data.frame(path=paths,md5=unname(tools::md5sum(paths)))),file.path(root,"complete.rds"))
  result <- weather_core_download(as.Date("2023-03-01"),root)
  testthat::expect_true(result$cached)
  testthat::expect_equal(result$requests,0L)
  testthat::expect_equal(result$transferred_bytes,0)
})
