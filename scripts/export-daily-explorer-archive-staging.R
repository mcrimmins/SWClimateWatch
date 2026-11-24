source("scripts/load-daily-explorer-archive-integration.R")
directory<-"data/diagnostics/daily-explorer-archive-integrated"
validate_daily_explorer_archive_integration(directory)
release<-jsonlite::read_json(file.path(directory,"integration-release.json"))
files<-c(vapply(release$files,`[[`,character(1),"path"),"integration-release.json")
archive<-file.path(normalizePath("data/diagnostics",winslash="/",mustWork=TRUE),"swc-daily-explorer-archive-pilot.tar.gz")
local({
  previous<-getwd();on.exit(setwd(previous),add=TRUE);setwd(directory)
  withCallingHandlers(utils::tar(archive,files=files,compression="gzip",tar="internal"),warning=function(w) {
    # R warns about standard long-path headers; the target VM's GNU tar
    # supports them. Verify the exact archived names below before delivery.
    if(startsWith(conditionMessage(w),"storing paths of more than 100 bytes is not portable"))invokeRestart("muffleWarning")
  })
})
entries<-utils::untar(archive,list=TRUE,tar="internal")
if(!setequal(entries,files)||length(entries)!=length(files))stop("Archive entry names differ from the validated release.")
hash<-digest::digest(file=archive,algo="sha256")
writeBin(charToRaw(paste0(hash,"  ",basename(archive),"\n")),paste0(archive,".sha256"))
message("Bundle entry list verified: ",length(entries)," files.")
message("Publication bundle: ",archive)
message("SHA256: ",hash)
message("Transfer this archive and its .sha256 file. No raw/decoded weather caches are needed.")
