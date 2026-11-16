# Run on the laptop after reviewing the local viewer. No network access.
source("scripts/prepare-interactive-map-staging-seed.R")
local({
  archive <- file.path(normalizePath("data/diagnostics",winslash="/"),"swc-interactive-monthly-seed.tar.gz")
  previous <- setwd("data/diagnostics/interactive-map-staging-seed")
  on.exit(setwd(previous),add=TRUE)
  manifest <- jsonlite::read_json("manifest.json")
  files <- c("manifest.json","boundaries.json",unlist(lapply(manifest$layers,function(x)c(x$file,paste0(x$file,".md5")))))
  # R's internal tar handles Windows drive letters without GNU tar's remote-host parsing.
  utils::tar(archive,files=files,compression="gzip",tar="internal")
  writeBin(charToRaw(paste0(digest::digest(archive,algo="sha256",file=TRUE),"  ",basename(archive),"\n")),paste0(archive,".sha256"))
  message("Transfer ",archive," and its .sha256 file (",round(file.info(archive)$size/1024^2,1)," MiB archive).")
})
