# Update the standard Station Conditions snapshot from existing station caches.
# No downloads, recalculation of period rankings, site staging or publication.
source("R/config.R")
source("R/acis-station-inventory.R")
source("R/acis-station-daily-pilot.R")
source("R/acis-station-current-prototype.R")
source("R/acis-station-monthly-climatology.R")

station_climatology_directory<-file.path(swc_acis_station_dir,"station-explorer-prototype")
station_climatology_rows<-read.csv(file.path(station_climatology_directory,"station-explorer-data.csv"),stringsAsFactors=FALSE)
station_climatology_snapshot<-unique(station_climatology_rows$as_of)
stopifnot(length(station_climatology_snapshot)==1L)
station_climatology_cache<-"data/processed/acis-stations/monthly-climatology"
dir.create(station_climatology_cache,recursive=TRUE,showWarnings=FALSE)
# Reuse the reviewed local pilot caches when available. Fingerprints still
# verify their station, cutoff, screening version and historical inputs.
station_climatology_seeds<-list.files("data/diagnostics/station-monthly-climatology-cache",pattern="^[0-9]+(-record)?\\.rds$",full.names=TRUE)
for(path in station_climatology_seeds) {
  target<-file.path(station_climatology_cache,basename(path))
  if(!file.exists(target)&&!file.copy(path,target))stop("Could not seed monthly reference cache.")
}
station_climatology_uids<-unique(station_climatology_rows$uid)
station_climatology_report<-vector("list",length(station_climatology_uids))
for(i in seq_along(station_climatology_uids)) {
  uid<-station_climatology_uids[i]
  path<-file.path(station_climatology_directory,"station-details",paste0(uid,".json"))
  detail<-jsonlite::read_json(path,simplifyVector=TRUE)
  stopifnot(as.integer(detail$uid)==as.integer(uid),detail$as_of==station_climatology_snapshot)
  cache<-acis_station_read_daily_cache(acis_station_daily_cache_path(uid),uid)
  monthly<-prepare_acis_station_monthly_reference(cache,uid,station_climatology_snapshot,station_climatology_cache)
  detail$monthly_climatology<-monthly$reference
  validate_acis_station_monthly_detail(detail,uid,station_climatology_snapshot)
  jsonlite::write_json(detail,path,auto_unbox=TRUE,dataframe="rows",na="null",null="null",digits=7)
  station_climatology_report[[i]]<-data.frame(uid,as_of=station_climatology_snapshot,
    reference_reused=monthly$reused[["reference"]],record_reused=monthly$reused[["record"]])
  if(i%%10L==0L||i==length(station_climatology_uids))message("Station climatology integration: ",i,"/",length(station_climatology_uids))
}
station_climatology_report<-do.call(rbind,station_climatology_report)
write.csv(station_climatology_report,file.path(station_climatology_cache,"update-summary.csv"),row.names=FALSE)
source("scripts/refresh-acis-station-explorer-preview.R")
source("R/acis-station-site.R")
station_climatology_checked<-swc_station_beta_snapshot(station_climatology_directory)
message(sprintf("Integrated Station Conditions ready: %d stations; %d baseline and %d full-record references reused. No publication.",
  station_climatology_checked$stations,sum(station_climatology_report$reference_reused),sum(station_climatology_report$record_reused)))
