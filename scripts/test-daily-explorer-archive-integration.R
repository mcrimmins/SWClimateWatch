source("scripts/load-daily-explorer-archive-integration.R")
directory<-"data/diagnostics/daily-explorer-archive-integrated"
validate_daily_explorer_archive_integration(directory)
catalog<-jsonlite::read_json(file.path(directory,"archive-catalog.json"))
stopifnot(sum(vapply(catalog$months,function(m)length(m$dates),integer(1)))==36L)
# Detect modified copied browser code and leave the accepted sources intact.
file<-file.path(directory,"bundles/2025-07/archive-month-bridge.js")
saved<-readBin(file,"raw",n=file.info(file)$size)
writeBin(c(saved,charToRaw("\n// tamper fixture\n")),file)
rejected<-inherits(try(validate_daily_explorer_archive_integration(directory),silent=TRUE),"try-error")
writeBin(saved,file);stopifnot(rejected)
validate_daily_explorer_archive_integration(directory)
node<-c(getOption("swc.interactive.node",""),unname(Sys.which("node")),"data/diagnostics/local-test-tools/node.exe",
  file.path(Sys.getenv("ProgramFiles"),"nodejs/node.exe"),Sys.glob(file.path(Sys.getenv("ProgramFiles"),"WindowsApps","OpenAI.CodexPrimaryRuntime.*","dependencies/node/bin/node.exe")))
node<-node[nzchar(node)&file.exists(node)]
if(!length(node))stop("R checks passed; set options(swc.interactive.node='C:/path/to/node.exe') for browser-code checks.")
stopifnot(system2(node[1],"tests/daily-explorer-integrated-model.cjs")==0L)
for(file in c("scripts/daily-explorer-archive-assets/archive-shell.js","scripts/daily-explorer-archive-assets/archive-month-bridge.js"))
  stopifnot(system2(node[1],c("--check",file))==0L)
message("PASS: full July route, isolated month assets, source preservation, checksums and unsupported-date guards. Nothing downloaded or published.")
