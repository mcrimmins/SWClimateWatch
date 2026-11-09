# Two cached staging passes. No downloads, API calls, S3 sync or success-marker advancement.
source("R/conditions-synopsis-site.R")
synopsis_test_destination <- Sys.getenv("SWC_S3_DESTINATION", "")
if (!identical(synopsis_test_destination, "s3://cales-climate-reports/climate/watch-staging/"))
  stop("Load staging.env first: this smoke test is restricted to watch-staging/.")
synopsis_test_paths <- synopsis_publication_paths(synopsis_test_destination)
synopsis_test_summary <- list()
synopsis_test_previous <- NULL
for (pass in 1:2) {
  started <- proc.time()[["elapsed"]]
  result <- stage_conditions_synopsis(destination=synopsis_test_destination)
  if (!identical(result$status,"READY")) stop("Synopsis is not ready: ",result$note,
    ". Refresh staging inputs with the daily runner, then repeat this test.")
  evidence <- jsonlite::read_json("data/diagnostics/conditions-synopsis/evidence.json")
  draft <- jsonlite::read_json(file.path(synopsis_test_paths$directory,"draft/draft-evidence.json"))
  audit <- read.csv(file.path(synopsis_test_paths$directory,"draft/highlight-link-audit.csv"))
  quantitative <- Filter(function(b)length(unlist(b$fact_ids))>0L,draft$blocks)
  if (!all(vapply(quantitative,function(b)is.character(b$support_link)&&length(b$support_link)==1L,logical(1))))
    stop("A selected quantitative highlight lacks its supporting page.")
  files <- file.path("site",result$support_manifest$path)
  if (!length(files)||!all(file.exists(files))||
      !identical(unname(tools::md5sum(files)),result$support_manifest$md5)) stop("Staged supporting evidence failed checksum verification.")
  weekly_temperature <- any(vapply(quantitative,function(b)any(grepl("tmean_departure_07day",unlist(b$fact_ids),fixed=TRUE)),logical(1)))
  if (weekly_temperature&&!any(basename(files)=="temperature-7day.png")) stop("Selected weekly temperature claim has no matching map.")
  snow_cache <- isTRUE(evidence$snow_context$cache_reused)
  reused <- identical(result$support_manifest,synopsis_test_previous)
  if (pass==2L) {
    if (!reused) stop("Supporting outputs changed across identical cached passes.")
    if (identical(evidence$snow_context$status,"CHECKED")&&!snow_cache) stop("Second-pass snow evidence did not reuse its cache.")
  }
  synopsis_test_summary[[pass]] <- data.frame(pass=pass,date=result$date,
    elapsed_seconds=round(proc.time()[["elapsed"]]-started,2),
    selected_bullets=length(quantitative),withheld_candidates=sum(!audit$status %in% c("SUPPORTED","NOTICE")),
    supporting_files=length(files),weekly_temperature_map=if(weekly_temperature)"VERIFIED" else "NOT_SELECTED",
    core_cache_reused=isTRUE(evidence$regional_cache_reused),recent_cache_reused=isTRUE(evidence$recent$cache_reused),
    snow_status=evidence$snow_context$status,snow_cache_reused=snow_cache,
    supporting_outputs_reused=if(pass==1L)NA else reused,status="PASS")
  synopsis_test_previous <- result$support_manifest
}
synopsis_test_summary <- do.call(rbind,synopsis_test_summary)
dir.create("data/diagnostics/synopsis-staging-smoke",recursive=TRUE,showWarnings=FALSE)
write.csv(synopsis_test_summary,"data/diagnostics/synopsis-staging-smoke/summary.csv",row.names=FALSE)
print(synopsis_test_summary,row.names=FALSE)
message("Two cached passes verified. No source requests, S3 sync or successful-publication comparison changes.")
