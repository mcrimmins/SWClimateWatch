# Read-only checks before moving a release to a daily production machine.
# Source R/config.R and R/daily-publish.R first, from the project root.

swc_production_preflight <- function(
    root = getwd(), destination = swc_daily_publish_destination()) {
  destination <- swc_daily_publish_destination(destination)
  source(swc_daily_publish_deploy_script(), local = TRUE)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  checks <- list()
  add <- function(group, item, ok, detail = "") {
    checks[[length(checks) + 1L]] <<- data.frame(
      group = group, item = item, status = if (isTRUE(ok)) "PASS" else "MISSING",
      detail = detail, stringsAsFactors = FALSE)
  }
  present <- function(path) {
    full <- file.path(root, path)
    file.exists(full) && !is.na(file.info(full)$size) &&
      file.info(full)$size > 0
  }
  add("code", "Quarto site source", present("site/_quarto.yml"),
      "site/_quarto.yml")
  add("code", "Daily publisher", present("scripts/daily-update-and-publish.R"),
      "scripts/daily-update-and-publish.R")
  for (package in unique(c(swc_packages, "Rcpp", "xml2"))) {
    add("R package", package, requireNamespace(package, quietly = TRUE))
  }
  if(swc_monthly_maps_enabled()) {
    for(package in c("filelock","MASS")) add("R package",package,requireNamespace(package,quietly=TRUE))
    cache <- file.path("data","processed","prism-monthly",swc_prism$aoi_id)
    add("seed file","Monthly PRISM manifest",present(file.path(cache,"manifest.csv")),file.path(cache,"manifest.csv"))
    add("code","Monthly update adapter",present("R/monthly-publish.R"),"R/monthly-publish.R")
  }
  quarto <- tryCatch(swc_deploy_quarto(), error = function(error) "")
  add("command", "Quarto", nzchar(quarto), quarto)
  aws <- Sys.which("aws")
  add("command", "AWS CLI", nzchar(aws), unname(aws))
  if (.Platform$OS.type != "windows") {
    compiler <- Sys.which("g++")
    add("command", "C++ compiler", nzchar(compiler), unname(compiler))
  }

  seed_files <- c(
    "data/raw/prism/manifest.csv",
    "data/processed/prism/manifest.csv",
    "data/processed/snodas/manifest.csv",
    "data/diagnostics/acis-stations/reference-network/daily-audit/stations.csv",
    "site/stations/index.html",
    "site/stations/station-explorer-data.csv")
  for (path in seed_files) add("seed file", path, present(path), path)
  seed_groups <- list(
    "Processed PRISM grids and reference caches" = "data/processed/prism",
    "Processed SNODAS daily grids" = "data/processed/snodas",
    "Station daily caches" = "data/processed/acis-stations/reference-network/daily",
    "Generated map PNGs" = "site/maps/generated",
    "Station detail JSON files" = "site/stations/station-details")
  for (name in names(seed_groups)) {
    path <- file.path(root, seed_groups[[name]])
    pattern <- if (identical(name, "Generated map PNGs")) "\\.png$" else NULL
    count <- if (dir.exists(path)) length(list.files(
      path, pattern = pattern, recursive = TRUE, all.files = FALSE)) else 0L
    add("seed directory", name, count > 0L,
        paste0(seed_groups[[name]], " (", count, " files)"))
  }
  snow_page <- file.path(root, "site", "pages", "current-snow.qmd")
  if (file.exists(snow_page) && any(grepl(
      "swe-observed.png", readLines(snow_page, warn = FALSE), fixed = TRUE))) {
    for (name in c("swe-observed.png", "swe-departure.png")) {
      path <- file.path("site", "maps", "generated", "snodas", "current", name)
      add("seed file", paste("Current snow", name), present(path), path)
    }
  }
  checks <- do.call(rbind, checks)
  timezone <- Sys.getenv("TZ", unset = Sys.timezone())
  list(ready = all(checks$status == "PASS"), checks = checks,
       destination = destination,
       staging_destination = !identical(
         destination, swc_daily_publish_live_destination()),
       timezone = timezone,
       timezone_matches = identical(timezone, "America/Phoenix"))
}
