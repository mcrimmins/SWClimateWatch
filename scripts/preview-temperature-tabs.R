# Isolated local Quarto preview: no site changes, calculations or deployment.
source("R/temperature-tabs-preview.R")
temperature_tabs_preview <- build_temperature_tabs_preview()
swc_temperature_quarto <- unname(Sys.which("quarto"))
if (!nzchar(swc_temperature_quarto) && requireNamespace("quarto", quietly = TRUE))
  swc_temperature_quarto <- tryCatch(quarto::quarto_path(), error = function(e) "")
if (!nzchar(swc_temperature_quarto) && .Platform$OS.type == "windows") {
  candidates <- c(file.path(Sys.getenv("ProgramFiles"), "RStudio/resources/app/bin/quarto/bin/quarto.cmd"),
    file.path(Sys.getenv("ProgramFiles"), "Quarto/bin/quarto.cmd"))
  candidates <- candidates[file.exists(candidates)]
  if (length(candidates)) swc_temperature_quarto <- candidates[1]
}
if (!nzchar(swc_temperature_quarto)) stop("Quarto was not found. Run from RStudio or install Quarto.")
if (.Platform$OS.type == "windows") swc_temperature_quarto <- utils::shortPathName(swc_temperature_quarto)
swc_temperature_status <- system2(swc_temperature_quarto, c("render", shQuote(temperature_tabs_preview$directory)))
if (swc_temperature_status != 0L) stop("Temperature preview render failed.")
temperature_tabs_validation <- check_temperature_tabs_preview(temperature_tabs_preview$directory)
temperature_tabs_url <- normalizePath(file.path(temperature_tabs_preview$directory, "_site/index.html"))
if (interactive()) utils::browseURL(temperature_tabs_url)
message("Local preview: ", temperature_tabs_url)
