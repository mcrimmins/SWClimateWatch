# Small isolated smoke test. Downloads six regional grids; no render or S3 sync.
source("R/config.R")
source("R/acis-prism.R")

run_prism_latest_smoke_test <- function() {
  directory <- tempfile("prism-latest-smoke-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  today <- as.Date(format(Sys.time(), tz = "America/Phoenix", format = "%Y-%m-%d"))
  fallback <- sync_prism("update", today = today, raw_dir = directory,
    try_yesterday = TRUE,
    revision_ages = 2L, manifest = data.frame(), max_requests = 6L,
    availability_path = file.path(directory, "status.csv"),
    candidate_function = function(plan, ...) download_prism_latest_set(plan, ...,
      fetch_function = function(item, path) stop("Simulated unavailable yesterday")))
  fallback_status <- attr(fallback, "availability")
  stopifnot(fallback_status$status == "FALLBACK", nrow(fallback) == 3L,
            fallback_status$selected_date == as.character(today - 2L))
  plan <- plan_prism_download("update", today = today, raw_dir = directory,
    revision_ages = 2L)
  live <- download_prism_latest_set(plan)
  stopifnot(live$status$status %in% c("ACCEPTED", "FALLBACK"))
  manifest <- read_prism_manifest(prism_manifest_path(directory))
  if (live$status$status == "ACCEPTED") {
    stopifnot(nrow(live$records) == 3L, nrow(manifest) == 6L,
              live$status$selected_date == as.character(today - 1L))
  } else stopifnot(nrow(live$records) == 0L, nrow(manifest) == 3L)
  result <- rbind(transform(fallback_status, scenario = "simulated unavailability"),
                  transform(live$status, scenario = "live yesterday"))
  report <- "data/diagnostics/prism-availability/live-smoke.csv"
  dir.create(dirname(report), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(result, report, row.names = FALSE)
  print(result, row.names = FALSE)
  message("Smoke test passed. Temporary grids removed on exit; no operational data, maps or S3 changed.")
  invisible(result)
}

prism_latest_smoke <- run_prism_latest_smoke_test()
