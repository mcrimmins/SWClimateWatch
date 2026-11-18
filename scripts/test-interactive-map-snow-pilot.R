source("scripts/load-snodas-current-site.R")
source("R/interactive-map-snow-pilot.R")
r <- terra::rast(nrows = 2, ncols = 4, xmin = -112, xmax = -110, ymin = 33, ymax = 34, crs = "EPSG:4326")
make <- function(v) terra::setValues(r, v)
date <- as.Date("2025-02-15")
observed <- make(c(0, 2, 2, 2, NA, 0, 4, 1)); terra::time(observed) <- date
median <- make(c(2, 0, .5, 1, 2, 0, 2, NA))
years <- make(c(21, 21, 21, 17, 21, 21, 18, NA))
p <- snodas_daily_percent_swe(observed, median, years, date)
inputs <- list(observed = observed, median_swe = median, sample_years = years, departure = observed - median)
v <- interactive_snow_fields(inputs, p, NULL)
stopifnot(identical(as.integer(v$percent_status), c(1L,2L,2L,3L,3L,2L,1L,3L)),
  identical(v$percent[c(1,7)], c(0,200)), all(is.na(v$percent[-c(1,7)])),
  v$observed[1] == 0, v$departure_status[4] == 1, all(is.na(v$change)))
prior <- observed; terra::time(prior) <- date - 6L
bad <- tryCatch({snodas_seven_day_swe_change(observed, prior, date); FALSE}, error = function(e) TRUE)
stopifnot(bad)
message("PASS: zero/tiny medians, 17/18-year support, missing observations and exact endpoint guards.")
find_snow_test_node <- function() {
  override <- getOption("swc.interactive.node", "")
  if (length(override) != 1L || is.na(override)) stop("Set swc.interactive.node to one executable path.")
  if (nzchar(override)) {
    if (!file.exists(override)) stop("Configured Node executable does not exist: ", override)
    return(override)
  }
  candidates <- c(file.path("data", "diagnostics", "local-test-tools",
    if (.Platform$OS.type == "windows") "node.exe" else "node"),
    unname(Sys.which("node")))
  if (.Platform$OS.type == "windows") {
    program_files <- Sys.getenv("ProgramFiles", "C:/Program Files")
    local_app_data <- Sys.getenv("LOCALAPPDATA")
    candidates <- c(candidates,
      file.path(program_files, "nodejs", "node.exe"),
      file.path(local_app_data, "Programs", "nodejs", "node.exe"),
      file.path(Sys.getenv("NVM_SYMLINK"), "node.exe"),
      Sys.glob(file.path(program_files, "WindowsApps", "OpenAI.CodexPrimaryRuntime.*",
        "dependencies", "node", "bin", "node.exe")))
  }
  candidates <- unique(candidates[nzchar(candidates)])
  candidates <- candidates[file.exists(candidates) & !dir.exists(candidates)]
  if (!length(candidates)) stop(
    "R checks passed, but JavaScript checks have not run: Node was not found. ",
    "Set options(swc.interactive.node = 'C:/path/to/node.exe') and rerun. ",
    "You can still run scripts/preview-interactive-map-snow-pilot.R to review the viewer.",
    call. = FALSE)
  normalizePath(candidates[[1L]], winslash = "/", mustWork = TRUE)
}
node <- find_snow_test_node()
message("Running JavaScript checks with: ", node)
status <- system2(node, "tests/interactive-map-snow.cjs")
if (status != 0) stop("Snow viewer checks failed.")
