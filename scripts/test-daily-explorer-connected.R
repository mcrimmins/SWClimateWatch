testthat::test_file("tests/testthat/test-daily-explorer-connected.R",stop_on_failure=TRUE)
node<-c(getOption("swc.interactive.node",""),unname(Sys.which("node")),"data/diagnostics/local-test-tools/node.exe",
  file.path(Sys.getenv("ProgramFiles"),"nodejs/node.exe"),Sys.glob(file.path(Sys.getenv("ProgramFiles"),"WindowsApps","OpenAI.CodexPrimaryRuntime.*","dependencies/node/bin/node.exe")))
node<-node[nzchar(node)&file.exists(node)]
if(!length(node))stop("Set options(swc.interactive.node='C:/path/to/node.exe') for browser-code checks.")
for(f in c("tests/daily-explorer-connected.cjs","tests/daily-explorer-connected-bridge.cjs"))
  stopifnot(system2(node[1],f)==0L)
for(f in c("connected-model.js","connected-shell.js","connected-bridge.js"))
  stopifnot(system2(node[1],c("--check",paste0("scripts/daily-explorer-archive-assets/",f)))==0L)
source("scripts/load-daily-explorer-connected.R")
# The build fully validated the immutable archive. Recheck its release digest
# and every file's size/mtime, plus all current/UI hashes; avoid rereading GBs.
connected_check<-validate_connected_explorer(full_archive=FALSE)
