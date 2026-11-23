testthat::test_file("tests/testthat/test-nws-hazards-explorer.R",stop_on_failure=TRUE)
directory<-"data/diagnostics/daily-explorer-nws-hazards"
data<-jsonlite::read_json(file.path(directory,"daily-data.json"))
summary<-jsonlite::read_json(file.path(directory,"hazard-timeline.json"))
events<-jsonlite::read_json(file.path(directory,"hazards/cases/explorer.json"))$events
dates<-vapply(data$days,`[[`,character(1),"date")
stopifnot(isTRUE(data$nws_hazards_preview),!isTRUE(data$publication_mode),is.null(names(events)))
source("R/nws-hazards-explorer.R")
expected<-nws_hazards_timeline(events,dates,summary$start,summary$end_exclusive)
for(timing in c("prism","utc")) {
  stopifnot(identical(vapply(summary$timeline[[timing]],`[[`,character(1),"date"),dates))
  for(i in seq_along(dates))for(region in c("AZNM","AZ","NM")) {
    got<-summary$timeline[[timing]][[i]]$regions[[region]]
    want<-expected[[timing]][[i]]$regions[[region]]
    stopifnot(got$total==want$total,identical(got$types,want$types))
  }
}
html<-paste(readLines(file.path(directory,"index.html")),collapse="\n")
stopifnot(grepl('id="show-report-row" checked',html,fixed=TRUE),
  grepl('id="show-hazard-row" checked',html,fixed=TRUE),grepl('id="hazard-frame"',html,fixed=TRUE),
  length(gregexpr('id="storm-timeline-legend"',html,fixed=TRUE)[[1]])==1L)
source("R/storm-reports-staging.R")
validate_storm_reports_publication(directory,require_enabled=FALSE)
message("PASS: local Explorer, both default timeline rows, all date/region hazard counts and report payloads.")
source("scripts/test-nws-hazards-pilot.R")
stopifnot(system2(node_candidates[1],c("--check","scripts/nws-hazards-assets/hazards-explorer.js"))==0L)
