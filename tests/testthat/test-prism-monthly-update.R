for (file in c("prism-monthly.R", "prism-monthly-audit.R", "prism-monthly-temperature.R",
    "prism-monthly-precipitation.R", "prism-monthly-ranking-pilots.R", "prism-monthly-spi.R", "prism-monthly-update.R")) {
  source(file.path(project_root, "R", file))
}

monthly_update_fixture <- function(root) {
  cache <- file.path(root, "cache"); box <- c(0, 0, 2/24, 2/24)
  fetch <- function(item, destination, offset = 0) {
    r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2/24, ymin = 0, ymax = 2/24, crs = "EPSG:4326")
    value <- switch(item$variable, maxt = 20, mint = 10, pcpn = 1) + offset
    terra::values(r) <- c(value, value, value, NA); terra::time(r) <- prism_monthly_month(item$month)
    terra::writeRaster(r, destination)
  }
  plan <- plan_prism_monthly_download(start = "2023-01", end = "2023-10", cache_dir = cache, bbox = box)
  download_prism_monthly_plan(plan, max_requests = Inf, delay_seconds = 0, fetch = fetch)
  builder <- function(queue, ...) {
    dir <- file.path(root, "fake-products"); dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    markers <- vapply(seq_len(nrow(queue)), function(i) {
      file <- file.path(dir, paste(queue$end_month[i], queue$family[i], queue$duration_months[i], sep = "-"))
      writeLines("test product", file)
      marker <- paste0(file, ".rds")
      saveRDS(list(signature = "test", files = file, md5 = unname(tools::md5sum(file))), marker)
      marker
    }, character(1))
    list(products = data.frame(end_month = queue$end_month, family = queue$family,
      duration_months = queue$duration_months, status = "READY", event = "BUILT", note = ""), artifacts = markers)
  }
  args <- list(today = as.Date("2023-11-02"), start = "2023-01", cache_dir = cache,
    state_dir = file.path(root, "state"), report_dir = file.path(root, "reports"),
    ranking_dir = file.path(root, "rankings"), spi_dir = file.path(root, "spi"),
    audit_dir = file.path(root, "audit"), bbox = box, .fetch = fetch, .build = builder, delay_seconds = 0)
  list(args = args, fetch = fetch, plan = plan,
    run = function(...) do.call(run_prism_monthly_update, utils::modifyList(args, list(...))))
}

testthat::test_that("monthly preview is read-only and respects early-month scheduling", {
  testthat::skip_if_not_installed("filelock")
  root <- tempfile("monthly-preview-"); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- monthly_update_fixture(root)
  preview <- f$run(dry_run = TRUE)
  testthat::expect_equal(preview$summary$pending_requests, 24L)
  testthat::expect_setequal(unique(preview$requests$month), sprintf("2023-%02d", 3:10))
  testthat::expect_false(dir.exists(f$args$state_dir))
  testthat::expect_false(dir.exists(f$args$report_dir))
  outside <- f$run(today = as.Date("2023-11-08"), dry_run = TRUE)
  testthat::expect_equal(outside$summary$status, "SKIPPED_OUTSIDE_WINDOW")
  manual <- f$run(today = as.Date("2023-11-08"), manual = TRUE, dry_run = TRUE)
  testthat::expect_equal(manual$summary$pending_requests, 24L)
})

testthat::test_that("partial downloads preserve accepted inputs and resume only unfinished files", {
  testthat::skip_if_not_installed("filelock")
  root <- tempfile("monthly-resume-"); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- monthly_update_fixture(root)
  old <- unname(tools::md5sum(c(f$plan$path, file.path(f$args$cache_dir, "manifest.csv"))))
  bad <- function(item, destination) {
    if (item$month == "2023-10" && item$variable == "mint") stop("Simulated unavailability")
    f$fetch(item, destination, offset = 1)
  }
  pending <- f$run(.fetch = bad)
  testthat::expect_equal(pending$summary$status, "PENDING_DOWNLOAD")
  testthat::expect_equal(pending$summary$failed_requests, 1L)
  testthat::expect_equal(unname(tools::md5sum(c(f$plan$path, file.path(f$args$cache_dir, "manifest.csv")))), old)
  good <- function(item, destination) f$fetch(item, destination, offset = 1)
  accepted <- f$run(.fetch = good)
  testthat::expect_equal(accepted$summary$status, "COMPLETE")
  testthat::expect_equal(accepted$summary$requests_attempted, 1L)
  testthat::expect_equal(accepted$summary$changed_inputs, 24L)
  testthat::expect_equal(accepted$summary$products_built, 12L)
  repeated <- f$run(.fetch = function(...) stop("Must not download again"))
  testthat::expect_equal(repeated$summary$status, "ALREADY_COMPLETE")
  testthat::expect_equal(repeated$summary$requests_attempted, 0L)
  outside <- f$run(today=as.Date("2023-11-08"),.fetch=function(...) stop("No requests outside window"))
  testthat::expect_equal(outside$summary$status,"ALREADY_COMPLETE")
  testthat::expect_equal(outside$summary$requests_attempted,0L)
  state_path <- file.path(f$args$state_dir,"cycles","2023-11","state.rds")
  state <- readRDS(state_path); state$product_policy <- NULL
  saveRDS(state,state_path)
  changed_display <- f$run(today=as.Date("2023-11-08"),.fetch=function(...) stop("Display changes must not request sources"))
  testthat::expect_equal(changed_display$summary$status,"COMPLETE")
  testthat::expect_equal(changed_display$summary$requests_attempted,0L)
  testthat::expect_identical(readRDS(state_path)$product_policy,prism_monthly_update_product_policy())
})

