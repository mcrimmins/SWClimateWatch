# Run from a project-root RStudio terminal, for example:
# Rscript scripts/run-snodas-baseline.R 2005-2007
# Rscript scripts/run-snodas-baseline.R 2005,2008,2012
# Rscript scripts/run-snodas-baseline.R --preview 2005-2025
# Rscript scripts/run-snodas-baseline.R --max-stages=4 2005-2007
# Years must be explicit; the script never defaults to the full record.

arguments <- commandArgs(trailingOnly = TRUE)
preview_only <- "--preview" %in% arguments
arguments <- arguments[arguments != "--preview"]
stage_arg <- grep("^--max-stages=", arguments, value = TRUE)
if (length(stage_arg) > 1L ||
    (length(stage_arg) && !grepl("^--max-stages=[1-9][0-9]*$", stage_arg))) {
  stop("Use at most one positive --max-stages=N option.", call. = FALSE)
}
max_stages <- if (length(stage_arg)) {
  as.integer(sub("^--max-stages=", "", stage_arg))
} else Inf
arguments <- arguments[!grepl("^--max-stages=", arguments)]
if (length(arguments) != 1L) {
  stop("Usage: Rscript scripts/run-snodas-baseline.R [--preview] ",
       "YYYY or YYYY-YYYY or YYYY,YYYY,...", call. = FALSE)
}
choice <- arguments[[1L]]
if (grepl("^[0-9]{4}-[0-9]{4}$", choice)) {
  endpoints <- as.integer(strsplit(choice, "-", fixed = TRUE)[[1L]])
  if (endpoints[1L] > endpoints[2L]) {
    stop("The starting water year must not follow the ending year.",
         call. = FALSE)
  }
  years <- seq.int(endpoints[1L], endpoints[2L])
} else if (grepl("^[0-9]{4}(,[0-9]{4})*$", choice)) {
  years <- as.integer(strsplit(choice, ",", fixed = TRUE)[[1L]])
} else {
  stop("Invalid water-year selection: ", choice, call. = FALSE)
}

source("scripts/load-snodas-baseline.R")
snodas_baseline_result <- run_snodas_baseline(
  years, max_stages = max_stages, dry_run = preview_only
)
print(snodas_baseline_result$final[, c(
  "water_year", "listed_dates", "known_missing_dates",
  "paired_processed", "processing_pending", "processed_mb"
)], row.names = FALSE)
if (snodas_baseline_result$stage_limit_reached) {
  message("Stage limit reached; rerun the same command to resume.")
}
