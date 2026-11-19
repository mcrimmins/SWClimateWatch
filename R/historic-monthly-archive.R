# Full existing-archive expansion. No source/page publication or new downloads.
historic_monthly_archive_years <- function(site_dir = "site") {
  files <- list.files(file.path(site_dir, "pages/archive"), pattern = "^wy[0-9]{4}[.]qmd$", full.names = FALSE)
  years <- sort(as.integer(sub("^wy([0-9]{4})[.]qmd$", "\\1", files)))
  if (!length(years) || anyNA(years) || anyDuplicated(years) || any(years < 1896L))
    stop("No valid existing Historic Years page set found.")
  years
}

build_historic_monthly_archive <- function(years = historic_monthly_archive_years(),
    output_dir = "data/diagnostics/historic-monthly-archive",
    seed_dir = "data/diagnostics/historic-monthly-pilot", site_dir = "site",
    end = prism_monthly_latest_complete(), force = FALSE) {
  existing <- historic_monthly_archive_years(site_dir)
  historic_monthly_windows(years)
  if (any(!years %in% existing)) stop("This batch may only build existing Historic Years pages.")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  root <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)
  if (!startsWith(tolower(root), paste0(tolower(normalizePath("data/diagnostics", winslash = "/")), "/")))
    stop("Archive review output must remain inside data/diagnostics.")
  if (!requireNamespace("filelock", quietly = TRUE)) stop("Install filelock before running the archive batch.")
  lock <- filelock::lock(file.path(root, "build.lock"), timeout = 0)
  if (is.null(lock)) stop("Another archive build holds this output folder's lock.")
  on.exit(filelock::unlock(lock), add = TRUE)
  pages <- file.path(site_dir, "pages/archive", paste0("wy", years, ".qmd"))
  hashes <- unname(tools::md5sum(pages))
  scope <- data.frame(water_year = years, source_page = pages, source_md5 = hashes,
    monthly_maps = historic_monthly_products_per_year())
  write.csv(scope, file.path(root, "year-scope.csv"), row.names = FALSE)
  message("Existing Historic Years batch: ", length(years), " years, ", 21L * length(years),
    " maps. Verified pilot caches can seed this separate folder; interrupted batches resume.")
  tryCatch({
    result <- build_historic_monthly_pilot(years = years, end = end, output_dir = root,
      seed_dir = seed_dir, force = force)
    if (!identical(unname(tools::md5sum(pages)), hashes)) stop("Source Historic Years pages changed during the build; rerun to reconcile scope.")
    write.csv(result$summary, file.path(root, "archive-status.csv"), row.names = FALSE)
    result
  }, error = function(e) {
    write.csv(data.frame(status = "PARTIAL", years = length(years), expected_maps = 21L * length(years),
      requests = 0L, note = conditionMessage(e)), file.path(root, "archive-status.csv"), row.names = FALSE)
    stop(e)
  })
}

check_historic_monthly_archive_maps <- function(root = "data/diagnostics/historic-monthly-archive",
    site_dir = "site", expected_years = historic_monthly_archive_years(site_dir)) {
  if (dir.exists(root)) write.csv(data.frame(status = "CHECKING"),
    file.path(root, "validation-status.csv"), row.names = FALSE)
  scope <- read.csv(file.path(root, "year-scope.csv"), stringsAsFactors = FALSE)
  manifest <- read.csv(file.path(root, "manifest.csv"), stringsAsFactors = FALSE)
  if (!identical(sort(scope$water_year), sort(as.integer(expected_years))) ||
      !identical(sort(unique(manifest$water_year)), sort(as.integer(expected_years))))
    stop("Archive batch is missing or has extra years relative to the existing pages.")
  if (!identical(unname(tools::md5sum(scope$source_page)), scope$source_md5))
    stop("Existing Historic Years pages changed since the batch scope was recorded.")
  old <- options(swc.historic.monthly.check_root = root)
  on.exit(options(old), add = TRUE)
  source("scripts/check-historic-monthly-pilot.R", local = new.env(parent = globalenv()))
  result <- data.frame(status = "PASS", years = length(expected_years), monthly_maps = nrow(manifest), requests = 0L)
  write.csv(result, file.path(root, "validation-status.csv"), row.names = FALSE)
  result
}
