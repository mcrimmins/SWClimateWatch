# Portable public USGS caches only; excludes project secrets and other datasets.
streamflow_transfer_tar <- function() {
  paths<-c(if(.Platform$OS.type=="windows")file.path(Sys.getenv("SystemRoot","C:/Windows"),"System32/tar.exe"),unname(Sys.which("tar")))
  paths<-paths[nzchar(paths)&file.exists(paths)];if(!length(paths))stop("tar is required to verify the transfer package.")
  paths[[1]]
}
streamflow_transfer_paths <- function() {
  roots<-c("data/raw/streamflow-pilot","data/raw/streamflow-statistics","data/diagnostics/streamflow-network-pilot")
  sort(unlist(lapply(roots,function(d){if(!dir.exists(d))stop("Missing streamflow input: ",d);list.files(d,recursive=TRUE,full.names=TRUE)}),use.names=FALSE))
}
streamflow_transfer_safe <- function(path) {
  is.character(path)&&length(path)==1L&&!is.na(path)&&grepl("^[A-Za-z0-9_./-]+$",path)&&
    !any(strsplit(path,"/",fixed=TRUE)[[1]]%in%c(".","..",""))&&
    grepl("^data/(raw/(streamflow-pilot|streamflow-statistics)/|diagnostics/streamflow-network-pilot/)",path)
}
export_streamflow_transfer <- function() {
  paths<-streamflow_transfer_paths();if(!length(paths)||!all(vapply(paths,streamflow_transfer_safe,logical(1))))stop("Invalid transfer input paths.")
  message("Packing ",length(paths)," public streamflow cache files; no archive maps are included...")
  root<-normalizePath(".",winslash="/",mustWork=TRUE)
  out<-file.path(root,"data/diagnostics/streamflow-transfer");dir.create(out,recursive=TRUE,showWarnings=FALSE)
  work<-tempfile("export-",tmpdir=out);dir.create(work)
  for(p in paths){dir.create(dirname(file.path(work,p)),recursive=TRUE,showWarnings=FALSE);if(!file.copy(p,file.path(work,p)))stop("Copy failed: ",p)}
  rows<-lapply(paths,function(p)list(path=p,bytes=unname(file.info(p)$size),sha256=digest::digest(file=p,algo="sha256",serialize=FALSE)))
  jsonlite::write_json(list(schema_version=1L,files=rows),file.path(work,"streamflow-transfer.json"),auto_unbox=TRUE,pretty=TRUE)
  bundle<-file.path(out,"swc-streamflow-seed.tar.gz")
  old<-getwd();on.exit(setwd(old),add=TRUE);setwd(work)
  utils::tar(bundle,files=c("streamflow-transfer.json",paths),compression="gzip",tar=streamflow_transfer_tar(),extra_flags="--format=ustar")
  setwd(old)
  hash<-digest::digest(file=bundle,algo="sha256",serialize=FALSE)
  writeLines(paste(hash,basename(bundle),sep="  "),paste0(bundle,".sha256"))
  message("Verifying package extraction and file checksums...")
  result<-verify_streamflow_transfer(bundle)
  print(data.frame(files=nrow(result),bytes=sum(result$bytes),package_bytes=file.info(bundle)$size))
  message("Verified cache package: ",bundle)
  invisible(bundle)
}
verify_streamflow_transfer <- function(bundle,extract_dir=NULL) {
  bundle<-normalizePath(bundle,winslash="/",mustWork=TRUE)
  checksum<-paste0(bundle,".sha256");if(!file.exists(checksum))stop("Missing transfer checksum sidecar.")
  expected<-strsplit(readLines(checksum,warn=FALSE)[1],"[[:space:]]+")[[1]][1]
  if(!grepl("^[a-f0-9]{64}$",expected)||!identical(expected,digest::digest(file=bundle,algo="sha256",serialize=FALSE)))stop("Transfer package checksum mismatch.")
  tar<-streamflow_transfer_tar()
  entries<-utils::untar(bundle,list=TRUE,tar=tar)
  if(anyDuplicated(entries)||!"streamflow-transfer.json"%in%entries||!all(vapply(setdiff(entries,"streamflow-transfer.json"),streamflow_transfer_safe,logical(1))))stop("Unsafe transfer archive entries.")
  # Reject links and other special entry types before extracting any archive.
  listing<-system2(tar,c("-tzvf",shQuote(bundle)),stdout=TRUE,stderr=TRUE)
  if((!is.null(attr(listing,"status"))&&attr(listing,"status")!=0L)||length(listing)!=length(entries)||any(!startsWith(listing,"-")))stop("Transfer must contain regular files only.")
  if(is.null(extract_dir)){extract_dir<-tempfile("streamflow-import-");dir.create(extract_dir)}
  utils::untar(bundle,exdir=extract_dir,tar=tar)
  manifest<-jsonlite::read_json(file.path(extract_dir,"streamflow-transfer.json"))
  if(!identical(manifest$schema_version,1L)||!length(manifest$files))stop("Invalid transfer manifest.")
  paths<-vapply(manifest$files,`[[`,character(1),"path")
  if(anyDuplicated(paths)||!setequal(paths,setdiff(entries,"streamflow-transfer.json")))stop("Transfer manifest differs from archive files.")
  for(f in manifest$files){if(!streamflow_transfer_safe(f$path))stop("Unsafe cache destination.");p<-file.path(extract_dir,f$path)
    if(!file.exists(p)||file.info(p)$isdir||file.info(p)$size!=f$bytes||!identical(f$sha256,digest::digest(file=p,algo="sha256",serialize=FALSE)))stop("Transfer file differs: ",f$path)}
  rows<-do.call(rbind,lapply(manifest$files,as.data.frame,stringsAsFactors=FALSE));attr(rows,"extract_dir")<-extract_dir;rows
}
import_streamflow_transfer <- function(bundle,apply=FALSE) {
  rows<-verify_streamflow_transfer(bundle);work<-attr(rows,"extract_dir")
  if(!apply){print(data.frame(status="VERIFIED",files=nrow(rows),bytes=sum(rows$bytes),applied=FALSE));return(invisible(rows))}
  source("R/streamflow-staging.R",local=TRUE);streamflow_staging_guard()
  backup<-file.path("data/diagnostics/streamflow-transfer/import-backups",format(Sys.time(),"%Y%m%dT%H%M%S"))
  copied<-0L;reused<-0L
  for(p in rows$path){src<-file.path(work,p)
    if(file.exists(p)&&identical(digest::digest(file=p,algo="sha256",serialize=FALSE),digest::digest(file=src,algo="sha256",serialize=FALSE))){reused<-reused+1L;next}
    if(file.exists(p)){b<-file.path(backup,p);dir.create(dirname(b),recursive=TRUE,showWarnings=FALSE);if(!file.copy(p,b))stop("Cannot preserve existing cache: ",p)}
    dir.create(dirname(p),recursive=TRUE,showWarnings=FALSE);if(!file.copy(src,p,overwrite=TRUE))stop("Cannot import cache: ",p);copied<-copied+1L
  }
  message("Verified cache import: ",copied," copied, ",reused," identical; existing differing files preserved under ",backup)
  invisible(rows)
}
