source("R/storm-reports-pilot.R")
result<-testthat::test_file("tests/testthat/test-storm-reports-pilot.R",stop_on_failure=TRUE)
directory<-"data/diagnostics/daily-explorer-storm-reports"
if(!file.exists(file.path(directory,"storm-reports-manifest.json")))stop("Build the report pilot first.")
x<-jsonlite::read_json(file.path(directory,"storm-reports-manifest.json"))
for(day in x$days) {
  p<-jsonlite::read_json(file.path(directory,day$path))
  stopifnot(identical(p$date,day$date),length(p$reports)==day$reports,
    all(vapply(p$reports,function(r)r$date==day$date&&r$state%in%c("AZ","NM"),logical(1))))
}
rows<-unlist(lapply(x$days,function(day)jsonlite::read_json(file.path(directory,day$path))$reports),recursive=FALSE)
times<-as.POSIXct(vapply(rows,`[[`,character(1),"valid"),format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
for(timing in c("prism","utc")) {
  # Independently assign event timestamps to date labels, then verify all totals.
  labels<-format(times+if(timing=="prism")43200 else 0,"%Y-%m-%d",tz="UTC")
  for(day in x$timeline[[timing]])for(region in c("AZNM","AZ","NM")) {
    expected<-sum(labels==day$date&vapply(rows,function(r)region=="AZNM"||r$state==region,logical(1)))
    stopifnot(day$regions[[region]]$total==expected,
      sum(unlist(day$regions[[region]]$types))==expected)
  }
}
message("PASS: storm-report normalization and all cached daily payloads.")
node_candidates<-c(getOption("swc.interactive.node",""),unname(Sys.which("node")),
  "data/diagnostics/local-test-tools/node.exe",
  file.path(Sys.getenv("ProgramFiles"),"nodejs","node.exe"),
  Sys.glob(file.path(Sys.getenv("ProgramFiles"),"WindowsApps","OpenAI.CodexPrimaryRuntime.*","dependencies","node","bin","node.exe")))
node_candidates<-node_candidates[nzchar(node_candidates)&file.exists(node_candidates)&!dir.exists(node_candidates)]
if(!length(node_candidates))stop("R checks passed; JavaScript checks still need Node. Set options(swc.interactive.node='C:/path/to/node.exe') and rerun. Preview remains available.")
for(script in c("tests/storm-reports-controls.cjs","tests/storm-report-view-stats.cjs")) {
  status<-system2(node_candidates[[1]],script)
  if(status!=0)stop("Storm report browser checks failed: ",script)
}
