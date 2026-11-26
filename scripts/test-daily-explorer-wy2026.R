testthat::test_file("tests/testthat/test-daily-explorer-wy2026.R",stop_on_failure=TRUE)
testthat::test_file("tests/testthat/test-storm-reports-archive-retry.R",stop_on_failure=TRUE)
node<-c(getOption("swc.interactive.node",""),unname(Sys.which("node")),"data/diagnostics/local-test-tools/node.exe",
  file.path(Sys.getenv("ProgramFiles"),"nodejs/node.exe"),Sys.glob(file.path(Sys.getenv("ProgramFiles"),"WindowsApps","OpenAI.CodexPrimaryRuntime.*","dependencies/node/bin/node.exe")))
node<-node[nzchar(node)&file.exists(node)]
if(!length(node))stop("Set options(swc.interactive.node='C:/path/to/node.exe') to run browser-code checks.")
for(file in c("tests/daily-explorer-archive-model.cjs","tests/daily-explorer-month-context.cjs","tests/daily-explorer-archive-errors.cjs","tests/daily-explorer-archive-sizing.cjs","tests/daily-explorer-archive-bridge.cjs"))
  stopifnot(system2(node[1],file)==0L)
source("scripts/check-daily-explorer-wy2026.R")
