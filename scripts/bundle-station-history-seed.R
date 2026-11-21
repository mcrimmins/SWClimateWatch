# Portable cache seed only. Does not contain station raw caches or rendered pages.
source("R/station-custom-dates-pilot.R")
root <- station_custom_pilot_root()
summary <- read.csv(file.path(root,"update-summary.csv"))
if (!identical(summary$status,"READY")) stop("Complete the historical pilot build before bundling.")
archive <- "swc-station-history-seed.tar.gz"
tar <- if (.Platform$OS.type == "windows") file.path(Sys.getenv("SystemRoot","C:/Windows"),"System32/tar.exe") else unname(Sys.which("tar"))
if (!file.exists(tar)) stop("Native tar was not found.")
status <- system2(tar,c("-czf",archive,"-C",root,"catalog.json","update-summary.csv","history"))
if (status != 0L) stop("Historical seed archive creation failed.")
hash <- digest::digest(file=archive,algo="sha256")
writeBin(charToRaw(paste0(hash,"  ",basename(archive),"\n")),paste0(archive,".sha256"))
message("Ready: ",archive," (",round(file.info(archive)$size/1024^2,1)," MiB) and ",archive,".sha256")
