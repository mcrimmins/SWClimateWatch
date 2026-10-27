# Isolated VM benchmark. Run with Rscript from this checkout's project root.
# No production configuration, historical caches, Quarto render or S3 access.
run_weather_vm_test <- function() {
  output <- file.path("data","diagnostics","weather-circulation-vm-test")
  dir.create(output,recursive=TRUE,showWarnings=FALSE)
  started <- Sys.time()
  packages <- c("terra","httr2","ggplot2","maps","scales")
  installed <- vapply(packages,requireNamespace,logical(1),quietly=TRUE)
  versions <- vapply(packages,function(pkg) if (installed[[pkg]])
    as.character(utils::packageVersion(pkg)) else "MISSING",character(1))
  git_revision <- tryCatch(system2("git",c("rev-parse","HEAD"),stdout=TRUE,stderr=FALSE),
    error=function(e) "unavailable")
  environment <- data.frame(item=c("started_utc","R","platform","system","cores","timezone","commit",packages),
    value=c(format(started,"%Y-%m-%d %H:%M:%S UTC",tz="UTC"),R.version.string,
      R.version$platform,Sys.info()[["sysname"]],as.character(parallel::detectCores()),
      Sys.timezone(),paste(git_revision,collapse=" "),versions))
  utils::write.csv(environment,file.path(output,"environment.csv"),row.names=FALSE)
  writeLines(capture.output(sessionInfo()),file.path(output,"session-info.txt"))
  result <- tryCatch({
    if (!all(installed)) stop("Missing packages: ",paste(packages[!installed],collapse=", "))
    source("scripts/load-weather-circulation-pilot.R")
    source("R/weather-circulation-recent-test.R")
    pilot <- run_weather_circulation_recent_test(output_dir=output)
    if (pilot$summary$probe_errors>0 || pilot$summary$dates_built!=3L ||
        !isTRUE(pilot$summary$cache_check_pass))
      stop("Recent test requires review; inspect availability and cache reports.")
    list(status="PASS",note="Three dates rendered and download-cache reuse verified.",pilot=pilot)
  },error=function(e) list(status="FAILED",note=conditionMessage(e)))
  status <- data.frame(status=result$status,note=result$note,
    elapsed_seconds=as.numeric(difftime(Sys.time(),started,units="secs")),
    finished_utc=format(Sys.time(),"%Y-%m-%d %H:%M:%S UTC",tz="UTC"))
  utils::write.csv(status,file.path(output,"vm-test-status.csv"),row.names=FALSE)
  print(status,row.names=FALSE)
  message("Reports: ",output)
  if (result$status!="PASS") stop(result$note,call.=FALSE)
  invisible(result)
}
swc_weather_vm_test <- run_weather_vm_test()
