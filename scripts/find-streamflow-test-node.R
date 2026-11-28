find_streamflow_test_node <- function(required=TRUE) {
  override<-getOption("swc.streamflow.node",getOption("swc.interactive.node",""))
  if(length(override)!=1L||is.na(override))stop("Set swc.streamflow.node to one Node executable path.")
  candidates<-if(nzchar(override))override else c(
    file.path("data/diagnostics/local-test-tools",if(.Platform$OS.type=="windows")"node.exe"else"node"),
    unname(Sys.which("node")),file.path(Sys.getenv("ProgramFiles","C:/Program Files"),"nodejs/node.exe"),
    file.path(Sys.getenv("LOCALAPPDATA"),"Programs/nodejs/node.exe"),
    Sys.glob(file.path(Sys.getenv("ProgramFiles","C:/Program Files"),"WindowsApps","OpenAI.CodexPrimaryRuntime.*","dependencies/node/bin/node.exe")))
  candidates<-unique(candidates[nzchar(candidates)])
  for(candidate in candidates[file.exists(candidates)&!dir.exists(candidates)]) {
    version<-tryCatch(suppressWarnings(system2(candidate,"--version",stdout=TRUE,stderr=TRUE)),error=function(e)character())
    if((is.null(attr(version,"status"))||identical(attr(version,"status"),0L))&&any(grepl("^v[0-9]+[.]",version)))
      return(normalizePath(candidate,winslash="/",mustWork=TRUE))
  }
  if(required||nzchar(override))stop("R checks passed, but browser-controller checks have not run: no usable Node executable was found. Set options(swc.streamflow.node='C:/path/to/node.exe') to a real executable, or run scripts/preview-daily-explorer-streamflow.R to review the viewer.",call.=FALSE)
  ""
}
