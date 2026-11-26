source("scripts/load-daily-explorer-wy2026.R")
directory<-"data/diagnostics/daily-explorer-wy2026/preview"
validate_wy2026_explorer_navigation(directory)
release<-jsonlite::read_json(file.path(directory,"wy2026-release.json"))
files<-c(vapply(release$files,`[[`,character(1),"path"),"wy2026-release.json")
archive<-file.path(normalizePath("data/diagnostics",winslash="/",mustWork=TRUE),"swc-daily-explorer-wy2026.tar.gz")
if(file.exists(paste0(archive,".sha256")))file.remove(paste0(archive,".sha256"))
message("Packaging ",length(files)," publication files. This may take several minutes.")
local({
  previous<-getwd();on.exit(setwd(previous),add=TRUE);setwd(directory)
  withCallingHandlers(utils::tar(archive,files=files,compression="gzip",tar="internal"),warning=function(w) {
    if(startsWith(conditionMessage(w),"storing paths of more than 100 bytes is not portable"))invokeRestart("muffleWarning")
  })
})
entries<-utils::untar(archive,list=TRUE,tar="internal")
if(!setequal(entries,files)||length(entries)!=length(files))stop("Tar entry list differs from verified WY2026 release.")
# Detect changes while packaging before supplying a usable checksum sidecar.
for(f in release$files)if(!identical(f$md5,unname(tools::md5sum(file.path(directory,f$path)))))stop("Release changed during packaging: ",f$path)
if(!identical(release,jsonlite::read_json(file.path(directory,"wy2026-release.json"))))stop("Release marker changed during packaging.")
hash<-digest::digest(file=archive,algo="sha256")
writeBin(charToRaw(paste0(hash,"  ",basename(archive),"\n")),paste0(archive,".sha256"))
message("PASS: exact bundle entry list and source hashes; ",length(entries)," files; ",round(file.info(archive)$size/1024^3,2)," GiB.")
message("Transfer ",archive," and its .sha256 file. Raw grids and working caches are unnecessary.")