testthat::test_that("unchanged values retain file checksums and invalid temperature sets are not installed", {
  testthat::skip_if_not_installed("filelock")
  root <- tempfile("monthly-values-"); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- monthly_update_fixture(root)
  old <- unname(tools::md5sum(f$plan$path))
  unchanged <- f$run()
  testthat::expect_equal(unchanged$summary$status, "COMPLETE")
  testthat::expect_equal(unchanged$summary$changed_inputs, 0L)
  testthat::expect_equal(unname(tools::md5sum(f$plan$path)), old)
  manifest <- read.csv(file.path(f$args$cache_dir, "manifest.csv"))
  testthat::expect_true(all(is.na(manifest$source_final_confirmed)))
  testthat::expect_true("STABLE_AGE_EXPECTED" %in% manifest$stability_age)
  bad <- function(item, destination) f$fetch(item, destination, offset = if (item$variable == "mint") 20 else 0)
  invalid <- f$run(refresh_again = TRUE, .fetch = bad)
  testthat::expect_equal(invalid$summary$status, "FAILED")
  testthat::expect_equal(unname(tools::md5sum(f$plan$path)), old)
})

testthat::test_that("failed installation rolls back both files and manifest", {
  testthat::skip_if_not_installed("filelock")
  root <- tempfile("monthly-rollback-"); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- monthly_update_fixture(root)
  paths <- c(f$plan$path, file.path(f$args$cache_dir, "manifest.csv")); old <- unname(tools::md5sum(paths))
  count <- 0L
  install <- function(from, to) {
    count <<- count + 1L
    if (count == 2L) stop("Simulated installation failure")
    prism_monthly_install_file(from, to)
  }
  good <- function(item, destination) f$fetch(item, destination, offset = 1)
  failed <- f$run(.fetch = good, .install = install)
  testthat::expect_equal(failed$summary$status, "FAILED")
  testthat::expect_equal(unname(tools::md5sum(paths)), old)
  completed <- f$run(.fetch = function(...) stop("Staged files should resume without downloads"))
  testthat::expect_equal(completed$summary$status, "COMPLETE")
  testthat::expect_equal(completed$summary$requests_attempted, 0L)
})

testthat::test_that("accepted data with failed products can resume outside the download window", {
  testthat::skip_if_not_installed("filelock")
  root <- tempfile("monthly-products-"); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- monthly_update_fixture(root)
  failed <- f$run(.build = function(...) stop("Simulated map failure"))
  testthat::expect_equal(failed$summary$status, "FAILED")
  state <- readRDS(file.path(f$args$state_dir, "cycles", "2023-11", "state.rds"))
  testthat::expect_equal(state$phase, "DATA_READY")
  completed <- f$run(today = as.Date("2023-11-08"), .fetch = function(...) stop("No new downloads expected"))
  testthat::expect_equal(completed$summary$status, "COMPLETE")
  testthat::expect_equal(completed$summary$requests_attempted, 0L)
})

testthat::test_that("retained rebuild dependencies distinguish temperature, precipitation and SPI", {
  root <- tempfile("monthly-dependencies-"); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  ranks <- file.path(root, "rankings"); spi <- file.path(root, "spi")
  dir.create(file.path(ranks, "2026-09", "temperature", "01month"), recursive = TRUE)
  writeLines("marker", file.path(ranks, "2026-09", "temperature", "01month", "summary.csv"))
  dir.create(file.path(ranks, "2026-09", "precipitation", "03month"), recursive = TRUE)
  writeLines("marker", file.path(ranks, "2026-09", "precipitation", "03month", "summary.csv"))
  changes <- data.frame(month = "2026-08", variable = "pcpn", changed = TRUE)
  queue <- plan_prism_monthly_rebuilds("2026-10", changes, ranking_dir = ranks, spi_dir = spi)
  old <- queue[queue$end_month == "2026-09", ]
  testthat::expect_equal(old$family, "precipitation")
  testthat::expect_equal(old$duration_months, 3L)
  testthat::expect_equal(sum(queue$end_month == "2026-10"), 12)
  testthat::expect_false("2024-08" %in% prism_monthly_spi_dependencies("1895-01", "2026-10", 12))
  testthat::expect_true("2020-08" %in% prism_monthly_spi_dependencies("1895-01", "2026-10", 12))
})

testthat::test_that("request caps resume and an installation journal recovers outside the window", {
  testthat::skip_if_not_installed("filelock")
  root <- tempfile("monthly-cap-"); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- monthly_update_fixture(root)
  capped <- f$run(max_requests = 2L)
  testthat::expect_equal(capped$summary$status, "PENDING_DOWNLOAD")
  preview <- f$run(dry_run = TRUE)
  testthat::expect_equal(preview$summary$pending_requests, 22L)
  completed <- f$run()
  testthat::expect_equal(completed$summary$requests_attempted, 22L)
  testthat::expect_equal(completed$summary$status, "COMPLETE")
  # Simulate a process dying after one file install with its journal persisted.
  state_path <- file.path(f$args$state_dir, "cycles", "2023-11", "state.rds")
  state <- readRDS(state_path)
  original <- f$plan$path[1]; backup <- file.path(root, "journal.backup")
  file.copy(original, backup)
  old <- unname(tools::md5sum(original))
  state$phase <- "INSTALLING"
  state$transaction <- list(entries = data.frame(path = original, existed = TRUE, backup = backup, md5 = old))
  prism_monthly_update_save(state, state_path)
  writeBin(as.raw(1:5), original)
  recovered <- f$run(today = as.Date("2023-12-08"), .fetch = function(...) stop("Outside download window"))
  testthat::expect_equal(recovered$summary$status, "SKIPPED_OUTSIDE_WINDOW")
  testthat::expect_equal(unname(tools::md5sum(original)), old)
  testthat::expect_equal(readRDS(state_path)$phase, "DOWNLOADING")
})
