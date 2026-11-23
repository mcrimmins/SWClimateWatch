testthat::test_file("tests/testthat/test-nws-hazards-pilot.R",stop_on_failure=TRUE)
directory<-"data/diagnostics/nws-hazards-pilot"
if(file.exists(file.path(directory,"catalog.json"))) {
  catalog<-jsonlite::read_json(file.path(directory,"catalog.json"))
  for(case in catalog$cases) {
    x<-jsonlite::read_json(file.path(directory,case$path))
    stopifnot(is.null(names(x$events)),length(x$events)==case$events)
    ids<-vapply(x$events,`[[`,character(1),"id");stopifnot(!anyDuplicated(ids))
    bundles<-lapply(x$geometry_bundles,function(path)jsonlite::read_json(file.path(directory,path)))
    for(e in x$events)for(s in e$segments) {
      stopifnot(is.null(names(e$segments)),is.null(names(s$states)),s$start<s$end)
      if(!is.null(s$geometry)) {
        g<-bundles[[substr(s$geometry,1,1)]][[s$geometry]]
        stopifnot(g$type%in%c("Polygon","MultiPolygon"),length(g$coordinates)>0)
      }
    }
  }
  message("PASS: all built metadata arrays, unique event IDs and geometry references.")
}
node_candidates<-c(getOption("swc.interactive.node",""),unname(Sys.which("node")),
  "data/diagnostics/local-test-tools/node.exe",file.path(Sys.getenv("ProgramFiles"),"nodejs","node.exe"),
  Sys.glob(file.path(Sys.getenv("ProgramFiles"),"WindowsApps","OpenAI.CodexPrimaryRuntime.*","dependencies","node","bin","node.exe")))
node_candidates<-node_candidates[nzchar(node_candidates)&file.exists(node_candidates)]
if(!length(node_candidates))stop("R checks passed; set options(swc.interactive.node='C:/path/to/node.exe') to run JavaScript checks.")
stopifnot(system2(node_candidates[1],"tests/nws-hazards-model.cjs")==0L)
stopifnot(system2(node_candidates[1],c("--check","scripts/nws-hazards-assets/hazards.js"))==0L)
