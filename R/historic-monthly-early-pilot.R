# Bounded pre-1982 review only. Never creates operational archive pages.
historic_monthly_early_years <- function() c(1896L, 1934L, 1977L)
historic_monthly_early_root <- function() "data/diagnostics/historic-monthly-early-pilot"
historic_monthly_early_site <- function() "data/diagnostics/historic-monthly-early-site"

build_historic_monthly_early_pilot <- function() {
  root <- historic_monthly_early_root()
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  lock <- filelock::lock(file.path(root, "build.lock"), timeout = 0)
  if (is.null(lock)) stop("Another early Historic Years pilot build is running.")
  on.exit(filelock::unlock(lock), add = TRUE)
  build_historic_monthly_pilot(years = historic_monthly_early_years(), output_dir = root,
    seed_dir = "data/diagnostics/historic-monthly-archive")
}

check_historic_monthly_early_pilot <- function(root = historic_monthly_early_root()) {
  rows <- read.csv(file.path(root, "manifest.csv"))
  if (!identical(sort(unique(rows$water_year)), historic_monthly_early_years()) || nrow(rows) != 63L)
    stop("Early pilot must contain exactly WY1896, WY1934 and WY1977: 63 maps.")
  write.csv(data.frame(status = "CHECKING"), file.path(root, "validation-status.csv"), row.names = FALSE)
  old <- options(swc.historic.monthly.check_root = root)
  on.exit(options(old), add = TRUE)
  source("scripts/check-historic-monthly-pilot.R", local = new.env(parent = globalenv()))
  result <- data.frame(status = "PASS", years = 3L, maps = 63L, requests = 0L)
  write.csv(result, file.path(root, "validation-status.csv"), row.names = FALSE)
  result
}
