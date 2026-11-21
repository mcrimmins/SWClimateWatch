source("R/station-history-csv-check.R")
node_candidates <- unique(c(getOption("swc.interactive.node", ""), unname(Sys.which("node")),
  "data/diagnostics/local-test-tools/node.exe", file.path(Sys.getenv("ProgramFiles", "C:/Program Files"), "nodejs/node.exe"),
  Sys.glob(file.path(Sys.getenv("ProgramFiles", "C:/Program Files"), "WindowsApps/OpenAI.CodexPrimaryRuntime.*/dependencies/node/bin/node.exe"))))
node_candidates <- node_candidates[nzchar(node_candidates) & file.exists(node_candidates)]
if (!length(node_candidates)) stop("Set options(swc.interactive.node = 'C:/path/to/node.exe') to run CSV worker checks.")
if (system2(node_candidates[1L], "tests/station-custom-chart-selection.cjs") != 0L) stop("Chart/CSV interaction checks failed.")
csv_check_dir <- "data/diagnostics/station-history-csv-check"
status <- system2(node_candidates[1L], c("tests/station-history-csv-export.cjs", "data/diagnostics/station-history-integration/custom-history", csv_check_dir))
if (status != 0L) stop("Browser worker CSV export check failed.")
cases <- jsonlite::read_json(file.path(csv_check_dir, "cases.json"), simplifyVector = TRUE)
csv_check <- do.call(rbind, lapply(cases$filename, function(file) check_station_history_csv(file.path(csv_check_dir, file))))
write.csv(csv_check, file.path(csv_check_dir, "validation.csv"), row.names = FALSE)
print(csv_check, row.names = FALSE)
message("CSV contents verified. To check a file saved by your browser, run validate_station_history_csv_download() and choose it.")
