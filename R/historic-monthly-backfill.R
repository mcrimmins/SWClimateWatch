# Local-only WY1896-1981 expansion; never writes operational archive pages.
historic_monthly_backfill_years <- function() 1896L:1981L
historic_monthly_backfill_root <- function() "data/diagnostics/historic-monthly-backfill"
historic_monthly_backfill_site <- function() "data/diagnostics/historic-monthly-backfill-site"

historic_monthly_backfill_scope <- function(root, expected_years = historic_monthly_backfill_years()) {
  scope <- read.csv(file.path(root, "year-scope.csv"))
  rows <- read.csv(file.path(root, "manifest.csv"))
  if (!identical(sort(scope$water_year), sort(as.integer(expected_years))) ||
      !identical(sort(unique(rows$water_year)), sort(as.integer(expected_years))) ||
      anyDuplicated(scope$water_year) || any(scope$monthly_maps != 21L) ||
      nrow(rows) != 21L * length(expected_years))
    stop("Backfill scope is missing or has extra years/maps; the full default is WY1896-WY1981, 1806 maps.")
  protected <- read.csv(file.path(root, "protected-files.csv"), stringsAsFactors = FALSE)
  if (anyNA(protected$md5) || !identical(unname(tools::md5sum(protected$path)), protected$md5))
    stop("Protected site pages or publication bundle metadata changed during the local backfill.")
  invisible(rows)
}

build_historic_monthly_backfill <- function(years = historic_monthly_backfill_years(),
    output_dir = historic_monthly_backfill_root(),
    seed_dir = "data/diagnostics/historic-monthly-early-pilot") {
  historic_monthly_windows(years)
  if (any(!years %in% historic_monthly_backfill_years())) stop("Backfill years must remain within WY1896-WY1981.")
  allowed <- paste0(tolower(normalizePath("data/diagnostics", winslash = "/", mustWork = TRUE)), "/")
  if (basename(output_dir) %in% c(".", "..")) stop("Specify a named backfill output folder.")
  root <- file.path(normalizePath(dirname(output_dir), winslash = "/", mustWork = TRUE), basename(output_dir))
  if (!startsWith(tolower(root), allowed)) stop("Backfill outputs must remain under data/diagnostics.")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  lock <- filelock::lock(file.path(root, "build.lock"), timeout = 0)
  if (is.null(lock)) stop("Another backfill build holds this output folder's lock.")
  on.exit(filelock::unlock(lock), add = TRUE)
  protected_paths <- c(list.files("site/pages/archive", pattern = "^wy[0-9]{4}[.]qmd$", full.names = TRUE),
    "site/_quarto.yml", "data/processed/historic-monthly-release/manifest.csv",
    "data/processed/historic-monthly-release/release.json")
  protected_paths <- protected_paths[file.exists(protected_paths)]
  protected <- data.frame(path = protected_paths, md5 = unname(tools::md5sum(protected_paths)))
  write.csv(protected, file.path(root, "protected-files.csv"), row.names = FALSE)
  write.csv(data.frame(water_year = sort(as.integer(years)), monthly_maps = 21L),
    file.path(root, "year-scope.csv"), row.names = FALSE)
  write.csv(data.frame(status = "CHECKING"), file.path(root, "validation-status.csv"), row.names = FALSE)
  message("Local early archive: ", length(years), " years, ", 21L * length(years),
    " maps. Verified early-pilot maps/references seed this resumable batch.")
  tryCatch({
    result <- build_historic_monthly_pilot(years = years, output_dir = root, seed_dir = seed_dir)
    historic_monthly_backfill_scope(root, expected_years = years)
    write.csv(result$summary, file.path(root, "archive-status.csv"), row.names = FALSE)
    result
  }, error = function(e) {
    write.csv(data.frame(status = "PARTIAL", years = length(years), expected_maps = 21L * length(years),
      note = conditionMessage(e)), file.path(root, "archive-status.csv"), row.names = FALSE)
    stop(e)
  })
}

check_historic_monthly_backfill_maps <- function(root = historic_monthly_backfill_root(),
    expected_years = historic_monthly_backfill_years()) {
  if (dir.exists(root)) write.csv(data.frame(status = "CHECKING"),
    file.path(root, "validation-status.csv"), row.names = FALSE)
  rows <- historic_monthly_backfill_scope(root, expected_years)
  old <- options(swc.historic.monthly.check_root = root)
  on.exit(options(old), add = TRUE)
  source("scripts/check-historic-monthly-pilot.R", local = new.env(parent = globalenv()))
  result <- data.frame(status = "PASS", years = length(expected_years), monthly_maps = nrow(rows), requests = 0L)
  write.csv(result, file.path(root, "validation-status.csv"), row.names = FALSE)
  result
}
