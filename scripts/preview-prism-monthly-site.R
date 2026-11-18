# Stage, render and validate the local Monthly Climate page. No deployment.
source("scripts/stage-prism-monthly-site.R")
swc_monthly_quarto <- unname(Sys.which("quarto"))
if (!nzchar(swc_monthly_quarto) && requireNamespace("quarto", quietly = TRUE)) {
  swc_monthly_quarto <- tryCatch(quarto::quarto_path(), error = function(e) "")
}
if (!nzchar(swc_monthly_quarto) && .Platform$OS.type == "windows") {
  candidates <- c(file.path(Sys.getenv("ProgramFiles"), "RStudio/resources/app/bin/quarto/bin/quarto.cmd"),
    file.path(Sys.getenv("ProgramFiles"), "Quarto/bin/quarto.cmd"))
  candidates <- candidates[file.exists(candidates)]
  if (length(candidates)) swc_monthly_quarto <- candidates[1]
}
if (!nzchar(swc_monthly_quarto)) stop("Quarto was not found. Install Quarto or run from RStudio.")
if (.Platform$OS.type == "windows") swc_monthly_quarto <- utils::shortPathName(swc_monthly_quarto)
swc_monthly_render_status <- system2(swc_monthly_quarto,
  c("render", "site/pages/monthly-climate.qmd"))
if (swc_monthly_render_status != 0L) stop("Monthly page rendering failed; nothing published.")
source("scripts/check-prism-monthly-publication.R")
if (interactive()) utils::browseURL(normalizePath("site/_site/pages/monthly-climate.html"))
message("Local preview: site/_site/pages/monthly-climate.html")
